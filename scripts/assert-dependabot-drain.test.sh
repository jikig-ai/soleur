#!/usr/bin/env bash
# Guard for scripts/assert-dependabot-drain.py (#1327).
#
# That script had NO test file at all, and its two anti-vacuity floors -- MIN_ROWS and
# MIN_RESOLVED -- both count ROWS. Nothing floored the fourth tuple element, which is the
# only thing the reconciliation table exists to enforce: setting all 19 CVE thresholds to
# "0.0.0" printed a confident clean summary and exited 0.
#
# ACCOUNTING follows scripts/lint-dual-lockfile.test.sh:23-39 exactly, and the FIRST
# version of this file did not -- three defects from one cause. It incremented `asserted`
# inside both verdict helpers, the shape ADR-193 Decision 2 forbids: deleting the single
# token `fails=$((fails + 1))` from fail() made a battery with two genuinely failing arms
# report "11 assertions, 0 failed" and exit 0. It had no floor of any kind, so deleting
# all seven behavioural arms reported "4 assertions, 0 failed" and exit 0. And because
# scripts/guard-vacuity-floor.test.sh derives its population from floor SHAPE, a suite
# with no floor was invisible to the repo's own meta-guard -- neither covered, deferred,
# nor unclassified.
#
# So: `asserted` moves at the CALL SITE, the verdict helpers touch only the verdict
# counters, the conservation identity is emitted WITHOUT routing through fail() (a
# discarded verdict cannot be reported by the counter it corrupted), and MIN_ASSERTIONS
# floors PASSES rather than `asserted`.
#
# FIXTURES ARE SYNTHETIC. The first version ran the guard against the REAL lockfiles and
# exited early if that reddened -- so a genuine Dependabot regression would have reddened
# the live run AND skipped this whole battery, taking the guard-of-the-guard dark exactly
# when the guard was under load. The live assertion is separately registered in
# test-all.sh as `scripts/assert-dependabot-drain-live`; this file owns only the question
# "does the guard still have teeth", and answers it against a tree it controls.
#
# The fixture pins versions at <major>.999.999 rather than at each row's threshold, so it
# mirrors no floor and a lowered threshold cannot hide behind it. It does mirror the
# (manifest, package, major) SET -- deliberately: adding a REQUIRED row without a fixture
# entry drops `resolved` below MIN_RESOLVED and reds the control, which says so.
set -euo pipefail

# /tmp is a machine-global 4 GiB tmpfs shared by every parallel worktree, and running
# several at once is this repo's documented workflow. /var/tmp is disk-backed.
# test-all.sh and run-registered-suites.sh already default TMPDIR this way; a DIRECT
# invocation of this suite -- the inner loop while editing the guard -- inherits the bare
# /tmp without it, so its verdicts would become a function of another session's disk use.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/assert-dependabot-drain.py"
SANDBOX="$(mktemp -d -t drain-guard.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
# Re-raise rather than swallowing: test-all.sh's suite_exit_class separates the KILLED
# bucket from FAILED by inspecting signal-shaped statuses, so a trap that exits normally
# on SIGTERM reports a reap as a plain failure.
trap 'cleanup; trap - INT;  kill -INT  $$' INT
trap 'cleanup; trap - TERM; kill -TERM $$' TERM
trap 'cleanup; trap - HUP;  kill -HUP  $$' HUP

passes=0
fails=0
asserted=0
# ADR-193 #2: the verdict helpers touch ONLY the verdict counters. `asserted` moves at the
# call site, so stubbing fail() drops the verdict WITHOUT dropping its count and the
# conservation identity below catches it.
pass() { passes=$((passes + 1)); echo "[ok] $*"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $*" >&2; }

[[ -r "$GUARD" ]] || { echo "FATAL: cannot read $GUARD" >&2; exit 2; }
cp "$GUARD" "$SANDBOX/pristine.py" || { echo "FATAL: could not seed the sandbox" >&2; exit 2; }

# ---------------------------------------------------------------------------------------
# Synthetic fixture tree: four lockfiles at the paths LOCKS names, relative to $FIX.
# ---------------------------------------------------------------------------------------
FIX="$SANDBOX/fixture"
build_fixture() {
  local extra_webplat="${1:-}"
  rm -rf "$FIX"
  mkdir -p "$FIX/apps/web-platform" \
           "$FIX/plugins/soleur/skills/pencil-setup/scripts" \
           "$FIX/spike" || return 1
  python3 - "$FIX" "$extra_webplat" <<'PYEOF' || return 1
import json, os, sys
root, extra = sys.argv[1], sys.argv[2]

def pkgs(entries):
    # <major>.999.999 mirrors no threshold in the table, so a lowered floor cannot hide
    # behind the fixture: only FLOOR_ANCHORS and the structural check can catch that.
    out = {"": {"name": "fixture", "version": "0.0.1"}}
    for name, major in entries:
        out[f"node_modules/{name}"] = {"version": f"{major}.999.999"}
    return out

web = [("nanoid", 3), ("js-yaml", 3), ("hono", 4), ("@hono/node-server", 1),
       ("ip-address", 10), ("fast-uri", 3), ("undici", 7),
       ("brace-expansion", 1), ("@opentelemetry/propagator-jaeger", 2)]
w = pkgs(web)
# js-yaml and brace-expansion carry two more major lines each, nested so the paths differ.
w["node_modules/a/node_modules/js-yaml"] = {"version": "4.999.999"}
w["node_modules/b/node_modules/brace-expansion"] = {"version": "2.999.999"}
w["node_modules/c/node_modules/brace-expansion"] = {"version": "5.999.999"}
# The two DEFERRED rows assert these exact paths still exist.
w["node_modules/next/node_modules/postcss"] = {"version": "8.999.999"}
w["node_modules/next/node_modules/sharp"] = {"version": "0.999.999"}
if extra:
    w.update(json.loads(extra))

rt = pkgs([("js-yaml", 3), ("brace-expansion", 1)])
rt["node_modules/a/node_modules/js-yaml"] = {"version": "4.999.999"}

pen = pkgs([("hono", 4), ("@hono/node-server", 1), ("ip-address", 10), ("fast-uri", 3)])
spike = pkgs([])

for rel, p in [("apps/web-platform/package-lock.json", w),
               ("package-lock.json", rt),
               ("plugins/soleur/skills/pencil-setup/scripts/package-lock.json", pen),
               ("spike/package-lock.json", spike)]:
    with open(os.path.join(root, rel), "w") as fh:
        json.dump({"packages": p}, fh)
PYEOF
}

build_fixture || { echo "FATAL: could not build the fixture tree" >&2; exit 2; }

run_mutant() {
  local script="$1" out rc=0
  out="$(cd "$FIX" && python3 "$script" 2>&1)" || rc=$?
  printf '%s' "$out" > "$SANDBOX/last.out"
  return "$rc"
}

# mutate <label> <expected-substring> <python-mutator-on-stdin>
mutate() {
  local label="$1" expect="$2" src="$3"
  local mutant="$SANDBOX/mutant.py"
  asserted=$((asserted + 1))
  if ! python3 -c "$src" < "$SANDBOX/pristine.py" > "$mutant"; then
    fail "$label: the mutator crashed"; return
  fi
  if cmp -s "$SANDBOX/pristine.py" "$mutant"; then
    fail "$label: the mutation did NOT land — this arm re-ran the baseline and proves nothing"
    return
  fi
  # A mutant that does not PARSE reds via SyntaxError, which is indistinguishable from the
  # guard catching it unless the message is checked. Separate the two explicitly so a
  # broken mutator is reported as a harness fault, not as guard coverage.
  if ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$mutant" 2>/dev/null; then
    fail "$label: the mutant does not parse — the MUTATOR is broken, this arm measured nothing"
    return
  fi
  if run_mutant "$mutant"; then
    fail "$label: the mutant exited 0 — the guard did not catch it"; return
  fi
  if ! grep -qF -- "$expect" "$SANDBOX/last.out"; then
    fail "$label: reddened, but for the wrong reason (no '$expect' in the output)"; return
  fi
  pass "$label"
}

# --- Control. A red baseline voids every arm below. ---
asserted=$((asserted + 1))
if run_mutant "$SANDBOX/pristine.py"; then
  pass "control: the unmutated guard exits 0 against the synthetic fixture tree"
else
  fail "control: the unmutated guard is RED on a clean fixture — every arm below is void"
  echo "--- control output ---" >&2; cat "$SANDBOX/last.out" >&2; echo "--- end ---" >&2
fi

# --- MUST-PASS row. A guard that reds on ANY edit would score full marks on every RED
# arm below; this proves the reds are discriminating rather than reflexive. ---
asserted=$((asserted + 1))
python3 -c '
import sys; s = sys.stdin.read()
sys.stdout.write(s.replace("import json, re, sys", "import json, re, sys  # benign edit", 1))
' < "$SANDBOX/pristine.py" > "$SANDBOX/benign.py"
if cmp -s "$SANDBOX/pristine.py" "$SANDBOX/benign.py"; then
  fail "must-pass: the benign edit did not land"
elif run_mutant "$SANDBOX/benign.py"; then
  pass "must-pass: a semantically inert edit still exits 0 (the reds below discriminate)"
else
  fail "must-pass: an inert edit REDDENED the guard — it fails on self-edits, so every RED arm is uninformative"
fi

# --- Source-grep arms: floors that no input can exercise. ---
# Lowering a floor makes the guard strictly MORE permissive, so there is no tree that reds
# a lowered floor -- only reading the constant catches it. Exactly-one-match + ^[0-9]+$
# per the cross-file-drift convention (work/SKILL.md): the first version used `head -1`,
# and a shadowing `MIN_ROWS = 0` added later inside main() was reported "[ok] MIN_ROWS is
# 19" while the effective floor was 0.
for spec in "MIN_ROWS:19" "MIN_RESOLVED:19" "MIN_LOCKS:4"; do
  name="${spec%%:*}"; floor="${spec##*:}"
  asserted=$((asserted + 1))
  n="$(grep -cE "^ *${name} = [0-9]+" "$GUARD" || true)"
  if [[ "$n" -ne 1 ]]; then
    fail "$name: expected exactly 1 assignment, found $n — a shadowing redefinition retargets which one is effective"
    continue
  fi
  # `|| true` is load-bearing, not defensive noise: under `set -euo pipefail` a
  # zero-match grep exits 1, pipefail promotes it, and the assignment KILLS the suite
  # mid-run instead of failing this assertion. The count check above makes a no-match
  # unreachable today — which is exactly the reasoning lint-shell-capture-exit rejects,
  # because it is an invariant held somewhere else. The `^[0-9]+$` check below is what
  # turns an empty capture into a reported verdict.
  value="$({ grep -oE "^ *${name} = [0-9]+" "$GUARD" | grep -oE '[0-9]+$'; } || true)"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    fail "$name is not a plain integer ('$value')"
  elif [[ "$value" -lt "$floor" ]]; then
    fail "$name is $value, below the required floor of $floor — the floor is decorative"
  else
    pass "$name is $value (>= $floor, exactly one assignment)"
  fi
done

# The anchors are the floor under the CVE thresholds. Source-grepped here so that lowering
# a threshold AND its anchor together is a three-file edit rather than a two-line one.
for spec in "brace-expansion:1:1.1.18" "brace-expansion:2:2.1.4" "brace-expansion:5:5.0.9"; do
  IFS=: read -r pkg major want <<< "$spec"
  asserted=$((asserted + 1))
  n="$(grep -cE "^ *\(\"${pkg}\", ${major}\): \"[0-9.]+\"," "$GUARD" || true)"
  if [[ "$n" -ne 1 ]]; then
    fail "FLOOR_ANCHORS: expected exactly 1 anchor for ${pkg} line ${major}, found $n"
  elif ! grep -qF "(\"${pkg}\", ${major}): \"${want}\"," "$GUARD"; then
    fail "FLOOR_ANCHORS for ${pkg} line ${major} is not ${want} — a security floor moved without the advisory feed being re-derived"
  else
    pass "FLOOR_ANCHORS pins ${pkg} line ${major} at ${want}"
  fi
done

# --- Behavioural arms. ---

mutate "every CVE threshold zeroed to 0.0.0 REDs" "was zeroed or retargeted" '
import re, sys
Q = chr(34)
s = sys.stdin.read()
i, j = s.index("REQUIRED = ["), s.index("]", s.index("(" + Q + "pencil-setup" + Q))
body = re.sub(r"(\(" + Q + r"[^" + Q + r"]+" + Q + r", " + Q + r"[^" + Q + r"]+" + Q + r", \d+, )" + Q + r"[^" + Q + r"]+" + Q,
              lambda m: m.group(1) + Q + "0.0.0" + Q, s[i:j])
sys.stdout.write(s[:i] + body + s[j:])
'

mutate "a single zeroed threshold REDs" "was zeroed or retargeted" '
import sys
s = sys.stdin.read()
i = s.index("REQUIRED = [")
sys.stdout.write(s[:i] + s[i:].replace(chr(34) + "5.0.9" + chr(34), chr(34) + "0.0.0" + chr(34), 1))
'

mutate "a threshold lowered to the bare major floor REDs" "is the bare 7.0.0 floor" '
import sys
s = sys.stdin.read()
i = s.index("REQUIRED = [")
sys.stdout.write(s[:i] + s[i:].replace(chr(34) + "7.29.0" + chr(34), chr(34) + "7.0.0" + chr(34), 1))
'

# The mutation the structural check alone could NOT see: a real, later-than-X.0.0 patch
# level that is nonetheless below the advisory floor.
mutate "every threshold lowered to a real <major>.0.1 REDs" "was LOWERED to" '
import re, sys
Q = chr(34)
s = sys.stdin.read()
i, j = s.index("REQUIRED = ["), s.index("]", s.index("(" + Q + "pencil-setup" + Q))
body = re.sub(r"(\(" + Q + r"[^" + Q + r"]+" + Q + r", " + Q + r"[^" + Q + r"]+" + Q + r", (\d+), )" + Q + r"[^" + Q + r"]+" + Q,
              lambda m: m.group(1) + Q + m.group(2) + ".0.1" + Q, s[i:j])
sys.stdout.write(s[:i] + body + s[j:])
'

# The highest-probability drift on this file: a revert to the value #1327 replaced, which
# is a REAL historical first_patched_version and so passes every structural check.
mutate "a threshold reverted to the stale-but-real 1.1.16 REDs" "was LOWERED to" '
import sys
s = sys.stdin.read()
i, j = s.index("REQUIRED = ["), s.index("]", s.index("(\"pencil-setup\", \"fast-uri\""))
sys.stdout.write(s[:i] + s[i:j].replace(chr(34) + "1.1.18" + chr(34), chr(34) + "1.1.16" + chr(34)) + s[j:])
'

mutate "a lockfile deleted from LOCKS REDs" "below the MANIFEST floor of 4" '
import re, sys
s = sys.stdin.read()
sys.stdout.write(re.sub(r"^ *\"spike\": .*\n", "", s, count=1, flags=re.M))
'

mutate "a package name substituted for another real package REDs" "drifted from WATCHED_PACKAGES" '
import sys
s = sys.stdin.read()
sys.stdout.write(s.replace(
    chr(34) + "undici" + chr(34) + ", 7, " + chr(34) + "7.29.0" + chr(34),
    chr(34) + "chalk" + chr(34) + ", 4, " + chr(34) + "4.999.0" + chr(34), 1))
'

mutate "deleting rows from the table REDs" "below the TABLE-SIZE floor of 19" '
import re, sys
s = sys.stdin.read()
sys.stdout.write(re.sub(
    r"^ *\(\"web-platform\", \"(nanoid|js-yaml|hono|@hono/node-server|ip-address)\".*\n",
    "", s, flags=re.M))
'

mutate "a row renamed to a nonexistent package REDs" "below the RESOLVED-ROW floor of 19" '
import sys
s = sys.stdin.read()
sys.stdout.write(s.replace(chr(34) + "nanoid" + chr(34) + ", 3",
                           chr(34) + "nanoid-does-not-exist" + chr(34) + ", 3", 1))
'

# The COMPLETENESS sweep and the DEFERRED loop are the two most substantive assertions in
# the guard, and both had zero arm coverage: deleting them left every arm above green.
# The COMPLETENESS sweep is the only check that turns the table from "a coincidence of
# today'"'"'s tree" into an asserted property, and it had no arm. Dropping the row that covers
# a major the tree actually carries must be caught BY THE SWEEP -- so deleting the sweep
# makes this arm fail rather than silently pass.
mutate "a present major left uncovered by any row REDs" "which no row covers" '
import re, sys
Q = chr(34)
s = sys.stdin.read()
sys.stdout.write(re.sub(r"^ *\(" + Q + r"web-platform" + Q + r", " + Q + r"brace-expansion" + Q + r", 2,.*\n",
                        "", s, count=1, flags=re.M))
'

# Same shape for the DEFERRED presence loop: the deferral of the postcss/sharp advisories
# rests on them being next-pinned nested copies, so the loop asserting those paths still
# exist is load-bearing. Repointing one at a path the tree lacks must be caught by it.
mutate "a DEFERRED path that no longer exists REDs" "is gone" '
import sys
s = sys.stdin.read()
sys.stdout.write(s.replace("node_modules/next/node_modules/postcss",
                           "node_modules/next/node_modules/postcss-GONE", 1))
'

# --- Fixture-side arm: npm aliasing. Not a mutation of the guard at all -- a mutation of
# the TREE, which is the axis every arm above leaves untouched. This lockfile shape is
# already live (node_modules/string-width-cjs carries name=string-width), so a
# brace-expansion alias pinned below the floor is a real, reachable state.
asserted=$((asserted + 1))
if build_fixture '{"node_modules/brace-expansion-cjs": {"name": "brace-expansion", "version": "1.1.11"}}'; then
  if run_mutant "$SANDBOX/pristine.py"; then
    fail "an npm-aliased vulnerable copy exited 0 — the matchers key on the install path, not the package name"
  elif grep -qF "1.1.11" "$SANDBOX/last.out"; then
    pass "an npm-aliased brace-expansion@1.1.11 is seen and flagged"
  else
    fail "reddened, but without naming the aliased 1.1.11"
  fi
else
  fail "could not rebuild the fixture with an alias entry"
fi
build_fixture || { echo "FATAL: could not restore the fixture tree" >&2; exit 2; }

# --- Accounting. Emitted DIRECTLY, never through fail(): a conservation check routed
# through the verdict helper it exists to police cannot report the fault that corrupted it.
if [[ $((passes + fails)) -ne $asserted ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != asserted (%d).\n' \
    "$((passes + fails))" "$asserted" >&2
  if [[ $((passes + fails)) -lt "$asserted" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded without a counted case — a call site is missing its increment (a harness bug, not a product failure).\n' >&2
  fi
  exit 1
fi

MIN_ASSERTIONS=20
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS} — arms were deleted or neutered" >&2
  exit 1
fi

echo
echo "assert-dependabot-drain.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
