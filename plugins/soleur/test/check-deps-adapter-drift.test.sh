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

# Each case gets an isolated install dir so a failure in one case cannot
# cascade through shared state into the next case's assertions.

# --- Case 1: installed adapter matches repo → no drift, exit 0 ---
case1_dir="$tmp_dir/case1"
mkdir -p "$case1_dir"
scripts_dir="$REPO_ROOT/plugins/soleur/skills/pencil-setup/scripts"
cp "$scripts_dir"/*.mjs "$case1_dir/"
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
cp "$scripts_dir"/*.mjs "$case2b_dir/"
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
cp "$scripts_dir"/*.mjs "$case2c_dir/"
rm "$case2c_dir/pencil-repl-surface.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2c_dir" bash "$CHECK_DEPS" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "3" "$rc" "missing sibling: exit 3"
assert_contains "$out" "pencil-repl-surface.mjs" "missing sibling: names the missing module"

# --- Case 2c: an unparseable module list is an error, never a clean OK ---
case2c_scripts="$tmp_dir/case2c-scripts"
case2c_dir="$tmp_dir/case2c"
mkdir -p "$case2c_scripts" "$case2c_dir"
cp "$CHECK_DEPS" "$case2c_scripts/check_deps.sh"
cp "$repo_adapter" "$case2c_scripts/pencil-mcp-adapter.mjs"
cp "$repo_adapter" "$case2c_dir/pencil-mcp-adapter.mjs"
echo "# no module list here" > "$case2c_scripts/copy_adapter.sh"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case2c_dir" bash "$case2c_scripts/check_deps.sh" --check-adapter-drift 2>&1)
rc=$?
set -e
assert_eq "2" "$rc" "empty module list: exit 2"
assert_contains "$out" "no adapter modules parsed" "empty module list: says why"

# --- Case 3: --auto re-copies and then exits 0 ---
case3_dir="$tmp_dir/case3"
mkdir -p "$case3_dir"
cp "$repo_adapter" "$case3_dir/pencil-mcp-adapter.mjs"
echo "// drift" >> "$case3_dir/pencil-mcp-adapter.mjs"
set +e
out=$(PENCIL_ADAPTER_INSTALL_DIR="$case3_dir" bash "$CHECK_DEPS" --check-adapter-drift --auto 2>&1)
rc=$?
set -e
assert_eq "0" "$rc" "--auto re-copy: exit 0"
installed_sha=$(sha256sum "$case3_dir/pencil-mcp-adapter.mjs" | awk '{print $1}')
repo_sha=$(sha256sum "$repo_adapter" | awk '{print $1}')
assert_eq "$repo_sha" "$installed_sha" "--auto re-copy: installed sha now matches repo"

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
TREE="$SCRIPT_DIR/lib/pen-identity-tree.mjs"
CASES="$SCRIPT_DIR/fixtures/pen-identity-cases.tsv"
PEN_VALID_KEY="valid-key"   # the fake engine in lib/pen-identity-tree.mjs accepts exactly this

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
    assert_contains "$out" "auth failed" "auth: $label -> says auth failed"
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
cp "$scripts_dir"/*.mjs "$home/.local/share/pencil-adapter/"
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
} > "$FAKE_NPM_LOG"
node "$FAKE_TREE_HELPER" "$HOME" good >/dev/null
FAKE_NPM
chmod 0755 "$home/fakenode/npm"
set +e
out=$(env -u PEN_CLI_KEY -u PENCIL_CLI_KEY HOME="$home" NVM_DIR="$home/.nvm" FNM_DIR="$home/.fnm" \
  PEN_CLI_KEY=synthetic-canary-1 PENCIL_CLI_KEY=synthetic-canary-2 \
  FAKE_NPM_LOG="$home/npm.log" FAKE_TREE_HELPER="$TREE" FAKE_NODE="$home/fakenode/node" \
  bash -c 'f="$1"; set --; source "$f"; AUTO_INSTALL=true; find_node22() { echo "$FAKE_NODE"; }; attempt_headless_install; echo "install_rc=$?"; detect_headless_cli; echo "detect_rc=$?"' _ "$CHECK_DEPS" 2>&1 </dev/null)
set -e
assert_contains "$out" "install_rc=0" "install: attempt_headless_install succeeds"
assert_contains "$out" "detect_rc=0" "install: the installed tree is detected"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "ARGS=ci --ignore-scripts" "install: npm ci with scripts ignored"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "CWD=$home/.local/share/pen-cli" "install: runs inside the pen-cli prefix"
assert_contains "$(cat "$home/npm.log" 2>/dev/null)" "CRED_VARS=0" "install: neither credential name reaches npm"
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

print_results 116
