#!/usr/bin/env bash
# lint-legal-scope-block-placement.sh -- gate 1 of #7387.
#
# Fails when an ADDED scope block in the legal corpus asserts plugin-local scope in a way
# the surrounding text does not support. Added lines only: this is a ratchet, not an audit.
#
# WHAT THIS GATE IS NOT (CLO Amendment 11, binding). It does not adjudicate whether a scope
# statement is legally correct. It enforces three mechanical preconditions. Scope
# correctness is a CLO decision and this gate must never be cited as evidence of it.
#
# WHY IT CLASSIFIES ON REFERENT AND NOT ON PROXIMITY TO CLOUD WORDS. The first draft fired
# wherever a plugin-local assertion sat near a cloud marker. Measured against the tree the
# CLO ruled final, that form fired on 8 sites of which 6 were text the CLO had EXPRESSLY
# RULED CORRECT: the ruling's remedy for over-reach was never relocation or deletion, it was
# to narrow the referent in place ("This section" -> "The paragraph above"). A gate shipped
# to that spec would have driven editors to delete legal text against a standing ruling --
# precisely the harm it exists to prevent. The legal test is not adjacency. It is whether
# the scope statement's DECLARED REFERENT is larger than the text that is actually
# plugin-local.
#
#   arm (a)  referent/section agreement -- a SECTION-scoped referent inside a section that
#            carries a cloud marker. Paragraph-scoped referents are excluded entirely: they
#            are the ruling's prescribed remedy form.
#   arm (b)  attachment matches referent -- a SECTION-scoped referent that is list-indented.
#            In CommonMark an indented paragraph after a list item is a continuation of THAT
#            ITEM, so the qualification attaches to one bullet while claiming the section.
#            The converse is NOT a defect: a limb-scoped rider is legitimately indented, and
#            forcing it flush-left would silently re-scope it to the whole enumeration.
#   arm (c)  the block discharges its own scope -- via a negative delimiter or a
#            cross-reference to the surface it disclaims.
#
# The negative delimiter is deliberately NOT part of the classifier (arm 0). Making it one
# creates an escape hatch: deleting "must not be read as covering it" would blind the gate
# while the over-broad affirmative stays published. The gate would then reward removing a
# disclaimer.
#
# TWO LAUNDERING PATHS THIS GATE DOES NOT CLOSE, stated so nobody assumes it does:
#   - Section laundering. The marker list is a heuristic over prose. Rewording a section
#     opener to avoid every marker turns a real defect green with the false block intact.
#     Treat a marker-list edit in the same diff as a scope block as a review flag.
#   - Relocation into a marker-free but substantively cloud-scoped section.
# Neither is mechanically preventable. Both are why Amendment 11 exists.
#
# Exit codes:  0 clean   1 violation   2 cannot decide (never a vacuous 0)

set -euo pipefail

export LC_ALL=C

# Arm toggles exist so the suite's mutation battery can neuter each arm independently and
# prove the fixtures detect its absence. They are not a runtime configuration surface.
ARM_A_ENABLED=1
ARM_B_ENABLED=1
ARM_C_ENABLED=1

BASE_REF="origin/main"
PRINT_MARKERS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --print-markers) PRINT_MARKERS=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------
# Vocabulary. Every pattern below was derived by measuring the live corpus on 2026-08-10,
# never recalled: the issue's own examples (`**Scope.**`, `**What this covers.**`,
# "describes plugin-local processing") appear ZERO times in either surface, so a
# memory-derived list would reject the motivating change and match nothing real.
# ---------------------------------------------------------------------------------------

# Cloud markers: prose that means "this section governs cloud processing".
# Live counts at derivation: Web Platform 555, app.soleur.ai 140, acts as Controller 2,
# Cloud Execution 2, server-side monitoring 2. The suite asserts each still matches >= 1 as
# a FLOOR -- an equality would red the moment the corpus legitimately grows.
MARKERS=(
  'Web Platform'
  'app\.soleur\.ai'
  'acts as Controller'
  'Cloud Execution'
  'server-side monitoring'
)

if [[ "$PRINT_MARKERS" == "1" ]]; then
  printf '%s\n' "${MARKERS[@]}"
  exit 0
fi

MARKER_RE=$(IFS='|'; printf '%s' "${MARKERS[*]}")

# A locality assertion claims some span of text covers only the local plugin.
LOCALITY_RE='(applies to|describes|covers|governs|is limited to)[^.]{0,40}(the )?(locally-installed )?[Pp]lugin only|plugin-local processing'

# Referents, split by the scope they declare. Arm (a) and arm (b) act on SECTION referents
# only; paragraph and limb referents are the correct narrow forms.
SECTION_REF_RE='(This|The) section'
PARA_REF_RE='(The paragraph above|The two paragraphs above|The bullets? above|The (three|four|five) bullets above)'

# A block discharges its scope by disclaiming the reading (negative delimiter) or by
# pointing at the surface it is disclaiming (cross-reference).
NEG_DELIM_RE='must not be read as|do(es)? \*\*not\*\* (describe|cover)|shall not be (read|construed)'
XREF_RE='[Ss]ee (Section|§|the) |For the (Soleur )?Web Platform, see|see \[.*\]\('

# ---------------------------------------------------------------------------------------
# Base resolution. Fail CLOSED: an unresolvable base means "cannot decide", and a blocking
# gate must never report clean because it could not compute the thing it gates on.
# ---------------------------------------------------------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "::error::not inside a git work tree; cannot compute added lines" >&2
  exit 2
fi

# Best-effort fetch so a shallow CI checkout can still resolve the base. A failure here is
# not fatal on its own -- the rev-parse below is the real gate.
if [[ "$BASE_REF" == origin/* ]]; then
  git fetch --no-tags --quiet origin "${BASE_REF#origin/}" 2>/dev/null || true
fi

if ! BASE_SHA=$(git rev-parse --verify --quiet "${BASE_REF}^{commit}"); then
  echo "::error::base ref '${BASE_REF}' does not resolve; refusing to report clean" >&2
  exit 2
fi

if ! MERGE_BASE=$(git merge-base HEAD "$BASE_SHA" 2>/dev/null) || [[ -z "$MERGE_BASE" ]]; then
  echo "::error::no merge base between HEAD and '${BASE_REF}'; refusing to report clean" >&2
  exit 2
fi

# ---------------------------------------------------------------------------------------
# Corpus readability floor. A glob that resolves to nothing would make every run clean.
# This is a floor on the CORPUS, never on added lines -- a PR that touches no legal doc
# legitimately has zero added lines and must exit 0.
# ---------------------------------------------------------------------------------------

CANONICAL_DIR="docs/legal"
MIRROR_DIR="plugins/soleur/docs/pages/legal"

shopt -s nullglob
canon_files=("$CANONICAL_DIR"/*.md)
mirror_files=("$MIRROR_DIR"/*.md)
shopt -u nullglob

if (( ${#canon_files[@]} == 0 && ${#mirror_files[@]} == 0 )); then
  echo "::error::neither ${CANONICAL_DIR}/ nor ${MIRROR_DIR}/ contains any .md; the corpus is unreadable from $(pwd)" >&2
  exit 2
fi

# ---------------------------------------------------------------------------------------
# Added-line extraction.
#
# `-U0` so hunks carry no context lines to misread as additions. Path is keyed off `+++ b/`
# rather than `--- a/` so a rename reports its NEW path; `+++ /dev/null` (a deletion) is
# skipped. `--diff-filter=d` drops deleted files outright. core.quotePath=false keeps
# non-ASCII paths literal instead of octal-escaped.
#
# Hunk headers appear in four shapes and all four occur in real legal diffs:
#   @@ -a,b +c,d @@   @@ -a +c @@   @@ -a,0 +c @@   @@ -a,b +c,0 @@
# An absent `,N` means 1; `+c,0` is a pure deletion and contributes no added lines. A parser
# that assumes `,N` is always present silently drops single-line insertions -- and a gate
# that drops the added line reports clean, which is the failure mode that matters.
# ---------------------------------------------------------------------------------------

ADDED=$(mktemp -t legal-scope-added.XXXXXXXX) || exit 2
trap 'rm -f "$ADDED"' EXIT

git -c core.quotePath=false diff -U0 --no-color --diff-filter=d "$MERGE_BASE" -- \
      "$CANONICAL_DIR" "$MIRROR_DIR" 2>/dev/null \
  | awk '
      /^\+\+\+ /{
        p=$0
        sub(/^\+\+\+ /, "", p)
        if (p == "/dev/null") { path=""; next }
        sub(/^b\//, "", p)
        path=p
        next
      }
      /^@@ /{
        if (path == "") next
        # Extract the +start[,count] field.
        plus=$0
        sub(/^.*\+/, "", plus)
        sub(/ .*$/, "", plus)
        n=split(plus, a, ",")
        start=a[1] + 0
        count=(n > 1) ? a[2] + 0 : 1
        cur=start
        remaining=count
        next
      }
      /^\+/{
        if (path == "" || remaining <= 0) next
        line=substr($0, 2)
        printf "%s\t%d\t%s\n", path, cur, line
        cur++
        remaining--
      }
    ' > "$ADDED" || true

if [[ ! -s "$ADDED" ]]; then
  echo "legal scope-block placement: no added lines in the legal corpus; nothing to check."
  echo "  NOT CHECKED: pre-existing text (this gate is added-lines-only, by design), and"
  echo "  scope CORRECTNESS, which is a CLO decision and not mechanically decidable here."
  exit 0
fi

# ---------------------------------------------------------------------------------------
# Section resolution.
#
# The enclosing section is the LAST heading at level 2 or 3 at or above the line --
# max(last_h2, last_h3) by position, so a later h2 correctly resets a stale h3 scope. No
# `\d+\.\d+` numbering is assumed; the corpus mixes numbered and unnumbered headings.
#
# The scope block's OWN line is EXCLUDED from the marker scan. This is load-bearing and was
# measured, not assumed: at all four canonical locality-assertion sites on main the ONLY
# marker in the enclosing section sits on the block's own line, and in every case it is the
# cross-reference the block needs in order to be correct ("For the Web Platform, see Section
# 4.3 below"). Scanning it would red three of four blocks the corpus already treats as
# correct -- the same false-positive class that got this gate's first draft withdrawn.
# ---------------------------------------------------------------------------------------

section_marker_hit() {
  local file="$1" lineno="$2"
  [[ -f "$file" ]] || return 1
  awk -v target="$lineno" -v mk="$MARKER_RE" '
    NR == target { next }                      # never scan the block-s own line
    /^#{2,3} /{
      if (NR > target) exit
      hit = 0                                  # a new h2/h3 resets the section
      next
    }
    NR > target { exit }
    $0 ~ mk { hit = 1 }
    END { exit (hit ? 0 : 1) }
  ' "$file"
}

# ---------------------------------------------------------------------------------------
# Evaluation.
# ---------------------------------------------------------------------------------------

violations=0
report=$(mktemp -t legal-scope-report.XXXXXXXX) || exit 2
trap 'rm -f "$ADDED" "$report"' EXIT

classified=0
while IFS=$'\t' read -r path lineno line; do
  [[ -n "$path" ]] || continue

  # arm 0 -- classification. A scope block carries a locality assertion AND a referent.
  # The negative delimiter is deliberately absent from this test.
  grep -qE -- "$LOCALITY_RE" <<<"$line" || continue

  is_section_ref=0
  is_para_ref=0
  grep -qE -- "$SECTION_REF_RE" <<<"$line" && is_section_ref=1
  grep -qE -- "$PARA_REF_RE" <<<"$line" && is_para_ref=1

  (( is_section_ref || is_para_ref )) || continue
  classified=$((classified + 1))

  indented=0
  [[ "$line" =~ ^[[:space:]]+ ]] && indented=1

  # arm (a) -- referent/section agreement.
  if (( ARM_A_ENABLED && is_section_ref && ! is_para_ref )); then
    if section_marker_hit "$path" "$lineno"; then
      {
        echo "${path}:${lineno}  arm (a): section-scoped referent inside a section that carries a cloud marker"
        echo "    ${line:0:160}"
        echo "    Remediation:"
        echo "      1. Narrow the referent in place -- 'This section' -> 'The paragraph above'."
        echo "         This is the CLO's prescribed remedy. Do NOT move or delete the block."
        echo "      2. If the claim really is section-wide, the SECTION is mis-scoped; that is a"
        echo "         CLO question, not an editing one."
      } >> "$report"
      violations=$((violations + 1))
      continue
    fi
  fi

  # arm (b) -- attachment must match referent.
  if (( ARM_B_ENABLED && is_section_ref && indented )); then
    {
      echo "${path}:${lineno}  arm (b): section-scoped referent attached to a single list item"
      echo "    ${line:0:160}"
      echo "    Remediation:"
      echo "      1. If the qualification is section-wide, move it flush-left (column 0). Indented,"
      echo "         CommonMark makes it a continuation of the preceding list item, so it qualifies"
      echo "         one bullet while claiming the section."
      echo "      2. If it really qualifies only that limb, keep the indent and narrow the referent"
      echo "         to 'The paragraph above'."
    } >> "$report"
    violations=$((violations + 1))
    continue
  fi

  # arm (c) -- the block must discharge its own scope.
  if (( ARM_C_ENABLED )); then
    if ! grep -qE -- "$NEG_DELIM_RE" <<<"$line" && ! grep -qE -- "$XREF_RE" <<<"$line"; then
      {
        echo "${path}:${lineno}  arm (c): scope block discharges nothing"
        echo "    ${line:0:160}"
        echo "    Remediation: add EITHER"
        echo "      1. a negative delimiter -- '... and must not be read as covering it', OR"
        echo "      2. a cross-reference to the surface being disclaimed -- 'For the Web Platform,"
        echo "         see Section 4.3 below'. Three of the four scope blocks on main use this form."
      } >> "$report"
      violations=$((violations + 1))
      continue
    fi
  fi
done < "$ADDED"

if (( violations > 0 )); then
  echo "::error::legal scope-block placement: ${violations} violation(s)" >&2
  cat "$report" >&2
  echo "" >&2
  echo "  This gate checks PLACEMENT and REFERENT AGREEMENT only. It does not decide whether" >&2
  echo "  a scope statement is legally correct -- that is the CLO's call (Amendment 11)." >&2
  exit 1
fi

echo "legal scope-block placement: ${classified} scope block(s) in added lines, 0 violations."
echo "  NOT CHECKED, and not implied by this pass:"
echo "    - whether the scope statement is legally CORRECT (a CLO decision, Amendment 11);"
echo "    - pre-existing text -- this gate is added-lines-only by design;"
echo "    - section laundering (rewording a section opener to shed every cloud marker) and"
echo "      relocation into a marker-free but substantively cloud-scoped section. Neither is"
echo "      mechanically preventable; a marker-list edit in the same diff as a scope block"
echo "      should be treated as a review flag."
exit 0
