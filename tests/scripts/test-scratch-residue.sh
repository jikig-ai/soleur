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
# test-weakness-miner) PLUS one direct vitest suite, one `python -m unittest` module and the pytest
# chokepoint hook (pytest itself is not installed on every host, so the hook pytest calls is driven
# directly: pytest_configure is the whole of the conftest chokepoint).
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
# /var/tmp are never measured or touched.
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
ALLOW_RE='^(node-compile-cache)$'

# snapshot <dir> <outfile>: sorted entry names. rc 2 if the base does not exist -- a missing base must
# never read as an empty one (harness row H1).
snapshot() {
  [[ -d "$1" ]] || return 2
  { ls -A "$1" 2>/dev/null | grep -Ev "$ALLOW_RE" || true; } | sort > "$2"
}
# new_since <dir> <snapfile>: names now present that were not in the snapshot.
new_since() {
  local now="$1.now.$$"
  snapshot "$1" "$now" || return 2
  comm -13 "$2" "$now"
  rm -f "$now"
}

# run_leaf <tmpdir> <logfile> <cmdstring> [extra env assignments...]: run a leaf from the repo root
# with the scratch/incident env scrubbed and TMPDIR pointed at <tmpdir>. The log lives OUTSIDE the
# measured base so it is never counted as a created entry.
run_leaf() {
  local base="$1" log="$2" cmd="$3"; shift 3
  _run_bounded 240 env -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE \
    -u INCIDENTS_REPO_ROOT -u SOLEUR_TEST_INCIDENT_ROOT -u SOLEUR_KEEP_SCRATCH \
    TMPDIR="$base" "$@" bash -c "$cmd" > "$log" 2>&1
}

# --- the leaf set --------------------------------------------------------------------------------
LEAF_NAMES=()
LEAF_CMDS=()
LEAF_KINDS=()   # sh = counted by the mktemp shim; rt = counted by the entries left in the adopted root
add_leaf() { LEAF_NAMES+=("$1"); LEAF_CMDS+=("$2"); LEAF_KINDS+=("${3:-rt}"); }
add_leaf bun-kb-coverage        'bun test plugins/soleur/test/kb-coverage.test.ts'
add_leaf bun-gdpr-gate          'bun test plugins/soleur/test/gdpr-gate.test.ts'
add_leaf bun-legal-template     'bun test plugins/soleur/test/legal-template-vendor-surface.test.ts'
add_leaf bun-plan-skeleton      'bun test plugins/soleur/test/plan-skeleton-checkpoint.test.ts'
add_leaf bun-runtime-plugin     'bun test plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts'
add_leaf bun-ship-pir-gate      'bun test plugins/soleur/test/ship-incident-pir-gate.test.ts'
add_leaf sh-grep-rewrite        'bash .claude/hooks/grep-rewrite.test.sh' sh
add_leaf sh-weakness-miner      'bash tests/scripts/test-weakness-miner.sh' sh
add_leaf py-unittest            'python3 -m unittest tests.scripts.test_lint_rule_ids'
add_leaf py-pytest-configure    'python3 -c "import tests.conftest as c; c.pytest_configure()"'
if [[ -x "$REPO_ROOT/apps/web-platform/node_modules/.bin/vitest" ]]; then
  add_leaf vitest-direct        'cd apps/web-platform && ./node_modules/.bin/vitest run test/abort-classifier.test.ts'
else
  echo "  NOTE: apps/web-platform/node_modules/.bin/vitest absent -- vitest leaf not run on this host"
fi
N_LEAVES=${#LEAF_NAMES[@]}

# --- harness rows (the canary's own instruments, proven before they are trusted) -----------------
echo "== harness rows"
# H1: a nonexistent base is an error, not an empty base.
snapshot "$BASE/does-not-exist" "$BASE/h1.snap" 2>/dev/null; h1_rc=$?
verdict "$([[ "$h1_rc" == "2" ]] && echo 0 || echo 1)" "H1: a missing base is an error (rc=$h1_rc), never read as empty"
# H2: pre-seeded base -- the delta, not absolute emptiness, is compared (must PASS).
mkdir -p "$BASE/h2" && : > "$BASE/h2/unrelated-entry"
snapshot "$BASE/h2" "$BASE/h2.snap"
TMPDIR="$BASE/h2" bash -c 'd=$(mktemp -d); touch "$d/x"; rm -rf "$d"'
h2_new="$(new_since "$BASE/h2" "$BASE/h2.snap")"
verdict "$([[ -z "$h2_new" ]] && echo 0 || echo 1)" "H2: a pre-seeded base with a leaf that cleans up after itself has delta 0"
# H2b: and the same instrument DOES see a leak (the delta is not blind).
TMPDIR="$BASE/h2" bash -c 'd=$(mktemp -d); touch "$d/x"'
h2b_new="$(new_since "$BASE/h2" "$BASE/h2.snap")"
verdict "$([[ -n "$h2b_new" ]] && echo 0 || echo 1)" "H2b: the delta detector sees a leaking leaf (not vacuous)"
# H3: a no-op leaf must be flagged vacuous by the counting instrument.
count_created() { # <base> <root> -> number of entries a leaf created (base entries other than root + root entries other than marker)
  local base="$1" root="$2" n=0 e
  while IFS= read -r e; do
    [[ -n "$e" && "$base/$e" != "$root" ]] && n=$((n + 1))
  done < <(ls -A "$base" 2>/dev/null | grep -Ev "$ALLOW_RE")
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
mkdir -p "$BASE/h3"; h3_root="$(mk_parent_root "$BASE/h3")"
n_noop="$(count_created "$BASE/h3" "$h3_root")"
verdict "$([[ "$n_noop" == "0" ]] && echo 0 || echo 1)" "H3: a no-op runtime leaf creates 0 entries, so the anti-vacuity check would reject it"

# The counting shim for shell leaves: log one line per mktemp call, then run the real one. A shell
# leaf that cleans up after itself leaves nothing to count at exit, so entries cannot prove it ran.
REAL_MKTEMP="$(command -v mktemp)"
mkdir -p "$BASE/shim"
printf '#!/bin/sh\nprintf "x\\n" >> "$SOLEUR_SHIM_LOG"\nexec "%s" "$@"\n' "$REAL_MKTEMP" > "$BASE/shim/mktemp"
chmod +x "$BASE/shim/mktemp"
shim_count() { if [[ -f "$1" ]]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
: > "$BASE/h3.shimlog"
env PATH="$BASE/shim:$PATH" SOLEUR_SHIM_LOG="$BASE/h3.shimlog" bash -c 'true'
n_noop_sh="$(shim_count "$BASE/h3.shimlog")"
env PATH="$BASE/shim:$PATH" SOLEUR_SHIM_LOG="$BASE/h3.shimlog" bash -c 'd=$(mktemp -d); rmdir "$d"'
n_real_sh="$(shim_count "$BASE/h3.shimlog")"
verdict "$([[ "$n_noop_sh" == "0" && "$n_real_sh" == "1" ]] && echo 0 || echo 1)" "H3: the mktemp shim counts 0 for a no-op shell leaf and 1 for a real allocation (got $n_noop_sh, $n_real_sh)"

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
  if [[ "${LEAF_KINDS[$i]}" == "sh" ]]; then made="$(shim_count "$BASE/c.$n.shimlog")"; else made="$(count_created "$BASE/c.$n" "$parent")"; fi
  verdict "$([[ "$crc" == "0" && "$made" -ge 1 ]] && echo 0 || echo 1)" "[$n] anti-vacuity: the leaf created >= 1 scratch entry (rc=$crc, created=$made)"
  verdict "$([[ -d "$parent" ]] && echo 0 || echo 1)" "[$n] nesting: an adopted parent root is never deleted by the leaf"
done
verdict "$([[ "$ran" -ge 8 ]] && echo 0 || echo 1)" "floor: >= 8 runners executed and exited 0 ($ran of $N_LEAVES) -- 0 runners checked is a failure"

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
import os, tempfile, time
import tests.scripts._git_fixture_env  # noqa: F401  (the unittest chokepoint)
d = tempfile.mkdtemp(prefix="probe-")
open(os.path.join(d, "f"), "w").write("x")
print("ROOT=" + os.environ.get("SOLEUR_SCRATCH_SESSION_ROOT", ""), flush=True)
print("PID=%d" % os.getpid(), flush=True)
if os.environ.get("PROBE_HANG") == "1":
    print("READY", flush=True)
    time.sleep(60)
EOF
cat > "$BASE/probe.sh" <<EOF
#!/usr/bin/env bash
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh"
echo "PID=\$\$"
echo "READY"
sleep 20 & wait \$!
EOF

# probe_start <kind> <base> [env assignments...] -> sets PROBE_PID; waits for READY or exit
probe_start() {
  local kind="$1" base="$2"; shift 2
  local cmd
  case "$kind" in
    ts) cmd=(bun --preload "$REPO_ROOT/plugins/soleur/test/lib/git-tripwire.ts" "$BASE/probe.ts") ;;
    py) cmd=(python3 "$BASE/probe.py"); set -- "$@" PYTHONPATH="$REPO_ROOT" ;;
    sh) cmd=(bash "$BASE/probe.sh") ;;
  esac
  # `env` execs, so $! is the runtime's own pid (the pid its marker must carry).
  env -u SOLEUR_SCRATCH_SESSION_ROOT -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE \
    -u INCIDENTS_REPO_ROOT -u SOLEUR_TEST_INCIDENT_ROOT -u SOLEUR_KEEP_SCRATCH \
    TMPDIR="$base" PROBE_HANG=1 "$@" "${cmd[@]}" > "$base.out" 2>&1 &
  PROBE_PID=$!
  BG_PIDS+=("$PROBE_PID")
  local k
  for _ in $(seq 1 100); do
    grep -q '^READY' "$base.out" 2>/dev/null && return 0
    kill -0 "$PROBE_PID" 2>/dev/null || return 1
    sleep 0.2
  done
  return 1
}
parse_marker() { # <dir> -> prints owner pid via the single production parser
  bash -c 'source "$1/plugins/soleur/scripts/lib/tmp-classify.sh"; tc_marker_owner_pid "$2"' _ "$REPO_ROOT" "$1" 2>/dev/null
}
classify() { # <dir>
  bash -c 'source "$1/plugins/soleur/scripts/lib/tmp-classify.sh"; tc_classify_entry "$2"' _ "$REPO_ROOT" "$1" 2>/dev/null | tail -1
}
find_run_roots() { # <base> <pid> -> soleur-run.<pid>.* dirs
  find "$1" -mindepth 1 -maxdepth 1 -type d -name "soleur-run.$2.*" 2>/dev/null
}

echo "== SIGTERM arm: root removed, 128+15 exit status preserved"
for kind in ts py sh; do
  lb="$BASE/term.$kind"; mkdir -p "$lb"; snapshot "$lb" "$lb.snap"
  if probe_start "$kind" "$lb"; then
    kill -TERM "$PROBE_PID" 2>/dev/null
    wait "$PROBE_PID" 2>/dev/null; trc=$?
    sleep 0.3
    left="$(new_since "$lb" "$lb.snap")"
    verdict "$([[ -z "$left" ]] && echo 0 || echo 1)" "[$kind] delta == 0 under SIGTERM (left: $(printf '%s' "$left" | head -3 | tr '\n' ' '))"
    verdict "$([[ "$trc" == "143" ]] && echo 0 || echo 1)" "[$kind] SIGTERM keeps the 128+n exit status (rc=$trc)"
  else
    verdict 1 "[$kind] probe reached READY under SIGTERM arm ($(head -c 200 "$lb.out" 2>/dev/null | tr '\n' ' '))"
    verdict 1 "[$kind] SIGTERM keeps the 128+n exit status (probe never ready)"
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
    kill -TERM "$PROBE_PID" 2>/dev/null; wait "$PROBE_PID" 2>/dev/null
  else
    verdict 1 "[$kind] writer: probe reached READY"
  fi
done

echo "== SIGKILL arm: a marker-bearing dead-owner root remains and classifies marker:<pid>"
for kind in ts py; do
  lb="$BASE/kill.$kind"; mkdir -p "$lb"
  if probe_start "$kind" "$lb"; then
    pid="$PROBE_PID"
    kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    root="$(find_run_roots "$lb" "$pid" | head -1)"
    cls=""; [[ -n "$root" ]] && cls="$(classify "$root")"
    verdict "$([[ "$cls" == "marker:$pid" ]] && echo 0 || echo 1)" "[$kind] SIGKILLed runner leaves a root classified marker:$pid (got '${cls:-<no root>}')"
    # control: an unrelated dir in the same base does not classify as an owned marker
    mkdir -p "$lb/unrelated-dir" && : > "$lb/unrelated-dir/f"
    ccls="$(classify "$lb/unrelated-dir")"
    verdict "$([[ "$ccls" != marker:* ]] && echo 0 || echo 1)" "[$kind] control: an unmarked dir is not classified marker:* (got '$ccls')"
  else
    verdict 1 "[$kind] probe reached READY under SIGKILL arm"
    verdict 1 "[$kind] control skipped (probe never ready)"
  fi
done

echo "== nesting validation (bun probe, run to completion)"
nest_probe() { # <label> <base> <session-root> ; runs the probe to completion, prints its output file
  local base="$2" root="$3"
  env -u SOLEUR_SCRATCH_OWNER_PID -u SOLEUR_SCRATCH_BASE -u INCIDENTS_REPO_ROOT -u SOLEUR_TEST_INCIDENT_ROOT \
    TMPDIR="$base" SOLEUR_SCRATCH_SESSION_ROOT="$root" \
    bun --preload "$REPO_ROOT/plugins/soleur/test/lib/git-tripwire.ts" "$BASE/probe.ts" > "$base.out" 2>&1
}
# valid owned parent: adopt, do not delete it, allocate inside it
lb="$BASE/nest.valid"; mkdir -p "$lb"; parent="$(mk_parent_root "$lb")"
nest_probe valid "$lb" "$parent"
adopted="$(sed -n 's/^ROOT=//p' "$lb.out")"
verdict "$([[ "$adopted" == "$parent" ]] && echo 0 || echo 1)" "valid parent root is adopted (ROOT=$([[ "$adopted" == "$parent" ]] && echo same || echo "$adopted"))"
verdict "$([[ -d "$parent" ]] && echo 0 || echo 1)" "valid parent root still exists after the nested runner exits"
verdict "$([[ -n "$(ls -A "$parent" | grep -v '^.soleur-owned$')" ]] && echo 0 || echo 1)" "the nested runner's allocations landed INSIDE the parent root"
extra="$(ls -A "$lb" | grep -vFx "${parent##*/}" || true)"
verdict "$([[ -z "$extra" ]] && echo 0 || echo 1)" "nothing escaped to the base next to the parent root (${extra:-none})"

# stale root with no marker: not adopted, left untouched, fresh root used and removed
lb="$BASE/nest.nomarker"; mkdir -p "$lb"; stale="$lb/soleur-run.1.STALEROOT"; mkdir -p "$stale"
nest_probe nomarker "$lb" "$stale"
fresh="$(sed -n 's/^ROOT=//p' "$lb.out")"
verdict "$([[ -n "$fresh" && "$fresh" != "$stale" ]] && echo 0 || echo 1)" "a root with no marker is NOT adopted (fresh root: ${fresh##*/})"
verdict "$([[ -z "$(ls -A "$stale")" ]] && echo 0 || echo 1)" "the no-marker root is left untouched (nothing allocated in it)"

# dead owner pid: not adopted
lb="$BASE/nest.dead"; mkdir -p "$lb"; stale="$lb/soleur-run.1.DEADOWNER"; mkdir -p "$stale"
bash -c 'exit 0' & dead=$!; wait "$dead" 2>/dev/null
SOLEUR_SCRATCH_OWNER_PID="$dead" soleur_scratch_mark_owned "$stale"
nest_probe dead "$lb" "$stale"
fresh="$(sed -n 's/^ROOT=//p' "$lb.out")"
verdict "$([[ -n "$fresh" && "$fresh" != "$stale" ]] && echo 0 || echo 1)" "a root whose owner pid is dead is NOT adopted (fresh root: ${fresh##*/})"
verdict "$([[ -z "$(ls -A "$stale" | grep -v '^.soleur-owned$')" ]] && echo 0 || echo 1)" "the dead-owner root received no allocation"

echo
MIN_CASES=60
if [[ "$CASES" -lt "$MIN_CASES" ]]; then
  echo "[FATAL] vacuity floor: $CASES cases executed, expected at least $MIN_CASES" >&2; exit 1
fi
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  echo "[FATAL] accounting: PASS+FAIL=$((PASS + FAIL)) but CASES=$CASES" >&2; exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then echo "FAILED: $FAIL/$CASES"; exit 1; fi
echo "OK: $PASS/$CASES"
