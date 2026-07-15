#!/usr/bin/env bash
# Guards that every scripts/followthroughs/*.sh is committed executable (100755).
#
# Why this exists (#6435): zot-soak-6122.sh shipped as mode 100644 — the sole non-100755
# outlier in the probe set. sweep-followthroughs.sh rejects a non-executable probe at an
# `[[ ! -x "$script" ]]` guard BEFORE the `env -i` exec, via fail() which is `printf ... >&2`
# and nothing else, then `return 0`. No run, no exit code, no comment on the tracker, no
# TRANSIENT bucket — the tracker just sits open while its gate is silently inert, an
# hr-no-dashboard-eyeball-pull-data-yourself surface discoverable only by reading the
# sweeper job's stderr.
#
# Scope note (do not overstate this gate): mode 100644 was a LATENT defect on that probe, not
# the reason it never ran — it is also unenrolled (no tracker carries its directive), so the
# sweeper never reaches the exec-bit guard for it. This gate closes the executability half for
# the whole class, so the next probe cannot ship dead-on-arrival. It does NOT prove a probe is
# reachable; an orphaned probe passes this gate while running never. Reachability is tracked
# separately.
#
# Asserts the INDEX mode (git ls-files -s), not the worktree bit (test -x): the bug was
# committed as 100644, and a worktree-only chmod that never reaches the index would satisfy
# `test -x` locally and still ship a dead probe. The index is what CI and the sweeper consume.
#
# Guards the CLASS, not the instance: fixing one file and hoping is the same defect this
# repo keeps re-learning — a guard that does not pin the thing it names.

set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 2

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

echo "followthrough-exec-bit: every scripts/followthroughs/*.sh must be committed 100755"

# `git ls-files -s` emits: <mode> <sha> <stage>\t<path>
listing=$(git ls-files -s -- 'scripts/followthroughs/*.sh')

if [[ -z "$listing" ]]; then
  fail "no scripts/followthroughs/*.sh are tracked — the glob matched nothing, so this gate would pass vacuously"
  echo "FAILED: $fails" >&2
  exit 1
fi

checked=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  mode=${line%% *}
  path=${line#*$'\t'}
  checked=$((checked + 1))
  if [[ "$mode" != "100755" ]]; then
    fail "$path is mode $mode — must be 100755, or sweep-followthroughs.sh silently skips it (no run, no comment)"
  fi
done <<< "$listing"

# Minimum-cardinality guard: a probe set that silently shrinks would make every assertion
# above vacuous. Deliberately a loose floor, not an exact count — the probe set grows with
# every follow-through, so an exact expected-N here would rot into a false RED on the next
# one. The floor only has to be high enough that a broken glob (which yields 0) fails.
if (( checked < 10 )); then
  fail "only $checked probe(s) checked — expected the full scripts/followthroughs/*.sh set; the glob or listing is broken"
fi

if (( fails == 0 )); then
  pass "$checked probe(s) all committed 100755"
  echo "PASSED"
  exit 0
fi

echo "FAILED: $fails" >&2
exit 1
