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
# The published mirror UNDER-DISCLOSES relative to the canonical record. VERIFIED omissions,
# each re-measured against the drift this gate actually computes, at #7349 merge sign-off:
#   - a named sub-processor (Bullet Train Ltd / Flagsmith) in gdpr-policy;
#   - the Art. 14 information posture and the DPIA-status statement in gdpr-policy;
#   - the Art. 15/20 request-channel split (self-serve vs email) in gdpr-policy Sec. 8;
#   - the LinkedIn Company Page data category and its two international-transfer rows, and
#     the community-digest rights carve-out, in privacy-policy.
#
# The PRIOR enumeration here -- "collected-data categories (team/agent customisation data,
# turn summaries, message attachments, workspace logo, BYOK usage audit log, beta-tester
# CRM); lawful bases; the Art. 15/20 self-serve export route" -- was CORRECT WHEN WRITTEN and
# was falsified by #7349, which put all six named categories on the mirror, brought
# gdpr-policy's Art. 6(1) bullets to 12/12 parity with zero canonical-only bullets, and
# published /dashboard/settings/privacy. It is restated rather than deleted because a header
# that silently swaps one omission list for another teaches the next reader nothing about how
# often this list goes stale. RE-MEASURE THIS LIST WHENEVER DRIFT MOVES; do not inherit it.
#
# An earlier version of this header also claimed the mirror omits "a named third-country
# recipient (Anthropic, US)". That is WITHDRAWN and was wrong: the mirror discloses the
# transfer and names the recipient (gdpr-policy.md:206, "record content is transmitted to
# Anthropic (US) ... a Chapter V transfer"; `Anthropic` occurs 18 times on each surface).
# The drift line is a rewording, not an omission. Two further items were narrower than
# stated: both surfaces carry a **Retention:** block (only the statutory_repin_send row is
# canonical-only), and the mirror carries Article 14 at three sites including the
# involuntary-third-party case (only the beta-CRM posture paragraph is canonical-only).
#
# That correction matters rather than being a wording nit: this header is cited as Art.
# 83(2)(b)/(c) evidence that the divergence was MEASURED. A compliance artifact asserting a
# measurement it did not perform, on a point the corpus contradicts, weakens the exact claim
# it was written to support. The list came from an issue body and was reproduced here under
# the word "measured" without being checked. Corrected on #7349 too.
#
# That divergence is tracked on #7465, which carries a remediation target of 2026-09-30.
# The date is part of this gate's contract, not a footnote: a knowingly-retained divergence
# bears on GDPR Art. 83(2)(b) (intentional or negligent character) and 83(2)(c) (mitigating
# action taken), and a permanent freeze with no date is documentary evidence that the
# divergence was measured, understood, and institutionalised. If the date on #7465 moves,
# move it here too -- the two are deliberately coupled, and the suite asserts this header
# still carries both the issue number and the date.
#
# WHAT NO OTHER GATE SEES. legal-doc-consistency compares heading SEQUENCE; check-tc-
# document-sha compares canonical HASHES and its body-equivalence step covers terms-and-conditions, acceptable-use-policy and disclaimer (#7349). Neither
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

# An explicit usage block: `sed -n '2,40p' "$0"` printed `set -euo pipefail` and the toggle
# comments as though they were documentation, and silently changed meaning on every header
# edit.
usage() {
  cat <<'USAGE'
lint-legal-mirror-drift-baseline.sh -- gate 2 of #7387

  --base <ref>   Diff base. Default: MERGE_GROUP_BASE_SHA, else origin/$GITHUB_BASE_REF,
                 else origin/main.
  -h, --help     This text.

Asserts canonical<->mirror drift at HEAD is a subsequence of drift at the merge base.
Reduction always passes; growth, reordering and in-place edits of drifting lines fail.

Break-glass: SOLEUR_LEGAL_DRIFT_ACCEPT=<reason> downgrades a failure to a warning. Intended
for a revert of a merged drift-reducing PR, which is otherwise unrevertable, and for an
urgent legal publication. The reason is echoed into the run log.

Exit codes: 0 clean, 1 drift grew/reordered/changed, 2 cannot decide.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    # `$# -lt 2` guarded: a bare trailing `--base` made `shift 2` fail inside a `while` body,
    # which is NOT exempt from `set -e`, so the gate died with rc=1 and no output -- "cannot
    # decide" mislabelled as "violation".
    --base)
      if [[ $# -lt 2 ]]; then echo "::error::--base requires a value" >&2; exit 2; fi
      BASE_REF="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "::error::unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------
# Event-aware base resolution.
#
# A PR resolves against its target branch, a merge-queue run against the ancestor SHA the
# queue built on, and a direct push against origin/main. The merge BASE is used rather than
# the tip: comparing against a moving tip would attribute a sibling PR's drift to this one.
# ---------------------------------------------------------------------------------------

_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_LIB="$_GATE_DIR/lib/legal-base-ref.sh"
if [[ ! -f "$BASE_LIB" ]]; then
  echo "::error::shared base resolver missing: $BASE_LIB" >&2
  exit 2
fi
# shellcheck source=lib/legal-base-ref.sh
. "$BASE_LIB"

_base_out=""
_base_rc=0
_base_out=$(legal_resolve_base "$BASE_REF") || _base_rc=$?
if (( _base_rc != 0 )); then
  exit 2
fi
RESOLVED_REF="${_base_out%%$'\t'*}"
MERGE_BASE="${_base_out##*$'\t'}"

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
#
# THE SURFACE MARKER IS KEPT. Stripping `<`/`>` erased which surface each drifting line was
# on, and this gate's entire framing -- and the Art. 83(2)(b)/(c) argument that rests on it
# -- is that the MIRROR under-discloses relative to the canonical record. With the marker
# gone, moving a clause from canonical to mirror produced a byte-identical drift sequence, so
# a PR that DELETED a clause from the record and published it only on the mirror passed the
# ratchet. That is the inversion of the posture the gate exists to hold. `<` is the canonical
# side, `>` the mirror side; both the subsequence check and the report read them.
#
# `---` is dropped only when it is diff's own change-hunk separator, i.e. only between a `<`
# run and a `>` run. A bare `/^---$/d` also deleted a markdown thematic break that is real
# corpus content (zero such lines today, so this is latent, not live).
# ---------------------------------------------------------------------------------------

drift_seq() {
  local canon="$1" mirror="$2"
  diff <(normalize_canonical "$canon" | collapse) <(normalize_plugin "$mirror" | collapse) \
    | awk '
        /^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$/ { next }   # position header
        /^---$/ { if (sep_armed) { sep_armed=0; next } }      # hunk separator, not content
        /^[<>]/ {
          side = substr($0, 1, 1)
          text = substr($0, 2)
          sub(/^ /, "", text)
          sep_armed = (side == "<")
          printf "%s%s\n", side, text
          next
        }
        { sep_armed = 0 }
      ' \
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

shopt -s nullglob
canon_live=("$CANONICAL_DIR"/*.md)
mirror_live=("$MIRROR_DIR"/*.md)
shopt -u nullglob

# `-c core.quotePath=false` on BOTH git calls: by default git octal-escapes and double-quotes
# any path with a non-ASCII byte, and the trailing quote defeats the `\.md$` anchor, so such a
# document is dropped from enumeration entirely. The case that actually escapes is a
# non-ASCII-named doc deleted from one surface -- absent from the live globs, quoted by both
# git calls, therefore never enumerated, so the one-sided-delete check never fires.
#
# The sed anchors the DIRECTORY PREFIX so only direct children are enumerated. `ls-tree -r`
# recurses, so `docs/legal/v2/privacy-policy.md` previously collapsed onto the same name as
# its top-level twin and the subdirectory pair was never compared. Non-recursive matches
# check-tc-document-sha.sh, whose own glob is `"$CANONICAL_DIR"/*.md`.
names=$(
  {
    git -c core.quotePath=false ls-tree -r --name-only "$MERGE_BASE" -- "$CANONICAL_DIR" "$MIRROR_DIR" 2>/dev/null || true
    git -c core.quotePath=false ls-files -- "$CANONICAL_DIR" "$MIRROR_DIR" 2>/dev/null || true
    printf '%s\n' ${canon_live[@]+"${canon_live[@]}"} ${mirror_live[@]+"${mirror_live[@]}"}
  } | sed -nE 's#^(docs/legal|plugins/soleur/docs/pages/legal)/([^/]+)\.md$#\2#p' | sort -u
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
# Anchored to match the vitest guard's own /^EXPECTED_COUNT=(\d+)\b/m, not `$`. With the `$`
# anchor a trailing comment -- `EXPECTED_COUNT=10  # added retention policy`, an entirely
# natural edit for a sentinel whose purpose is documentation -- parsed as empty, the
# `[[ -n "$expected" ]]` guard below was false, and the cross-check silently did not run while
# the vitest guard stayed green. Parse failure is now distinguishable from success.
_tc_sha_script="$REPO_ROOT/apps/web-platform/scripts/check-tc-document-sha.sh"
expected=$( { sed -nE 's/^EXPECTED_COUNT=([0-9]+).*$/\1/p' "$_tc_sha_script" 2>/dev/null || true; } | head -1 )
if [[ -f "$_tc_sha_script" && -z "$expected" ]]; then
  echo "::warning::could not parse EXPECTED_COUNT from ${_tc_sha_script}; the pair-count cross-check did NOT run" >&2
fi
# Count via a nullglob array rather than `ls | grep -c`: parsing `ls` breaks on filenames
# containing newlines (SC2010), and an empty directory would otherwise count the glob
# pattern itself as one entry.
live_pairs=${#canon_live[@]}
if [[ -n "$expected" && "$live_pairs" != "0" && "$live_pairs" != "$expected" ]]; then
  echo "::warning::${CANONICAL_DIR}/ holds ${live_pairs} docs; check-tc-document-sha.sh EXPECTED_COUNT=${expected}. Update it if intentional." >&2
fi

# Single source for the remediation date so the header, the PASS message and the expiry
# check cannot drift apart. Coupled to #7465 by design.
REMEDIATION_TARGET="2026-09-30"

violations=0
unpaired=0
total_drift=0
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
        echo "    canonical: ${cpath} -- $( (( c_head )) && echo present || echo DELETED ) at HEAD"
        echo "    mirror:    ${mpath} -- $( (( m_head )) && echo present || echo DELETED ) at HEAD"
        echo "    Both surfaces existed at the merge base, so this is a DELETION, not an"
        echo "    unpaired document -- a baseline exists for this pair."
        echo "    Remediation: delete BOTH surfaces to retire the document, or restore the one"
        echo "    that was removed. A legal document published on one surface only leaves the"
        echo "    other stating something the record does not."
      } >> "$report"
      violations=$((violations + 1))
    else
      echo "::error::${name} exists on exactly one surface and has no baseline; cannot decide" >&2
      unpaired=$((unpaired + 1))
    fi
    continue
  fi

  # A document with fewer than two `---` lines normalises to ZERO BYTES: the frontmatter
  # stripper emits nothing until it has seen the closing delimiter. Two such surfaces produce
  # an empty drift sequence and a trivially-satisfied subsequence, so a pair sharing NO content
  # reported "checked, drift within the baseline". Measured. There is no backstop here --
  # check-tc-document-sha.sh has its raw-file SHA pin, this gate has nothing.
  c_norm_n=$(normalize_canonical "$cpath" | collapse | grep -cE '.' || true)
  m_norm_n=$(normalize_plugin "$mpath" | collapse | grep -cE '.' || true)
  if (( c_norm_n == 0 || m_norm_n == 0 )); then
    echo "::error::${name}: a surface normalises to zero lines (canonical=${c_norm_n} mirror=${m_norm_n}); frontmatter is likely malformed. Refusing to compare." >&2
    unpaired=$((unpaired + 1))
    continue
  fi

  head_seq="$WORK/${name}.head"
  drift_seq "$cpath" "$mpath" > "$head_seq"
  head_n=$(grep -cE '.' < "$head_seq" || true)
  total_drift=$((total_drift + head_n))
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
    # The verdict is DERIVED from the evidence, not guessed from the counts. `head_n < base_n`
    # labelled an equal-count content substitution as "reordered" while the headline said
    # "grew (3 -> 3)" -- two contradictory diagnoses of a change that neither grew nor moved.
    # The discriminator is already computed: lines present at HEAD and absent from the
    # baseline mean CONTENT CHANGED; none means the multiset is identical and only the
    # SEQUENCE differs.
    novel="$WORK/${name}.novel"
    { comm -23 <(sort "$head_seq") <(sort "$base_seq") || true; } > "$novel"
    novel_n=$(grep -cE '.' < "$novel" || true)

    if (( novel_n == 0 )); then
      verdict="REORDERED: the same drift lines now appear in a different sequence"
    elif (( head_n > base_n )); then
      verdict="GREW: HEAD carries drift the baseline did not"
    else
      verdict="CONTENT CHANGED: a line that was already drifting was edited in place"
    fi

    {
      echo "  ${name}: ${verdict}"
      echo "    baseline ${base_n} drift line(s) -> HEAD ${head_n}; ${novel_n} not in the baseline"
      echo "    canonical: ${cpath}"
      echo "    mirror:    ${mpath}"
      if (( novel_n > 0 )); then
        echo "    Drift lines present at HEAD but not in the baseline ('<' canonical, '>' mirror):"
        # Blank drift lines are dropped from the DISPLAY only: `sort` floats them to the top
        # and `head` then consumed the entire budget, so a 30-clause regression rendered as
        # twelve empty rows and the remediation named nothing to fix. The real corpus carries
        # 31 blank lines in its drift sequences, so this reproduced on live content.
        # `awk NR<=12` rather than `head -12`: head closes the pipe, comm takes SIGPIPE, and
        # under `pipefail` the gate aborted with rc=141 and ZERO output -- detecting the drift
        # and reporting nothing, outside its documented 0/1/2 contract.
        grep -vE '^[<>]$' "$novel" | awk 'NR<=12 { print "      + " $0 }'
        shown=$(grep -cvE '^[<>]$' "$novel" || true)
        (( shown > 12 )) && echo "      ... $((shown - 12)) more; run locally for the full list"
      fi
      case "$verdict" in
        REORDERED*)
          echo "    No other gate sees this -- legal-doc-consistency compares heading sequence,"
          echo "    and the SHA guard compares canonical hashes."
          echo "    Remediation: restore the original ordering on whichever surface moved, or"
          echo "    apply the same reordering to both."
          ;;
        "CONTENT CHANGED"*)
          echo "    Remediation: this line exists on only ONE surface (it is pre-existing drift),"
          echo "    so 'apply it to both in the same position' may be impossible. Either port the"
          echo "    enclosing passage to the other surface -- which REDUCES drift and always"
          echo "    passes -- or leave the line unedited until #7465 resyncs the pair."
          ;;
        *)
          echo "    Remediation: apply the change to BOTH surfaces in the same commit, in the"
          echo "    same position. Reducing drift always passes; only growth, reordering and"
          echo "    in-place edits of already-drifting lines fail."
          ;;
      esac
    } >> "$report"
    violations=$((violations + 1))
  fi
done <<< "$names"

# A real VIOLATION is reported before the "nothing was evaluated" guard. The guard used to
# run first, so on a single-pair corpus a correct one-sided-delete finding was computed,
# written to the report, and then discarded in favour of "no comparable document pairs were
# evaluated" -- a diagnosis regression that threw away the specific answer.
if (( violations > 0 )); then
  # Break-glass. This gate derives its baseline from git history rather than from a committed
  # file, which is what makes a REVERT of a merged drift-reducing PR fail: reverting restores
  # the larger drift while the merge base has already moved. Measured, exit 1, with no way
  # past a required context except an admin override. For a gate over PUBLISHED LEGAL TEXT,
  # rolling the publication back is the primary incident response, so blocking it is the wrong
  # failure direction. The escape announces itself loudly and records the reason.
  if [[ -n "${SOLEUR_LEGAL_DRIFT_ACCEPT:-}" ]]; then
    echo "::warning::legal mirror drift: ${violations} document(s) drifted beyond the baseline -- ACCEPTED via SOLEUR_LEGAL_DRIFT_ACCEPT" >&2
    echo "::warning::reason: ${SOLEUR_LEGAL_DRIFT_ACCEPT}" >&2
    cat "$report" >&2
    echo "  base=${RESOLVED_REF} merge-base=${MERGE_BASE:0:7}" >&2
    echo "  This run did NOT gate. The accepted drift becomes the new baseline for every" >&2
    echo "  later PR, so record why in the PR body and on #7465." >&2
    exit 0
  fi
  echo "::error::legal mirror drift: ${violations} document(s) drifted beyond the baseline" >&2
  cat "$report" >&2
  echo "" >&2
  echo "  base=${RESOLVED_REF} merge-base=${MERGE_BASE:0:7}" >&2
  echo "  reproduce: bash scripts/lint-legal-mirror-drift-baseline.sh --base ${RESOLVED_REF}" >&2
  echo "  If this is a revert of a merged drift-reducing PR, or an urgent legal publication," >&2
  echo "  set SOLEUR_LEGAL_DRIFT_ACCEPT='<reason>' -- the reason is recorded in the run log." >&2
  exit 1
fi

if (( unpaired > 0 )); then
  echo "::error::${unpaired} legal document(s) could not be compared; refusing to report clean" >&2
  exit 2
fi

if (( checked == 0 )); then
  echo "::error::no comparable document pairs were evaluated; refusing to report clean" >&2
  exit 2
fi

echo "legal mirror drift: ${checked} pair(s) checked, drift is within the baseline."
echo "  base=${RESOLVED_REF} merge-base=${MERGE_BASE:0:7}"
echo "  This is a RATCHET, not a clean bill of health. It asserts drift did not GROW, REORDER"
echo "  or change CONTENT relative to the merge base. It does NOT assert the two surfaces"
echo "  agree: the published mirror under-discloses relative to the record. Re-measured at #7349"
echo "  merge sign-off -- a named sub-processor (Flagsmith), the Art. 14 information posture and"
echo "  DPIA-status statement, and the Art. 15/20 request-channel split in gdpr-policy; the"
echo "  LinkedIn Page data category with its two transfer rows and the community-digest carve-out"
echo "  in privacy-policy. Tracked on #7465, remediation target ${REMEDIATION_TARGET}."
echo "  NOT CHECKED: a lockstep DELETION. Removing the same disclosure from both surfaces"
echo "  leaves drift unchanged and passes here; only the SHA pin in legal-doc-shas.ts and"
echo "  human review catch that."

# The freeze must not outlive its remediation date silently. Nothing compared this date to
# the clock, so on 2026-10-01 the gate would still exit 0 while printing a past date as a
# live target -- a divergence that has become permanent in practice while presenting as
# managed, which inverts the Art. 83(2)(c) "mitigating action taken" argument the freeze
# rests on. `date -d` is offline; --today exists so the suite can pin the comparison.
_today="${SOLEUR_LEGAL_DRIFT_TODAY:-$(date -u +%Y-%m-%d)}"
if [[ "$_today" > "$REMEDIATION_TARGET" ]] && (( total_drift > 0 )); then
  echo "::warning::the canonical/mirror drift freeze passed its ${REMEDIATION_TARGET} remediation target on ${_today} and ${total_drift} drift line(s) remain. Re-date #7349 or resync the corpus -- an undated permanent freeze is evidence the divergence was institutionalised, not managed." >&2
fi
exit 0
