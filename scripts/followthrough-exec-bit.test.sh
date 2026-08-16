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
oks=0
# `checked` is incremented at the CALL SITE — once per probe, immediately before the decision
# that resolves to exactly one verdict — and NEVER inside ok()/fail(). That placement is the
# whole substance of the conservation check at the bottom of this file: a counter moved inside
# both verdict helpers moves WITH the verdict, so stubbing `fail() { :; }` drops the row and
# its count together, `oks + fails == checked` still holds, the cardinality floor is still
# satisfied at full value, and a 100644 probe ships behind a clean PASSED.
#
# Never increment inside `$( )` — a subshell discards it.
checked=0
pass() { printf '  ✓ %s\n' "$1"; }
# Per-row verdict recorders. ok() is deliberately silent — 68 identical ✓ lines would bury the
# one ✗ that matters — but it MOVES A COUNTER, and that counter is what conservation reads.
ok() { oks=$((oks + 1)); }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

echo "followthrough-exec-bit: every scripts/followthroughs/*.sh must be committed 100755"

# `git ls-files -s` emits: <mode> <sha> <stage>\t<path>
listing=$(git ls-files -s -- 'scripts/followthroughs/*.sh')

if [[ -z "$listing" ]]; then
  # Reported directly, never through fail(): a listing that is empty is exactly the state in
  # which every assertion below is vacuous, so the report must not depend on the machinery
  # those assertions use.
  printf '\n[FATAL] anti-vacuity floor: only 0 assertion(s) ran, expected >= 1 — no scripts/followthroughs/*.sh are tracked, so this gate would pass vacuously.\n' >&2
  exit 1
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  mode=${line%% *}
  path=${line#*$'\t'}
  # One assertion is about to be decided. Counted HERE, at the call site, so it keeps its
  # value even when the verdict below is discarded.
  checked=$((checked + 1))
  if [[ "$mode" != "100755" ]]; then
    fail "$path is mode $mode — must be 100755, or sweep-followthroughs.sh silently skips it (no run, no comment)"
  else
    ok
  fi
done <<< "$listing"

# --- Anti-vacuity floor -----------------------------------------------------------------------
# A probe set that silently shrinks would make every assertion above vacuous — a broken glob
# yields 0 rows and a clean PASSED.
#
# Reported with `printf >&2` + `exit 1` DIRECTLY, never through fail(). A floor that reports by
# calling fail() increments the same counter the exit status reads, so neutering fail() silences
# the rows AND the floor that exists to notice the silence. A floor enforced through the suspect
# cannot witness the suspect.
#
# Hand-ratcheted at the measured green count with ZERO slack, and it may only be RAISED. The
# earlier loose floor of 10 was satisfied by 58 probes silently vanishing from the index.
MIN_PROBES=68
if (( checked < MIN_PROBES )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$checked" "$MIN_PROBES" >&2
  echo "FAILED: $fails" >&2
  exit 1
fi

# --- Accounting conservation ------------------------------------------------------------------
# The arm that actually catches a neutered verdict helper. The floor above catches "no
# assertions RAN"; it cannot catch "assertions ran and their verdicts were discarded", because
# `checked` keeps its full value when fail() is a no-op. Every probe records exactly one
# verdict, so oks+fails MUST equal checked. Reported directly for the same reason as the floor.
if (( oks + fails != checked )); then
  printf '\n[FATAL] accounting: oks+fails (%d) != checked (%d).\n' "$((oks + fails))" "$checked" >&2
  if (( oks + fails < checked )); then
    printf '  A probe was counted but its verdict was not recorded — that is what a neutered ok()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded on a row with no `checked=$((checked + 1))` before it. This is a harness bug, not a probe failure: add the increment at that call site.\n' >&2
  fi
  echo "FAILED: $fails" >&2
  exit 1
fi

if (( fails == 0 )); then
  pass "$checked probe(s) all committed 100755"
  echo "PASSED"
  exit 0
fi

echo "FAILED: $fails" >&2
exit 1
