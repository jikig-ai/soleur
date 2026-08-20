#!/usr/bin/env bash
# Guard for scripts/assert-dependabot-drain.py (#1327).
#
# That script had NO test file at all, and its two anti-vacuity floors — MIN_ROWS and
# MIN_RESOLVED — both count ROWS. Nothing floored the fourth tuple element, which is the
# only thing the reconciliation table exists to enforce: setting all 19 CVE thresholds to
# "0.0.0" printed a confident clean summary and exited 0. Three more mutations were also
# silent: deleting a manifest from LOCKS, substituting one row's package name for another
# real package, and lowering any floor to a decorative value.
#
# Shape follows scripts/lint-dual-lockfile.test.sh: source-greps for the floors that
# cannot be exercised behaviourally (lowering a floor makes the guard MORE permissive, so
# no input reds it), plus behavioural arms that mutate a sandbox copy and require a
# non-zero exit AND the message that names the cause.
#
# Every behavioural arm asserts its mutation LANDED before running the mutant. A mutation
# that silently fails to apply re-runs the BASELINE, and a green baseline is
# indistinguishable from a guard that caught nothing.
set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/assert-dependabot-drain.py"
SANDBOX="$(mktemp -d -t drain-guard.XXXXXXXX)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

fails=0
asserted=0

pass() { asserted=$((asserted + 1)); echo "[ok] $1"; }
fail() { asserted=$((asserted + 1)); fails=$((fails + 1)); echo "[FAIL] $1"; }

[[ -r "$GUARD" ]] || { echo "FATAL: cannot read $GUARD"; exit 2; }
cp "$GUARD" "$SANDBOX/pristine.py" || { echo "FATAL: could not seed the sandbox"; exit 2; }

# Run a copy of the guard from the repo root, where its relative lockfile paths resolve.
run_mutant() {
  local script="$1" out rc=0
  out="$(cd "$REPO_ROOT" && python3 "$script" 2>&1)" || rc=$?
  printf '%s' "$out" > "$SANDBOX/last.out"
  return "$rc"
}

# mutate <label> <expected-substring-of-message> <python-mutator...>
# The mutator reads pristine.py on stdin and writes the mutant on stdout.
mutate() {
  local label="$1" expect="$2"; shift 2
  local mutant="$SANDBOX/mutant.py"
  python3 -c "$1" < "$SANDBOX/pristine.py" > "$mutant" || { fail "$label: mutator crashed"; return; }
  if cmp -s "$SANDBOX/pristine.py" "$mutant"; then
    fail "$label: the mutation did NOT land — this arm re-ran the baseline and proves nothing"
    return
  fi
  if run_mutant "$mutant"; then
    fail "$label: the mutant exited 0 — the guard did not catch it"
    return
  fi
  if ! grep -qF -- "$expect" "$SANDBOX/last.out"; then
    fail "$label: reddened, but for the wrong reason (no '$expect' in the output)"
    return
  fi
  pass "$label"
}

# --- Control. A red baseline voids every arm below. ---
if run_mutant "$SANDBOX/pristine.py"; then
  pass "control: the unmutated guard exits 0 against the real lockfiles"
else
  fail "control: the unmutated guard is already RED — every mutation arm below is void"
  echo "--- control output ---"; cat "$SANDBOX/last.out"; echo "--- end ---"
  echo; echo "$asserted assertions, $fails failed"; exit 1
fi

# --- Source-grep arms: the floors must not be decorative. ---
# These cannot be behavioural. Lowering a floor makes the guard strictly more permissive,
# so there is no input that reds a lowered floor — only reading the constant catches it.
for spec in "MIN_ROWS:19" "MIN_RESOLVED:19" "MIN_LOCKS:4"; do
  name="${spec%%:*}"; floor="${spec##*:}"
  value="$(grep -oE "^ *${name} = [0-9]+" "$GUARD" | grep -oE '[0-9]+$' | head -1 || true)"
  if [[ -z "$value" ]]; then
    fail "$name is missing from the guard entirely"
  elif [[ "$value" -lt "$floor" ]]; then
    fail "$name is $value, below the required floor of $floor — the floor is decorative"
  else
    pass "$name is $value (>= $floor)"
  fi
done

# --- Behavioural arms. ---

# The headline mutation: zero every CVE threshold. Both count floors stay satisfied.
mutate "every CVE threshold zeroed to 0.0.0 REDs" "was zeroed or retargeted" '
import re, sys
s = sys.stdin.read()
s = re.sub(r'"'"'(\("[^"]+", "[^"]+", \d+, )"[^"]+"'"'"', r'"'"'\g<1>"0.0.0"'"'"', s)
sys.stdout.write(s)
'

# One threshold, not all. A per-row check has to fire on a single row.
mutate "a single zeroed threshold REDs" "was zeroed or retargeted" '
import sys
s = sys.stdin.read()
s = s.replace(chr(34) + "5.0.9" + chr(34), chr(34) + "0.0.0" + chr(34), 1)
sys.stdout.write(s)
'

# The subtler form: keep the major line, drop to the bare X.0.0, which admits every
# vulnerable release on that line. This is what a major-line-only check would miss.
mutate "a threshold lowered to the bare major floor REDs" "is the bare 7.0.0 floor" '
import sys
s = sys.stdin.read()
s = s.replace(chr(34) + "7.29.0" + chr(34), chr(34) + "7.0.0" + chr(34), 1)
sys.stdout.write(s)
'

# F4: a manifest dropped from LOCKS. No row names "spike", so this was fully silent.
mutate "a lockfile deleted from LOCKS REDs" "below the floor of 4" '
import re, sys
s = sys.stdin.read()
s = re.sub(r'"'"'^ *"spike": .*\n'"'"', "", s, count=1, flags=re.M)
sys.stdout.write(s)
'

# F5: a row substituted for a DIFFERENT REAL package that resolves on the declared major
# line. len(REQUIRED) and `resolved` both stay at 19, so neither count floor moves.
mutate "a package name substituted for another real package REDs" "drifted from WATCHED_PACKAGES" '
import sys
s = sys.stdin.read()
s = s.replace(
    chr(34) + "undici" + chr(34) + ", 7, " + chr(34) + "7.29.0" + chr(34),
    chr(34) + "chalk" + chr(34) + ", 4, " + chr(34) + "4.1.2" + chr(34), 1)
sys.stdout.write(s)
'

# The pre-existing floors must still work. Retained so a future edit cannot trade the new
# threshold checks for the row-count ones.
mutate "deleting rows from the table REDs" "below the floor of 19" '
import re, sys
s = sys.stdin.read()
s = re.sub(r'"'"'^ *\("web-platform", "(nanoid|js-yaml|hono|@hono/node-server|ip-address)".*\n'"'"',
           "", s, flags=re.M)
sys.stdout.write(s)
'

mutate "a row renamed to a nonexistent package REDs" "rows resolved to an installed version" '
import sys
s = sys.stdin.read()
s = s.replace(chr(34) + "nanoid" + chr(34) + ", 3", chr(34) + "nanoid-does-not-exist" + chr(34) + ", 3", 1)
sys.stdout.write(s)
'

echo
echo "$asserted assertions, $fails failed"
[[ "$fails" -eq 0 ]]
