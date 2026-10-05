#!/usr/bin/env bash
# test-scratch-residue.sh -- Guard 1 canary for the dev-machine scratch leak (#9117 / plan
# 2026-10-01-fix-dev-machine-disk-leak-scratch-and-cache-cleanup).
#
# PROPERTY. A test runner started DIRECTLY (not through scripts/test-all.sh, which already binds a
# per-run soleur-run.<pid>.* root) leaves no new entry in its TMPDIR base after a normal exit or
# SIGTERM, including the soleur-inc-* incident sandbox. A SIGKILLed runner leaves only an entry the
# reapers can attribute (marker-bearing soleur-run.<pid>.* root, classified marker:<pid>).
#
# LEAVES. The eight directly-run suites measured leaking on main (6 bun TS suites, grep-rewrite,
# test-weakness-miner) PLUS one bun suite run from plugins/soleur (its own bunfig preload), one shell
# suite that sources test-helpers.sh (its normal-exit leaf), one `python -m unittest` module, the pytest
# chokepoint hook (pytest itself is not installed on every host, so the hook pytest calls is driven
# directly: pytest_configure is the whole of the conftest chokepoint) and two vitest leaves -- one
# existing test and one GENERATED test that really mkdtemp's and leaks if the root is unbound.
#
# PROBES (beyond the leaves): SIGTERM/SIGINT/SIGKILL per runtime, the marker contract and a byte/mode
# PARITY pin across the three writers (with drifted-copy controls), the python fork guard,
# SOLEUR_KEEP_SCRATCH, the TMPDIR sub-path normalisation, and nesting validation for bun AND python
# (no marker / dead owner / pid 0 / foreign pid namespace / symlinked root are never adopted).
#
# EVERY LEAF RUNS TWICE. (Shell leaves are counted with a PATH shim that logs each mktemp call and
# then runs the real one: a shell leaf that cleans up after itself leaves nothing to count at exit.)
#   delta arm:    TMPDIR=<private base>, SOLEUR_SCRATCH_SESSION_ROOT unset. rc must be 0 and the
#                 base must gain zero entries (compared as a DELTA, so a pre-seeded base is fine).
#   counting arm: same leaf, but a valid owned root is handed in (the nested-runner shape). The leaf
#                 must have created >= 1 entry in it -- a leaf that creates nothing proves nothing
#                 (anti-vacuity) -- and must NOT delete the parent root it did not create.
#
# The measured base is ALWAYS a private mktemp dir this suite removes itself; the real /tmp and
# /var/tmp are never measured or touched. Every runtime is started with TMPFS_GUARD_SCRATCH_BASES
# pointed at a path that matches nothing, because the private base lives under /tmp and the TS/python
# runtimes normalise a TMPDIR that sits INSIDE a standard base up to that base (the shell does the
# same): without that, every root would land in the operator's real /tmp.
#
# FLOORS ARE DERIVED, NOT TYPED. `ran` must equal the registered leaf count, the case floor is
# FIXED_CASES + 4 per registered leaf, and every member of the CHOKEPOINT_FILES + PRELOAD_FILES
# registry in .claude/hooks/incident-sandbox-coverage.test.sh must map to a registered leaf: a leaf
# dropped (or a chokepoint added) without its counterpart is a FAIL, not a smaller green.
#
# Entry names allowed to persist in a base, because the runtime itself (not Soleur code) owns them
# and they are one shared cache, not per-run growth: node-compile-cache (node >= 22 module cache).

set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$REPO_ROOT" || exit 1

BASE="$(mktemp -d "${TMPDIR:-/tmp}/scratch-residue.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 1; }
# Canonical assert_fixture_dir -- byte-identical copy (fixture-scan.py requires it); do not reword.
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
BG_PIDS=()
STD_NONE="/nonexistent-std-base"   # TMPFS_GUARD_SCRATCH_BASES value that matches no TMPDIR (see header)
cleanup() {
  local p
  for p in "${BG_PIDS[@]:-}"; do [[ -n "$p" ]] && kill -KILL "$p" 2>/dev/null; done
  assert_fixture_dir "$BASE"
  rm -rf "$BASE"
}
trap cleanup EXIT

PASS=0; FAIL=0; CASES=0
verdict() { # <0|1> <label>
  CASES=$((CASES + 1))
  if [[ "$1" == "0" ]]; then PASS=$((PASS + 1)); echo "  PASS: $2"; else FAIL=$((FAIL + 1)); echo "  FAIL: $2"; fi
}
# Self-check (harness row H0): drive verdict() once with a passing and once with a FAILING input and
# require the counters to move. A neutered verdict (`if true`) would otherwise let every arm read
# green. Reported with printf + exit, never through the helper under test; counters are restored.
_p=$PASS; _f=$FAIL; _c=$CASES
verdict 0 "self-check pass" >/dev/null; verdict 1 "self-check fail" >/dev/null
if [[ $((PASS - _p)) -ne 1 || $((FAIL - _f)) -ne 1 || $((CASES - _c)) -ne 2 ]]; then
  printf '[FATAL] verdict() is not counting (pass+%d fail+%d cases+%d)\n' $((PASS - _p)) $((FAIL - _f)) $((CASES - _c)) >&2
  exit 1
fi
PASS=$_p; FAIL=$_f; CASES=$_c
unset _p _f _c

# shellcheck source=../../scripts/lib/scratch-root.sh
source "$REPO_ROOT/scripts/lib/scratch-root.sh"

TMO=""
for _t in timeout gtimeout; do command -v "$_t" >/dev/null 2>&1 && { TMO="$_t"; break; }; done
unset _t
_run_bounded() { # <secs> cmd...
  local s="$1"; shift
  if [[ -n "$TMO" ]]; then "$TMO" "$s" "$@"; else "$@"; fi
}

# --- measurement primitives ---------------------------------------------------------------------
# The ONLY names tolerated in a base: the runtime's own shared module cache (node >= 22), not per-run
# growth. Pinned by H2c below with a fixture: a leaked soleur-inc-*/soleur-run.* must still fail.
ALLOW_RE='^(node-compile-cache)$'

# entries <dir>: the names in <dir>, one per line (the listing IS the measurement; names are never
# re-fed to another command, which is what SC2010 guards against).
# shellcheck disable=SC2010
entries() { ls -A "$1" 2>/dev/null; }

# snapshot <dir> <outfile>: sorted entry names. rc 2 if the base does not exist -- a missing base must
# never read as an empty one (harness row H1).
snapshot() {
  [[ -d "$1" ]] || return 2
  { entries "$1" | grep -Ev "$ALLOW_RE" || true; } | sort > "$2"
}
# new_since <dir> <snapfile>: names now present that were not in the snapshot. rc 2 on a missing base
# (harness row H1b drives THIS path, not just snapshot).
new_since() {
  local now="$1.now.$$"
  snapshot "$1" "$now" || return 2
  comm -13 "$2" "$now"
  rm -f "$now"
}

# bounded_wait <pid> <secs>: wait for a child, SIGKILLing it after <secs>. Sets BW_RC (137 = it had to
# be killed). An unbounded `wait` hangs the whole suite when a handler never re-raises its signal;
# bounded, that shape is a FAIL (harness row H4).
BW_RC=0
bounded_wait() {
  local p="$1" wd
  ( trap 'kill "$s" 2>/dev/null; exit 0' TERM; sleep "$2" & s=$!; wait "$s"; kill -KILL "$p" 2>/dev/null ) &
  wd=$!
  wait "$p" 2>/dev/null; BW_RC=$?
  kill -TERM "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return 0
}

SCRUB=(-u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE
       -u INCIDENTS_REPO_ROOT -u SOLEUR_TEST_INCIDENT_ROOT -u SOLEUR_KEEP_SCRATCH)

# run_leaf <tmpdir> <logfile> <cmdstring> [extra env assignments...]: run a leaf from the repo root
# with the scratch/incident env scrubbed and TMPDIR pointed at <tmpdir>. The log lives OUTSIDE the
# measured base so it is never counted as a created entry.
run_leaf() {
  local base="$1" log="$2" cmd="$3"; shift 3
  assert_fixture_dir "$base"; assert_fixture_dir "$log"
  _run_bounded 240 env "${SCRUB[@]}" TMPFS_GUARD_SCRATCH_BASES="$STD_NONE" \
    TMPDIR="$base" "$@" bash -c "$cmd" > "$log" 2>&1
}

# --- generated vitest leaf ------------------------------------------------------------------------
# A direct `vitest run <existing test>` allocates nothing of its own, so deleting the
# ensureScratchSession() call from the globalSetup left the canary green. This leaf is a test that
# REALLY mkdtemp's and leaves the directory behind: rooted, it lands in the session root and is
# removed with it; unrooted, it leaks into the TMPDIR base and the delta arm reds. It is generated
# into the private base (not committed under apps/web-platform/test, where it would be a test that
# deliberately leaks) and pointed at the production globalSetup. RESIDUE_VT_GLOBAL_SETUP is the
# mutation seam: run the canary against a mutated COPY of that file without touching the original.
VT_GLOBAL_SETUP="${RESIDUE_VT_GLOBAL_SETUP:-$REPO_ROOT/apps/web-platform/test/global-setup-git-tripwire.ts}"
assert_fixture_dir "$BASE"
mkdir -p "$BASE/vt"
cat > "$BASE/vt/leak.test.ts" <<'EOF'
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
test("allocates a scratch dir and leaves it behind", () => {
  const d = mkdtempSync(join(tmpdir(), "vt-leak-"));
  writeFileSync(join(d, "f"), "x");
  expect(d.length).toBeGreaterThan(0);
});
EOF
cat > "$BASE/vt/vitest.config.mjs" <<EOF
export default { test: { globals: true, root: "$BASE/vt", include: ["leak.test.ts"], globalSetup: ["$VT_GLOBAL_SETUP"] } };
EOF

# --- the leaf set --------------------------------------------------------------------------------
LEAF_NAMES=()
LEAF_CMDS=()
LEAF_KINDS=()    # sh = counted by the mktemp shim; rt = counted by the entries left in the adopted root
LEAF_NEEDLES=()  # optional glob: anti-vacuity counts entries the LEAF made (not the chokepoint's own soleur-inc-*)
SKIPPED_LEAVES=()
add_leaf() { LEAF_NAMES+=("$1"); LEAF_CMDS+=("$2"); LEAF_KINDS+=("${3:-rt}"); LEAF_NEEDLES+=("${4:-}"); }
add_leaf bun-kb-coverage        'bun test plugins/soleur/test/kb-coverage.test.ts'
add_leaf bun-gdpr-gate          'bun test plugins/soleur/test/gdpr-gate.test.ts'
add_leaf bun-legal-template     'bun test plugins/soleur/test/legal-template-vendor-surface.test.ts'
add_leaf bun-plan-skeleton      'bun test plugins/soleur/test/plan-skeleton-checkpoint.test.ts'
add_leaf bun-runtime-plugin     'bun test plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts'
add_leaf bun-ship-pir-gate      'bun test plugins/soleur/test/ship-incident-pir-gate.test.ts'
# plugins/soleur/bunfig.toml registers its own preload, resolved from the INVOCATION cwd.
add_leaf bun-plugin-cwd         'cd plugins/soleur && bun test test/kb-coverage.test.ts'
add_leaf sh-grep-rewrite        'bash .claude/hooks/grep-rewrite.test.sh' sh
add_leaf sh-weakness-miner      'bash tests/scripts/test-weakness-miner.sh' sh
# Sources plugins/soleur/test/test-helpers.sh (the shell chokepoint): the normal-exit leaf for it.
add_leaf sh-test-helpers        'bash plugins/soleur/test/auto-close-scanner.test.sh' sh
# test-all.sh binds its run root ~2900 lines above its full EXIT trap, so every early exit (flag modes, usage
# errors) used to leave a marker-only root per invocation; a mutation battery driving it thousands of times
# left 2388 in /var/tmp. --enumerate-commands exits 0 through the enumerate path, not the full trap.
add_leaf sh-test-all-enumerate  'bash scripts/test-all.sh --enumerate-commands' sh
add_leaf py-unittest            'python3 -m unittest tests.scripts.test_lint_rule_ids'
add_leaf py-pytest-configure    'python3 -c "import tests.conftest as c; c.pytest_configure()"'
VITEST_BIN="$REPO_ROOT/apps/web-platform/node_modules/.bin/vitest"
VITEST_ABSENT=0
if [[ -x "$VITEST_BIN" ]]; then
  add_leaf vitest-direct        'cd apps/web-platform && ./node_modules/.bin/vitest run test/abort-classifier.test.ts'
  add_leaf vitest-leak          "cd apps/web-platform && ./node_modules/.bin/vitest run --config '$BASE/vt/vitest.config.mjs'" rt 'vt-leak-*'
else
  VITEST_ABSENT=1
  SKIPPED_LEAVES=(vitest-direct vitest-leak)
  # LOUD, on both streams: a green run without the vitest chokepoint must not read as full coverage.
  printf '  SKIP (LOUD): apps/web-platform/node_modules/.bin/vitest absent -- the vitest chokepoint (global-setup-git-tripwire.ts) is NOT exercised on this host\n'
  printf 'SKIP (LOUD): vitest leaf not run (no apps/web-platform/node_modules); SOLEUR_REQUIRE_VITEST=%s\n' "${SOLEUR_REQUIRE_VITEST:-<unset>}" >&2
fi
N_LEAVES=${#LEAF_NAMES[@]}
N_SKIPPED=${#SKIPPED_LEAVES[@]}

# --- the chokepoint registry the canary must cover ------------------------------------------------
# The SAME registry incident-sandbox-coverage.test.sh asserts over (CHOKEPOINT_FILES + PRELOAD_FILES),
# read from that file rather than re-typed: a chokepoint added there without a leaf here is a FAIL.
COV_TEST="$REPO_ROOT/.claude/hooks/incident-sandbox-coverage.test.sh"
registry_members() {
  sed -n '/^CHOKEPOINT_FILES=(/,/^)/p;/^PRELOAD_FILES=(/,/^)/p' "$COV_TEST" | grep -oE '"[^"]+"' | tr -d '"'
}
# The leaf that exercises each registry member. The shell hooks lib is a chokepoint too (it is not in
# the registry because it is not a CHOKEPOINT_FILES predicate target, but it allocates soleur-inc-*).
leaf_for_file() {
  case "$1" in
    plugins/soleur/test/lib/git-tripwire.ts|bunfig.toml) echo bun-kb-coverage ;;
    plugins/soleur/bunfig.toml)                          echo bun-plugin-cwd ;;
    apps/web-platform/test/global-setup-git-tripwire.ts) echo vitest-leak ;;
    plugins/soleur/test/test-helpers.sh)                 echo sh-test-helpers ;;
    .claude/hooks/lib/test-incident-sandbox.sh)          echo sh-grep-rewrite ;;
    tests/conftest.py)                                   echo py-pytest-configure ;;
    tests/scripts/_git_fixture_env.py)                   echo py-unittest ;;
    *) echo "" ;;
  esac
}
in_list() { # <needle> <list...>
  local n="$1" e; shift
  for e in "$@"; do [[ "$e" == "$n" ]] && return 0; done
  return 1
}

# --- harness rows (the canary's own instruments, proven before they are trusted) -----------------
echo "== harness rows"
# H1: a nonexistent base is an error, not an empty base -- through snapshot AND through new_since.
snapshot "$BASE/does-not-exist" "$BASE/h1.snap" 2>/dev/null; h1_rc=$?
verdict "$([[ "$h1_rc" == "2" ]] && echo 0 || echo 1)" "H1: a missing base is an error (rc=$h1_rc), never read as empty"
assert_fixture_dir "$BASE"
: > "$BASE/h1b.snap"
h1b_out="$(new_since "$BASE/does-not-exist" "$BASE/h1b.snap" 2>/dev/null)"; h1b_rc=$?
verdict "$([[ "$h1b_rc" != "0" && -z "$h1b_out" ]] && echo 0 || echo 1)" "H1b: new_since against a missing base is an error too (rc=$h1b_rc), not an empty delta"
# H2: pre-seeded base -- the delta, not absolute emptiness, is compared (must PASS).
assert_fixture_dir "$BASE"
mkdir -p "$BASE/h2" && : > "$BASE/h2/unrelated-entry"
snapshot "$BASE/h2" "$BASE/h2.snap"
TMPDIR="$BASE/h2" bash -c 'd=$(mktemp -d); touch "$d/x"; rm -f "$d/x"; rmdir "$d"'
h2_new="$(new_since "$BASE/h2" "$BASE/h2.snap")"
verdict "$([[ -z "$h2_new" ]] && echo 0 || echo 1)" "H2: a pre-seeded base with a leaf that cleans up after itself has delta 0"
# H2b: and the same instrument DOES see a leak (the delta is not blind).
TMPDIR="$BASE/h2" bash -c 'd=$(mktemp -d); touch "$d/x"'
h2b_new="$(new_since "$BASE/h2" "$BASE/h2.snap")"
verdict "$([[ -n "$h2b_new" ]] && echo 0 || echo 1)" "H2b: the delta detector sees a leaking leaf (not vacuous)"
# H2c: the allowlist is the minimal documented set. A leaked soleur-inc-* / soleur-run.* entry is the
# exact residue this canary exists to catch and must NOT be allow-listed; node-compile-cache must be.
mkdir -p "$BASE/h2c"; snapshot "$BASE/h2c" "$BASE/h2c.snap"
mkdir -p "$BASE/h2c/soleur-inc-LEAKED" "$BASE/h2c/soleur-run.1.LEAKEDXX" "$BASE/h2c/node-compile-cache"
h2c_new="$(new_since "$BASE/h2c" "$BASE/h2c.snap" | tr '\n' ' ')"
verdict "$([[ "$h2c_new" == "soleur-inc-LEAKED soleur-run.1.LEAKEDXX " ]] && echo 0 || echo 1)" "H2c: allowlist pinned -- a leaked soleur-inc-*/soleur-run.* fails the delta, node-compile-cache does not (saw: ${h2c_new:-<none>})"
# H4: bounded_wait turns a hang into a bounded FAIL instead of hanging the suite.
sleep 30 & h4_pid=$!; BG_PIDS+=("$h4_pid")
h4_start=$SECONDS; bounded_wait "$h4_pid" 1; h4_el=$((SECONDS - h4_start))
verdict "$([[ "$BW_RC" == "137" && "$h4_el" -le 5 ]] && echo 0 || echo 1)" "H4: bounded_wait kills a hung child and returns (rc=$BW_RC after ${h4_el}s)"
# H3: a no-op leaf must be flagged vacuous by the counting instrument.
count_created() { # <base> <root> -> number of entries a leaf created (base entries other than root + root entries other than marker)
  local base="$1" root="$2" n=0 e
  while IFS= read -r e; do
    [[ -n "$e" && "$base/$e" != "$root" ]] && n=$((n + 1))
  done < <(entries "$base" | grep -Ev "$ALLOW_RE")
  while IFS= read -r e; do
    [[ -n "$e" && "$e" != ".soleur-owned" ]] && n=$((n + 1))
  done < <(ls -A "$root" 2>/dev/null)
  echo "$n"
}
mk_parent_root() { # <base> -> prints a valid owned soleur-run root (pid = this suite, alive)
  local base="$1" r
  mkdir -p "$base"
  r="$(mktemp -d "$base/soleur-run.$$.XXXXXXXX")" || return 1
  SOLEUR_SCRATCH_OWNER_PID="$$" soleur_scratch_mark_owned "$r" || return 1
  printf '%s' "$r"
}
assert_fixture_dir "$BASE"
mkdir -p "$BASE/h3"; h3_root="$(mk_parent_root "$BASE/h3")"
n_noop="$(count_created "$BASE/h3" "$h3_root")"
verdict "$([[ "$n_noop" == "0" ]] && echo 0 || echo 1)" "H3: a no-op runtime leaf creates 0 entries, so the anti-vacuity check would reject it"

# The counting shim for shell leaves: log one line per mktemp call, then run the real one. A shell
# leaf that cleans up after itself leaves nothing to count at exit, so entries cannot prove it ran.
REAL_MKTEMP="$(command -v mktemp)"
assert_fixture_dir "$BASE"
mkdir -p "$BASE/shim"
cat > "$BASE/shim/mktemp" <<'SHIMEOF'
#!/bin/sh
printf 'x\n' >> "$SOLEUR_SHIM_LOG"
exec "$SOLEUR_REAL_MKTEMP" "$@"
SHIMEOF
export SOLEUR_REAL_MKTEMP="$REAL_MKTEMP"
chmod +x "$BASE/shim/mktemp"
shim_count() { if [[ -f "$1" ]]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
assert_fixture_dir "$BASE"
: > "$BASE/h3.shimlog"
env PATH="$BASE/shim:$PATH" SOLEUR_SHIM_LOG="$BASE/h3.shimlog" bash -c 'true'
n_noop_sh="$(shim_count "$BASE/h3.shimlog")"
env PATH="$BASE/shim:$PATH" SOLEUR_SHIM_LOG="$BASE/h3.shimlog" bash -c 'd=$(mktemp -d); rmdir "$d"'
n_real_sh="$(shim_count "$BASE/h3.shimlog")"
verdict "$([[ "$n_noop_sh" == "0" && "$n_real_sh" == "1" ]] && echo 0 || echo 1)" "H3: the mktemp shim counts 0 for a no-op shell leaf and 1 for a real allocation (got $n_noop_sh, $n_real_sh)"

# --- registry coverage: every chokepoint the incident-sandbox canary lists has a registered leaf ---
echo "== registry coverage (CHOKEPOINT_FILES + PRELOAD_FILES -> leaf)"
mapfile -t REG_MEMBERS < <(registry_members)
verdict "$([[ "${#REG_MEMBERS[@]}" -ge 7 ]] && echo 0 || echo 1)" "registry parsed from incident-sandbox-coverage.test.sh: ${#REG_MEMBERS[@]} members (floor 7) -- an unparsed registry would check nothing"
for m in "${REG_MEMBERS[@]}" .claude/hooks/lib/test-incident-sandbox.sh; do
  lf="$(leaf_for_file "$m")"
  if [[ -z "$lf" ]]; then
    verdict 1 "chokepoint $m has NO mapped leaf -- add one (a runner that arms the sandbox must be exercised here)"
  elif in_list "$lf" "${LEAF_NAMES[@]}"; then
    verdict 0 "chokepoint $m is exercised by registered leaf [$lf]"
  elif [[ "${#SKIPPED_LEAVES[@]}" -gt 0 ]] && in_list "$lf" "${SKIPPED_LEAVES[@]}" && [[ -z "${SOLEUR_REQUIRE_VITEST:-}" ]]; then
    verdict 0 "chokepoint $m is exercised by [$lf], which is SKIPPED on this host (loud; set SOLEUR_REQUIRE_VITEST=1 to make it a failure)"
  else
    verdict 1 "chokepoint $m maps to leaf [$lf], which is not registered"
  fi
done
if [[ "$VITEST_ABSENT" == "1" && -n "${SOLEUR_REQUIRE_VITEST:-}" ]]; then
  verdict 1 "SOLEUR_REQUIRE_VITEST is set but apps/web-platform/node_modules/.bin/vitest is absent: the vitest chokepoint cannot be skipped"
fi

# --- delta + counting arms, all leaves in parallel (bounded wall clock) ---------------------------
echo "== delta arm (TMPDIR=<private base>, SOLEUR_SCRATCH_SESSION_ROOT unset) and counting arm"
for i in "${!LEAF_NAMES[@]}"; do
  n="${LEAF_NAMES[$i]}"; c="${LEAF_CMDS[$i]}"
  mkdir -p "$BASE/d.$n" "$BASE/c.$n"
  snapshot "$BASE/d.$n" "$BASE/d.$n.snap"
  parent="$(mk_parent_root "$BASE/c.$n")"
  printf '%s' "$parent" > "$BASE/c.$n.parent"
  ( run_leaf "$BASE/d.$n" "$BASE/d.$n.log" "$c"; echo $? > "$BASE/d.$n.rc" ) &
  cextra=(SOLEUR_SCRATCH_SESSION_ROOT="$parent" SOLEUR_SCRATCH_OWNER_PID="$$")
  [[ "${LEAF_KINDS[$i]}" == "sh" ]] && cextra+=(PATH="$BASE/shim:$PATH" SOLEUR_SHIM_LOG="$BASE/c.$n.shimlog")
  ( run_leaf "$parent" "$BASE/c.$n.log" "$c" "${cextra[@]}"; echo $? > "$BASE/c.$n.rc" ) &
done
wait

ran=0
for i in "${!LEAF_NAMES[@]}"; do
  n="${LEAF_NAMES[$i]}"
  rc="$(cat "$BASE/d.$n.rc" 2>/dev/null || echo 99)"
  new="$(new_since "$BASE/d.$n" "$BASE/d.$n.snap")"; nrc=$?
  nnew=0; [[ -n "$new" ]] && nnew="$(printf '%s\n' "$new" | wc -l | tr -d ' ')"
  [[ "$rc" == "0" ]] && ran=$((ran + 1))
  verdict "$([[ "$rc" == "0" ]] && echo 0 || echo 1)" "[$n] direct run exits 0 (rc=$rc)"
  verdict "$([[ "$nrc" == "0" && "$nnew" == "0" ]] && echo 0 || echo 1)" "[$n] delta == 0 after a normal exit (left $nnew: $(printf '%s' "$new" | head -3 | tr '\n' ' '))"

  parent="$(cat "$BASE/c.$n.parent")"
  crc="$(cat "$BASE/c.$n.rc" 2>/dev/null || echo 99)"
  if [[ "${LEAF_KINDS[$i]}" == "sh" ]]; then
    made="$(shim_count "$BASE/c.$n.shimlog")"
  elif [[ -n "${LEAF_NEEDLES[$i]}" ]]; then
    # entries the LEAF itself allocated (its own mkdtemp), not the chokepoint's soleur-inc-*
    made="$(find "$parent" -mindepth 1 -maxdepth 1 -name "${LEAF_NEEDLES[$i]}" 2>/dev/null | wc -l | tr -d ' ')"
  else
    made="$(count_created "$BASE/c.$n" "$parent")"
  fi
  verdict "$([[ "$crc" == "0" && "$made" -ge 1 ]] && echo 0 || echo 1)" "[$n] anti-vacuity: the leaf created >= 1 scratch entry (rc=$crc, created=$made)"
  verdict "$([[ -d "$parent" ]] && echo 0 || echo 1)" "[$n] nesting: an adopted parent root is never deleted by the leaf"
done
# Derived floors: EVERY registered leaf must run and exit 0 (not a typed ">= 8 of 11").
verdict "$([[ "$N_LEAVES" -ge 1 && "$ran" -eq "$N_LEAVES" ]] && echo 0 || echo 1)" "floor: all $N_LEAVES registered leaves executed and exited 0 (ran=$ran) -- 0 checked is a failure"

# --- probes: SIGTERM, SIGKILL, nesting validation, marker contract --------------------------------
cat > "$BASE/probe.ts" <<'EOF'
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const d = mkdtempSync(join(tmpdir(), "probe-"));
writeFileSync(join(d, "f"), "x");
console.log("ROOT=" + (process.env.SOLEUR_SCRATCH_SESSION_ROOT ?? ""));
console.log("PID=" + process.pid);
if (process.env.PROBE_HANG === "1") {
  console.log("READY");
  setInterval(() => {}, 1000);
}
EOF
cat > "$BASE/probe.py" <<'EOF'
import os, signal, tempfile, time
# A background job of a non-interactive shell inherits SIGINT as IGNORED, which python then keeps;
# restore the default so the SIGINT arm drives the same path a foreground run takes.
signal.signal(signal.SIGINT, signal.default_int_handler)
import tests.scripts._git_fixture_env  # noqa: F401  (the unittest chokepoint)
d = tempfile.mkdtemp(prefix="probe-")
open(os.path.join(d, "f"), "w").write("x")
print("ROOT=" + os.environ.get("SOLEUR_SCRATCH_SESSION_ROOT", ""), flush=True)
print("PID=%d" % os.getpid(), flush=True)
if os.environ.get("PROBE_HANG") == "1":
    print("READY", flush=True)
    time.sleep(60)
EOF
# A forked child that exits through sys.exit runs the atexit handlers it inherited. It must not
# delete the PARENT's root.
cat > "$BASE/probe-fork.py" <<'EOF'
import os, sys
import tests.scripts._git_fixture_env  # noqa: F401
root = os.environ.get("SOLEUR_SCRATCH_SESSION_ROOT", "")
print("ROOT=" + root, flush=True)
pid = os.fork()
if pid == 0:
    sys.exit(0)
os.waitpid(pid, 0)
print("EXISTS=%d" % (1 if os.path.isdir(root) else 0), flush=True)
EOF
cat > "$BASE/probe.sh" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"
echo "PID=\$\$"
sleep 20 & echo "SLEEP=\$!"
echo "READY"
wait \$!
EOF

PROBE_PID=""; PROBE_SLEEP=""
# probe_start <kind> <base> [env assignments...] -> sets PROBE_PID (+ PROBE_SLEEP for sh); waits for READY or exit
probe_start() {
  local kind="$1" base="$2"; shift 2
  local cmd
  case "$kind" in
    ts) cmd=(bun --preload "$REPO_ROOT/plugins/soleur/test/lib/git-tripwire.ts" "$BASE/probe.ts") ;;
    py) cmd=(python3 "$BASE/probe.py"); set -- "$@" PYTHONPATH="$REPO_ROOT" ;;
    sh) cmd=(bash "$BASE/probe.sh") ;;
  esac
  # `env` execs, so $! is the runtime's own pid (the pid its marker must carry).
  env "${SCRUB[@]}" TMPFS_GUARD_SCRATCH_BASES="$STD_NONE" \
    TMPDIR="$base" PROBE_HANG=1 "$@" "${cmd[@]}" > "$base.out" 2>&1 &
  PROBE_PID=$!
  BG_PIDS+=("$PROBE_PID")
  PROBE_SLEEP=""
  for _ in $(seq 1 100); do
    if grep -q '^READY' "$base.out" 2>/dev/null; then
      # the sh probe parks on a `sleep 20`; track it so it is reaped, not orphaned
      PROBE_SLEEP="$(sed -n 's/^SLEEP=//p' "$base.out" 2>/dev/null | head -1)"
      [[ -n "$PROBE_SLEEP" ]] && BG_PIDS+=("$PROBE_SLEEP")
      return 0
    fi
    kill -0 "$PROBE_PID" 2>/dev/null || return 1
    sleep 0.2
  done
  return 1
}
reap_probe_sleep() { [[ -n "${PROBE_SLEEP:-}" ]] && kill -KILL "$PROBE_SLEEP" 2>/dev/null; PROBE_SLEEP=""; return 0; }

# run_probe <kind> <base> <outfile> [env assignments...]: run a probe TO COMPLETION (no hang), bounded.
run_probe() {
  local kind="$1" base="$2" out="$3" cmd; shift 3
  case "$kind" in
    ts) cmd=(bun --preload "$REPO_ROOT/plugins/soleur/test/lib/git-tripwire.ts" "$BASE/probe.ts") ;;
    py) cmd=(python3 "$BASE/probe.py"); set -- "$@" PYTHONPATH="$REPO_ROOT" ;;
    pyfork) cmd=(python3 "$BASE/probe-fork.py"); set -- "$@" PYTHONPATH="$REPO_ROOT" ;;
  esac
  assert_fixture_dir "$base"; assert_fixture_dir "$out"
  _run_bounded 60 env "${SCRUB[@]}" TMPFS_GUARD_SCRATCH_BASES="$STD_NONE" TMPDIR="$base" "$@" "${cmd[@]}" > "$out" 2>&1
}
out_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

parse_marker() { # <dir> -> prints owner pid via the single production parser
  bash -c 'source "$1/plugins/soleur/scripts/lib/tmp-classify.sh"; tc_marker_owner_pid "$2"' _ "$REPO_ROOT" "$1" 2>/dev/null
}
classify() { # <dir>
  bash -c 'source "$1/plugins/soleur/scripts/lib/tmp-classify.sh"; tc_classify_entry "$2"' _ "$REPO_ROOT" "$1" 2>/dev/null | tail -1
}
find_run_roots() { # <base> <pid> -> soleur-run.<pid>.* dirs
  find "$1" -mindepth 1 -maxdepth 1 -type d -name "soleur-run.$2.*" 2>/dev/null
}

echo "== SIGTERM / SIGINT arm: root removed, 128+n exit status preserved (every wait is bounded)"
for kind in ts py sh; do
  lb="$BASE/term.$kind"; mkdir -p "$lb"; snapshot "$lb" "$lb.snap"
  if probe_start "$kind" "$lb"; then
    kill -TERM "$PROBE_PID" 2>/dev/null
    bounded_wait "$PROBE_PID" 15; trc=$BW_RC
    reap_probe_sleep
    sleep 0.3
    left="$(new_since "$lb" "$lb.snap")"
    verdict "$([[ -z "$left" ]] && echo 0 || echo 1)" "[$kind] delta == 0 under SIGTERM (left: $(printf '%s' "$left" | head -3 | tr '\n' ' '))"
    verdict "$([[ "$trc" == "143" ]] && echo 0 || echo 1)" "[$kind] SIGTERM keeps the 128+n exit status (rc=$trc; 137 = it hung and was killed)"
  else
    reap_probe_sleep
    verdict 1 "[$kind] probe reached READY under SIGTERM arm ($(head -c 200 "$lb.out" 2>/dev/null | tr '\n' ' '))"
    verdict 1 "[$kind] SIGTERM keeps the 128+n exit status (probe never ready)"
  fi
done
# SIGINT, once per runtime that owns a handler path for it.
for kind in ts py; do
  lb="$BASE/int.$kind"; mkdir -p "$lb"; snapshot "$lb" "$lb.snap"
  if probe_start "$kind" "$lb"; then
    kill -INT "$PROBE_PID" 2>/dev/null
    bounded_wait "$PROBE_PID" 15; irc=$BW_RC
    sleep 0.3
    left="$(new_since "$lb" "$lb.snap")"
    verdict "$([[ -z "$left" && "$irc" == "130" ]] && echo 0 || echo 1)" "[$kind] SIGINT removes the root and exits 130 (rc=$irc, left: $(printf '%s' "$left" | head -3 | tr '\n' ' '))"
  else
    verdict 1 "[$kind] SIGINT arm: probe reached READY ($(head -c 200 "$lb.out" 2>/dev/null | tr '\n' ' '))"
  fi
done

echo "== marker contract: three writers, one parser (tmp-classify.sh tc_marker_owner_pid)"
# shell writer
mc_sh="$BASE/mc.sh"; mkdir -p "$mc_sh"
SOLEUR_SCRATCH_OWNER_PID="$$" soleur_scratch_mark_owned "$mc_sh"
verdict "$([[ "$(parse_marker "$mc_sh")" == "$$" ]] && echo 0 || echo 1)" "shell writer: marker parses to the writer pid with matching ns"
# ts + py writers (live roots while the probe hangs)
for kind in ts py; do
  lb="$BASE/mc.$kind"; mkdir -p "$lb"
  if probe_start "$kind" "$lb"; then
    root="$(find_run_roots "$lb" "$PROBE_PID" | head -1)"
    got=""; [[ -n "$root" ]] && got="$(parse_marker "$root")"
    verdict "$([[ -n "$got" && "$got" == "$PROBE_PID" ]] && echo 0 || echo 1)" "[$kind] writer: marker parses to the writer pid $PROBE_PID (got ${got:-<none>})"
    kill -TERM "$PROBE_PID" 2>/dev/null; bounded_wait "$PROBE_PID" 15
  else
    verdict 1 "[$kind] writer: probe reached READY"
  fi
done

# PARITY PIN. The three writers must agree byte for byte, in key order, in mode and in what they leave
# in the directory -- parsing to the same pid is necessary, not sufficient (a python writer that
# wrote 0644 and a shell writer that wrote 0600 both parsed). pid=42 is written by each writer; the
# comparison is a function so a mutated COPY of a writer can be fed to it as a control.
fmode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null; }
PAR_BYTES_TS=1; PAR_BYTES_PY=1; PAR_MODE=1; PAR_KEYS=1; PAR_DETAIL=""
parity_check() { # <label> <py-writer-file> <ts-writer-file>
  local d="$BASE/par.$1" pyf="$2" tsf="$3"
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d/sh" "$d/ts" "$d/py"
  ( umask 022; SOLEUR_SCRATCH_OWNER_PID=42 soleur_scratch_mark_owned "$d/sh" )
  ( umask 022; PAR_TS="$tsf" PAR_DIR="$d/ts" bun -e 'import(process.env.PAR_TS).then((m) => m.writeScratchMarker(process.env.PAR_DIR, 42))' ) >/dev/null 2>&1
  ( umask 022; PAR_PY="$pyf" PAR_DIR="$d/py" python3 -c 'import importlib.util as u, os
s = u.spec_from_file_location("c", os.environ["PAR_PY"]); m = u.module_from_spec(s); s.loader.exec_module(m)
m.write_scratch_marker(os.environ["PAR_DIR"], 42)' ) >/dev/null 2>&1
  PAR_BYTES_TS=1; PAR_BYTES_PY=1; PAR_MODE=1; PAR_KEYS=1
  [[ -f "$d/sh/.soleur-owned" ]] || { PAR_DETAIL="shell writer wrote no marker"; return 1; }
  cmp -s "$d/sh/.soleur-owned" "$d/ts/.soleur-owned" 2>/dev/null && PAR_BYTES_TS=0
  cmp -s "$d/sh/.soleur-owned" "$d/py/.soleur-owned" 2>/dev/null && PAR_BYTES_PY=0
  local msh mts mpy
  msh="$(fmode "$d/sh/.soleur-owned")"; mts="$(fmode "$d/ts/.soleur-owned" 2>/dev/null)"; mpy="$(fmode "$d/py/.soleur-owned" 2>/dev/null)"
  [[ "$msh" == "600" && "$mts" == "$msh" && "$mpy" == "$msh" ]] && PAR_MODE=0
  local ksh kts kpy esh ets epy
  ksh="$(cut -d= -f1 "$d/sh/.soleur-owned" | paste -sd, -)"
  kts="$(cut -d= -f1 "$d/ts/.soleur-owned" 2>/dev/null | paste -sd, -)"
  kpy="$(cut -d= -f1 "$d/py/.soleur-owned" 2>/dev/null | paste -sd, -)"
  esh="$(ls -A "$d/sh" | paste -sd, -)"; ets="$(ls -A "$d/ts" | paste -sd, -)"; epy="$(ls -A "$d/py" | paste -sd, -)"
  [[ "$ksh" == "$kts" && "$ksh" == "$kpy" && "$esh" == "$ets" && "$esh" == "$epy" ]] && PAR_KEYS=0
  PAR_DETAIL="modes sh/ts/py=$msh/$mts/$mpy keys sh/ts/py=$ksh|$kts|$kpy entries sh/ts/py=$esh|$ets|$epy"
  [[ "$PAR_BYTES_TS" == 0 && "$PAR_BYTES_PY" == 0 && "$PAR_MODE" == 0 && "$PAR_KEYS" == 0 ]]
}
parity_check real "$REPO_ROOT/tests/conftest.py" "$REPO_ROOT/plugins/soleur/test/lib/scratch-session.ts"
verdict "$PAR_BYTES_TS" "parity: the TS writer's marker is byte-identical to the shell writer's (pid=42)"
verdict "$PAR_BYTES_PY" "parity: the python writer's marker is byte-identical to the shell writer's (pid=42)"
verdict "$PAR_MODE" "parity: all three markers have the same mode, 0600 ($PAR_DETAIL)"
verdict "$PAR_KEYS" "parity: same key order and no leftover tmp file across the three writers"
# controls: a drifted COPY of a writer must go RED, or the pin proves nothing
assert_fixture_dir "$BASE"
mkdir -p "$BASE/par-mut"
sed 's/schema=1/schema=2/' "$REPO_ROOT/tests/conftest.py" > "$BASE/par-mut/conftest.py"
cmp -s "$REPO_ROOT/tests/conftest.py" "$BASE/par-mut/conftest.py" && { printf '[FATAL] parity control: the python mutation did not land\n' >&2; exit 1; }
parity_check mutpy "$BASE/par-mut/conftest.py" "$REPO_ROOT/plugins/soleur/test/lib/scratch-session.ts"; mut_py_rc=$?
verdict "$([[ "$mut_py_rc" != "0" && "$PAR_BYTES_PY" != "0" ]] && echo 0 || echo 1)" "parity control: a python writer drifted to schema=2 (a COPY) is detected"
sed 's/0o600/0o644/' "$REPO_ROOT/plugins/soleur/test/lib/scratch-session.ts" > "$BASE/par-mut/scratch-session.ts"
cmp -s "$REPO_ROOT/plugins/soleur/test/lib/scratch-session.ts" "$BASE/par-mut/scratch-session.ts" && { printf '[FATAL] parity control: the ts mutation did not land\n' >&2; exit 1; }
parity_check mutts "$REPO_ROOT/tests/conftest.py" "$BASE/par-mut/scratch-session.ts"; mut_ts_rc=$?
verdict "$([[ "$mut_ts_rc" != "0" && "$PAR_MODE" != "0" ]] && echo 0 || echo 1)" "parity control: a TS writer drifted to mode 0644 (a COPY) is detected"

echo "== SIGKILL arm: a marker-bearing dead-owner root remains and classifies marker:<pid>"
for kind in ts py; do
  lb="$BASE/kill.$kind"; mkdir -p "$lb"
  if probe_start "$kind" "$lb"; then
    pid="$PROBE_PID"
    kill -KILL "$pid" 2>/dev/null; bounded_wait "$pid" 15
    root="$(find_run_roots "$lb" "$pid" | head -1)"
    cls=""; [[ -n "$root" ]] && cls="$(classify "$root")"
    verdict "$([[ "$cls" == "marker:$pid" ]] && echo 0 || echo 1)" "[$kind] SIGKILLed runner leaves a root classified marker:$pid (got '${cls:-<no root>}')"
    # control: an unrelated dir in the same base does not classify as an owned marker
    assert_fixture_dir "$lb"
    mkdir -p "$lb/unrelated-dir" && : > "$lb/unrelated-dir/f"
    ccls="$(classify "$lb/unrelated-dir")"
    verdict "$([[ "$ccls" != marker:* ]] && echo 0 || echo 1)" "[$kind] control: an unmarked dir is not classified marker:* (got '$ccls')"
  else
    verdict 1 "[$kind] probe reached READY under SIGKILL arm"
    verdict 1 "[$kind] control skipped (probe never ready)"
  fi
done
# The shell chokepoint cannot bind a per-process root; its half of the property is MARKER-AT-CREATION
# on the EXACT soleur-inc-* directory it created. Marking a different directory classifies unmarked.
lb="$BASE/kill.sh"; mkdir -p "$lb"
if probe_start sh "$lb"; then
  pid="$PROBE_PID"
  kill -KILL "$pid" 2>/dev/null; bounded_wait "$pid" 15; reap_probe_sleep
  sbx="$(find "$lb" -mindepth 1 -maxdepth 1 -type d -name 'soleur-inc-*' 2>/dev/null | head -1)"
  cls=""; [[ -n "$sbx" ]] && cls="$(classify "$sbx")"
  verdict "$([[ "$cls" == "marker:$pid" ]] && echo 0 || echo 1)" "[sh] SIGKILLed shell runner leaves its soleur-inc-* dir classified marker:$pid (got '${cls:-<no sandbox>}')"
else
  reap_probe_sleep
  verdict 1 "[sh] probe reached READY under SIGKILL arm"
fi

echo "== python fork guard: a forked child exiting via sys.exit must not delete the parent's root"
lb="$BASE/fork.py"; mkdir -p "$lb"; snapshot "$lb" "$lb.snap"
run_probe pyfork "$lb" "$lb.out"; frc=$?
verdict "$([[ "$frc" == "0" && "$(out_field "$lb.out" EXISTS)" == "1" ]] && echo 0 || echo 1)" "[py] the parent's root survives a forked child's sys.exit (rc=$frc, exists=$(out_field "$lb.out" EXISTS))"
left="$(new_since "$lb" "$lb.snap")"
verdict "$([[ -z "$left" ]] && echo 0 || echo 1)" "[py] and the parent still removes it at its own exit (left: $(printf '%s' "$left" | head -3 | tr '\n' ' '))"

echo "== SOLEUR_KEEP_SCRATCH=1 keeps the root for inspection"
for kind in ts py; do
  lb="$BASE/keep.$kind"; mkdir -p "$lb"
  run_probe "$kind" "$lb" "$lb.out" SOLEUR_KEEP_SCRATCH=1; krc=$?
  kroot="$(out_field "$lb.out" ROOT)"
  verdict "$([[ "$krc" == "0" && -n "$kroot" && -d "$kroot" && -f "$kroot/.soleur-owned" ]] && echo 0 || echo 1)" "[$kind] SOLEUR_KEEP_SCRATCH=1 leaves the root in place (rc=$krc, root=${kroot##*/})"
  if [[ -n "$kroot" && -d "$kroot" ]]; then
    assert_fixture_dir "$kroot"
    rm -rf "$kroot"
  fi
done

echo "== TMPDIR sub-path: a root allocated beneath a standard base lands at depth 1 of that base"
# Reaper 3 enumerates `-maxdepth 1 -name 'soleur-run.*'` under each scratch base, so a root at depth 2
# is invisible to it. The shell normalises TMPDIR=/tmp/<sub> up to the base; TS and python must too.
# The standard-base list is TMPFS_GUARD_SCRATCH_BASES (what Reaper 3 itself reads), pointed at a
# private dir so the real /tmp is never involved.
for kind in ts py; do
  lb="$BASE/sub.$kind"; std="$lb/std"; oth="$lb/other"
  mkdir -p "$std/sub/deeper" "$oth/sub"
  run_probe "$kind" "$std/sub/deeper" "$lb.out" TMPFS_GUARD_SCRATCH_BASES="$std"
  sroot="$(out_field "$lb.out" ROOT)"
  verdict "$([[ -n "$sroot" && "${sroot%/*}" == "$std" && "${sroot##*/}" == soleur-run.* ]] && echo 0 || echo 1)" "[$kind] TMPDIR=<std>/sub/deeper allocates the root at depth 1 of <std> (root=${sroot:-<none>})"
  run_probe "$kind" "$oth/sub" "$lb.out2" TMPFS_GUARD_SCRATCH_BASES="$std"
  sroot2="$(out_field "$lb.out2" ROOT)"
  verdict "$([[ -n "$sroot2" && "${sroot2%/*}" == "$oth/sub" ]] && echo 0 || echo 1)" "[$kind] control: a TMPDIR outside every standard base is used verbatim (root=${sroot2:-<none>})"
done

echo "== nesting validation, per runtime (bun and python probes, run to completion)"
MY_NS="$(readlink /proc/self/ns/pid 2>/dev/null || printf 'pid:[unknown]')"
write_marker() { printf 'pid=%s\nschema=1\nns=%s\n' "$2" "$3" > "$1/.soleur-owned"; }
for kind in ts py; do
  # valid owned parent: adopt, do not delete it, allocate inside it
  lb="$BASE/nest.$kind.valid"; mkdir -p "$lb"; parent="$(mk_parent_root "$lb")"
  run_probe "$kind" "$lb" "$lb.out" SOLEUR_SCRATCH_SESSION_ROOT="$parent"
  adopted="$(out_field "$lb.out" ROOT)"
  verdict "$([[ "$adopted" == "$parent" ]] && echo 0 || echo 1)" "[$kind] valid parent root is adopted (ROOT=$([[ "$adopted" == "$parent" ]] && echo same || echo "$adopted"))"
  verdict "$([[ -d "$parent" ]] && echo 0 || echo 1)" "[$kind] valid parent root still exists after the nested runner exits"
  verdict "$([[ -n "$(entries "$parent" | grep -v '^.soleur-owned$')" ]] && echo 0 || echo 1)" "[$kind] the nested runner's allocations landed INSIDE the parent root"
  extra="$(entries "$lb" | grep -vFx "${parent##*/}" | grep -v '\.out$' || true)"
  verdict "$([[ -z "$extra" ]] && echo 0 || echo 1)" "[$kind] nothing escaped to the base next to the parent root (${extra:-none})"

  # invalid roots are never adopted and never touched: a fresh root is used instead
  for v in nomarker dead pid0 foreignns symlink; do
    lb="$BASE/nest.$kind.$v"; mkdir -p "$lb"; stale="$lb/soleur-run.1.STALEROOT"; tgt="$stale"
    case "$v" in
      nomarker)  mkdir -p "$stale" ;;
      dead)      mkdir -p "$stale"; bash -c 'exit 0' & dead=$!; wait "$dead" 2>/dev/null; write_marker "$stale" "$dead" "$MY_NS" ;;
      pid0)      mkdir -p "$stale"; write_marker "$stale" 0 "$MY_NS" ;;
      foreignns) mkdir -p "$stale"; write_marker "$stale" "$$" "pid:[1]" ;;
      symlink)   tgt="$(mk_parent_root "$lb/real")"; ln -s "$tgt" "$stale" ;;
    esac
    run_probe "$kind" "$lb" "$lb.out" SOLEUR_SCRATCH_SESSION_ROOT="$stale"
    fresh="$(out_field "$lb.out" ROOT)"
    verdict "$([[ -n "$fresh" && "$fresh" != "$stale" && "$fresh" != "$tgt" ]] && echo 0 || echo 1)" "[$kind] $v: the root is NOT adopted (fresh root: ${fresh##*/})"
    verdict "$([[ -z "$(entries "$tgt" | grep -v '^.soleur-owned$')" ]] && echo 0 || echo 1)" "[$kind] $v: the rejected root received no allocation"
  done
done

echo
# FLOOR = the EXACT case count of a full run (all leaves registered). Each registered leaf contributes
# exactly 4 verdicts, so a leaf pair skipped LOUDLY (no node_modules, non-CI) lowers the floor by exactly
# its own 4 each -- and a leaf registration deleted from this file is not a loud skip, so it cannot
# shrink the floor: it lowers CASES below it. Raise it when an arm is added; never lower it to pass.
FULL_CASES=136
MIN_CASES=$((FULL_CASES - 4 * N_SKIPPED))
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  echo "[FATAL] vacuity floor: $CASES cases executed, expected at least $MIN_CASES" >&2; exit 1
fi
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  echo "[FATAL] accounting: PASS+FAIL=$((PASS + FAIL)) but CASES=$CASES" >&2; exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then echo "FAILED: $FAIL/$CASES"; exit 1; fi
echo "OK: $PASS/$CASES"
