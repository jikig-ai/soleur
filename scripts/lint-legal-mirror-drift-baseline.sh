#!/usr/bin/env bash
# lint-legal-mirror-drift-baseline.sh -- gate 2 of #7387.
#
# Asserts that canonical<->mirror drift at HEAD is a SUBSET of drift at the merge base,
# with relative order preserved. A ratchet, not a zero assertion.
#
# WHY A RATCHET AND NOT ZERO. The corpus carries substantial pre-existing drift between
# docs/legal/<doc>.md and its Eleventy mirror. A zero assertion would be unshippable and
# disabled within a day; equality would red the remediation PR that reduces the drift,
# which is the one PR that must never be blocked. Subset-with-order passes reduction,
# fails growth, and ratchets down naturally as the corpus is repaired.
#
# WHAT THIS GATE FREEZES, STATED PLAINLY. The frozen divergence is not neutral formatting.
# The published mirror UNDER-DISCLOSES relative to the canonical record. Measured omissions
# include collected-data categories, a named third-country recipient (ANTHROPIC, US),
# lawful bases, a retention period, the Art. 15/20 self-serve export route, and an Art. 14
# posture for involuntary third-party data subjects.
#
# That divergence is tracked on #7349, which carries a remediation target of 2026-09-30.
# The date is part of this gate's contract, not a footnote: a knowingly-retained divergence
# bears on GDPR Art. 83(2)(b) (intentional or negligent character) and 83(2)(c) (mitigating
# action taken), and a permanent freeze with no date is documentary evidence that the
# divergence was measured, understood, and institutionalised. If the date on #7349 moves,
# move it here too -- the two are deliberately coupled, and the suite asserts this header
# still carries both the issue number and the date.
#
# WHAT NO OTHER GATE SEES. legal-doc-consistency compares heading SEQUENCE; check-tc-
# document-sha compares canonical HASHES and its body-equivalence step is T&C-only. Neither
# can see the same content landing in a different POSITION on the mirror -- the published
# page then presents those rights in a sequence the record does not. All three gates were
# green while exactly that was true.
#
# Exit codes:  0 clean   1 drift grew   2 cannot decide (never a vacuous 0)

set -euo pipefail

export LC_ALL=C

# Behaviour toggles exist so the suite's mutation battery can neuter each property
# independently. They are not a runtime configuration surface.
RATCHET_ENABLED=1
ORDER_SENSITIVE=1
NEW_PAIR_MUST_BE_CLEAN=1

CANONICAL_DIR="docs/legal"
MIRROR_DIR="plugins/soleur/docs/pages/legal"

BASE_REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_REF="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------
# Event-aware base resolution.
#
# A PR resolves against its target branch, a merge-queue run against the ancestor SHA the
# queue built on, and a direct push against origin/main. The merge BASE is used rather than
# the tip: comparing against a moving tip would attribute a sibling PR's drift to this one.
# ---------------------------------------------------------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "::error::not inside a git work tree; cannot compute a drift baseline" >&2
  exit 2
fi

if [[ -z "$BASE_REF" ]]; then
  if [[ -n "${MERGE_GROUP_BASE_SHA:-}" ]]; then
    BASE_REF="$MERGE_GROUP_BASE_SHA"
  elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    BASE_REF="origin/${GITHUB_BASE_REF}"
  else
    BASE_REF="origin/main"
  fi
fi

if [[ "$BASE_REF" == origin/* ]]; then
  git fetch --no-tags --quiet origin "${BASE_REF#origin/}" 2>/dev/null || true
fi

if ! BASE_SHA=$(git rev-parse --verify --quiet "${BASE_REF}^{commit}"); then
  echo "::error::base ref '${BASE_REF}' does not resolve; refusing to report clean" >&2
  exit 2
fi

if ! MERGE_BASE=$(git merge-base HEAD "$BASE_SHA" 2>/dev/null) || [[ -z "$MERGE_BASE" ]]; then
  # A push directly to the base branch legitimately has HEAD as its own ancestor; that case
  # resolves above. Reaching here means the histories are genuinely unrelated.
  echo "::error::no merge base between HEAD and '${BASE_REF}'; refusing to report clean" >&2
  exit 2
fi

# ---------------------------------------------------------------------------------------
# Shared normaliser. Sourced, never reimplemented -- a second normaliser is a second thing
# to drift, and the two would disagree silently in opposite directions.
# ---------------------------------------------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel)"
NORMALISE_LIB="$REPO_ROOT/scripts/lib/legal-normalise.sh"
if [[ ! -f "$NORMALISE_LIB" ]]; then
  echo "::error::shared normaliser missing: $NORMALISE_LIB" >&2
  exit 2
fi
# shellcheck source=lib/legal-normalise.sh
. "$NORMALISE_LIB"

WORK=$(mktemp -d -t legal-drift.XXXXXXXX) || exit 2
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------------------
# The drift primitive.
#
# diff of the two normalised bodies, reduced to an ORDERED SEQUENCE of drifting text lines:
# `<`/`>` markers stripped, `NcN` / `NaN` / `NdN` position headers and `---` separators
# dropped. Positions are deliberately excluded. A lockstep edit that shifts every line
# number changes every position header while changing no drift at all, so a primitive that
# kept them would false-fire on the most common legitimate edit -- and a gate that
# false-fires on the common case gets disabled.
#
# Order is retained inside the sequence because ORDER IS THE DEFECT: the same clauses in a
# different sequence on the published page is precisely what no other gate can see.
# ---------------------------------------------------------------------------------------

drift_seq() {
  local canon="$1" mirror="$2"
  diff <(normalize_canonical "$canon" | collapse) <(normalize_plugin "$mirror" | collapse) \
    | sed -E '/^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$/d; /^---$/d' \
    | sed -E 's/^[<>] ?//' \
    || true
}

# Materialise a path as it existed at the merge base. Empty output + non-zero means the
# path did not exist there.
show_at_base() {
  git show "${MERGE_BASE}:$1" 2>/dev/null
}

# Is `needle` (ordered sequence) a SUBSEQUENCE of `hay`? Order-sensitive by construction:
# with ORDER_SENSITIVE off this degrades to a multiset containment check, which is exactly
# the blindness the reorder fixture pins.
is_subsequence() {
  local needle="$1" hay="$2"
  if (( ORDER_SENSITIVE )); then
    awk -v needlefile="$needle" '
      BEGIN {
        n = 0
        while ((getline line < needlefile) > 0) { need[++n] = line }
        i = 1
      }
      { if (i <= n && $0 == need[i]) i++ }
      END { exit (i > n ? 0 : 1) }
    ' "$hay"
  else
    # Unordered containment: every needle line must appear in hay at least as often.
    local missing
    missing=$(comm -23 <(sort "$needle") <(sort "$hay") | grep -cE '.' || true)
    [[ "$missing" == "0" ]]
  fi
}

# ---------------------------------------------------------------------------------------
# Pair enumeration: the UNION of base-side and HEAD-side names, so a pair that only exists
# on one side is still evaluated rather than silently skipped.
# ---------------------------------------------------------------------------------------

names=$(
  {
    git ls-tree -r --name-only "$MERGE_BASE" -- "$CANONICAL_DIR" "$MIRROR_DIR" 2>/dev/null || true
    git ls-files -- "$CANONICAL_DIR" "$MIRROR_DIR" 2>/dev/null || true
    ls "$CANONICAL_DIR"/*.md "$MIRROR_DIR"/*.md 2>/dev/null || true
  } | sed -nE 's|.*/([^/]+)\.md$|\1|p' | sort -u
)

name_count=$(printf '%s\n' "$names" | grep -cE '.' || true)
if [[ "$name_count" == "0" ]]; then
  echo "::error::no legal documents found under ${CANONICAL_DIR}/ or ${MIRROR_DIR}/ (cwd: $(pwd)); refusing to report clean" >&2
  exit 2
fi

# Cross-check against the SHA guard's sentinel. A warning, not a failure: the guard already
# treats its own count as a tripwire rather than a gate, and duplicating a hard failure here
# would make a legitimate corpus change red two places for one reason.
# `|| true` INSIDE the substitution, not after it. Under `set -euo pipefail` an
# assignment-only command takes the status of its right-hand side, and `2>/dev/null` on a
# pipeline whose first stage fails still yields a non-zero pipeline status -- so the
# obvious form aborts the whole gate, silently and with no output, whenever this optional
# cross-check file is absent. A cross-check that can kill the gate is worse than no
# cross-check.
expected=$( { sed -nE 's/^EXPECTED_COUNT=([0-9]+)$/\1/p' \
               "$REPO_ROOT/apps/web-platform/scripts/check-tc-document-sha.sh" 2>/dev/null \
               || true; } | head -1 )
live_pairs=$(ls "$CANONICAL_DIR"/*.md 2>/dev/null | grep -cE '.' || true)
if [[ -n "$expected" && "$live_pairs" != "0" && "$live_pairs" != "$expected" ]]; then
  echo "::warning::${CANONICAL_DIR}/ holds ${live_pairs} docs; check-tc-document-sha.sh EXPECTED_COUNT=${expected}. Update it if intentional." >&2
fi

violations=0
unpaired=0
checked=0
report="$WORK/report.txt"
: > "$report"

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  cpath="$CANONICAL_DIR/$name.md"
  mpath="$MIRROR_DIR/$name.md"

  c_head=0; [[ -f "$cpath" ]] && c_head=1
  m_head=0; [[ -f "$mpath" ]] && m_head=1

  c_base=0; show_at_base "$cpath" >/dev/null 2>&1 && c_base=1
  m_base=0; show_at_base "$mpath" >/dev/null 2>&1 && m_base=1

  # Retired on both surfaces: legitimate.
  if (( ! c_head && ! m_head )); then
    continue
  fi

  # One surface gone, the other still published.
  if (( c_head != m_head )); then
    if (( c_base && m_base )); then
      {
        echo "  ${name}: one surface was deleted, the other is still published"
        echo "    canonical: ${cpath} $(( c_head ? 1 : 0 )) present at HEAD"
        echo "    mirror:    ${mpath} $(( m_head ? 1 : 0 )) present at HEAD"
        echo "    Remediation: delete both surfaces, or restore the missing one. A document"
        echo "    that exists on exactly one surface has no baseline and cannot be compared."
      } >> "$report"
      violations=$((violations + 1))
    else
      echo "::error::${name} exists on exactly one surface and has no baseline; cannot decide" >&2
      unpaired=$((unpaired + 1))
    fi
    continue
  fi

  head_seq="$WORK/${name}.head"
  drift_seq "$cpath" "$mpath" > "$head_seq"
  head_n=$(grep -cE '.' < "$head_seq" || true)
  checked=$((checked + 1))

  # A pair absent from the base has no baseline to ratchet against. Requiring it to start
  # clean is also how a RENAME is handled WITHOUT consulting git history: the renamed doc is
  # a new pair at HEAD and must be drift-free. A history-based rule would read a head-side
  # rename as a shrink and silently hide the drift it carried.
  if (( ! c_base || ! m_base )); then
    if (( NEW_PAIR_MUST_BE_CLEAN && head_n > 0 )); then
      {
        echo "  ${name}: NEW document pair carries ${head_n} line(s) of drift"
        echo "    canonical: ${cpath}"
        echo "    mirror:    ${mpath}"
        echo "    Remediation: a pair with no baseline must start at zero drift. Sync the two"
        echo "    surfaces before merging; there is no prior state to ratchet against."
        echo "    (A renamed document is a new pair here by design -- see the header.)"
      } >> "$report"
      violations=$((violations + 1))
    fi
    continue
  fi

  base_seq="$WORK/${name}.base"
  bc="$WORK/${name}.base.canon.md"
  bm="$WORK/${name}.base.mirror.md"
  show_at_base "$cpath" > "$bc"
  show_at_base "$mpath" > "$bm"
  drift_seq "$bc" "$bm" > "$base_seq"
  base_n=$(grep -cE '.' < "$base_seq" || true)

  if (( ! RATCHET_ENABLED )); then
    continue
  fi

  if ! is_subsequence "$head_seq" "$base_seq"; then
    direction="grew"
    (( head_n < base_n )) && direction="reordered"
    {
      echo "  ${name}: drift ${direction} (baseline ${base_n} line(s) -> HEAD ${head_n} line(s))"
      echo "    canonical: ${cpath}"
      echo "    mirror:    ${mpath}"
      echo "    Drift lines present at HEAD but not in the baseline sequence:"
      comm -23 <(sort "$head_seq") <(sort "$base_seq") | head -12 | sed 's/^/      + /'
      if (( head_n <= base_n )); then
        echo "    NOTE: HEAD carries no more drift lines than the baseline, so this is an"
        echo "    ORDER change: the same content now lands in a different position on the two"
        echo "    surfaces. No other gate sees this -- legal-doc-consistency compares heading"
        echo "    sequence, and the SHA guard compares canonical hashes."
      fi
      echo "    Remediation: apply the change to BOTH surfaces in the same commit, in the same"
      echo "    position. Reducing drift always passes; only growth and reordering fail."
    } >> "$report"
    violations=$((violations + 1))
  fi
done <<< "$names"

if (( unpaired > 0 )); then
  echo "::error::${unpaired} legal document(s) exist on exactly one surface; cannot compute a baseline" >&2
  exit 2
fi

if (( checked == 0 )); then
  echo "::error::no comparable document pairs were evaluated; refusing to report clean" >&2
  exit 2
fi

if (( violations > 0 )); then
  echo "::error::legal mirror drift: ${violations} document(s) drifted beyond the baseline" >&2
  cat "$report" >&2
  exit 1
fi

echo "legal mirror drift: ${checked} pair(s) checked, drift is within the baseline."
echo "  This is a RATCHET, not a clean bill of health. It asserts drift did not GROW or"
echo "  REORDER relative to the merge base. It does NOT assert the two surfaces agree:"
echo "  the published mirror under-discloses relative to the record (collected-data"
echo "  categories, the Anthropic/US transfer, lawful bases, a retention period, the"
echo "  Art. 15/20 export route, and an Art. 14 posture). That is tracked on #7349 with a"
echo "  remediation target of 2026-09-30. This gate freezes the divergence; it does not"
echo "  bless it."
exit 0
