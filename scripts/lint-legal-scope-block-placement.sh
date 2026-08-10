#!/usr/bin/env bash
# lint-legal-scope-block-placement.sh -- gate 1 of #7387.
#
# Fails when an ADDED scope block in the legal corpus asserts plugin-local scope in a way
# the surrounding text does not support. Added lines only: this is a ratchet, not an audit.
#
# WHAT THIS GATE IS NOT (CLO Amendment 11, binding). It does not adjudicate whether a scope
# statement is legally correct. It enforces mechanical preconditions. Scope correctness is a
# CLO decision and this gate must never be cited as evidence of it.
#
# WHY IT CLASSIFIES ON REFERENT AND NOT ON PROXIMITY TO CLOUD WORDS. The first draft fired
# wherever a plugin-local assertion sat near a cloud marker. Measured against the tree the
# CLO ruled final, that form fired on 8 sites of which 6 were text the CLO had EXPRESSLY
# RULED CORRECT: the ruling's remedy for over-reach was never relocation or deletion, it was
# to narrow the referent in place ("This section" -> "The paragraph above"). The legal test
# is not adjacency. It is whether the scope statement's DECLARED REFERENT is larger than the
# text that is actually plugin-local.
#
#   arm (a)  referent/section agreement -- a SECTION-scoped referent inside a section that
#            carries a cloud marker.
#   arm (b)  attachment matches referent -- a SECTION-scoped referent that is list-indented.
#            In CommonMark an indented paragraph after a list item is a continuation of THAT
#            ITEM, so the qualification attaches to one bullet while claiming the section.
#            The converse is NOT a defect: a limb-scoped rider is legitimately indented.
#   arm (c)  the block discharges its own scope -- via a negative delimiter or a
#            cross-reference to the surface it disclaims, ON THE SAME LINE.
#
# The negative delimiter is deliberately NOT part of the classifier. Making it one creates an
# escape hatch: deleting "must not be read as covering it" would blind the gate while the
# over-broad affirmative stays published, so the gate would reward removing a disclaimer.
#
# LAUNDERING PATHS THIS GATE DOES NOT CLOSE, stated so nobody assumes it does:
#   - Section laundering. The marker list is a heuristic over prose. Rewording a section's
#     text to avoid every marker turns a real defect green with the false block intact.
#   - Relocation into a marker-free but substantively cloud-scoped section.
#   - Phrasing outside the locality vocabulary. Reported, not failed -- see UNCLASSIFIED below.
# None is mechanically preventable. All are why Amendment 11 exists.
#
# Exit codes:  0 clean   1 violation   2 cannot decide (never a vacuous 0)

set -euo pipefail

export LC_ALL=C

# Arm toggles exist so the suite's mutation battery can neuter each arm independently. They
# are not a runtime configuration surface, and they are NOT the only axis the battery
# mutates -- review of #7388 found that a battery which only flips these tests a SIMULATED
# defect and misses every real one.
ARM_A_ENABLED=1
ARM_B_ENABLED=1
ARM_C_ENABLED=1

BASE_REF=""
PRINT_VOCAB=0

usage() {
  cat <<'USAGE'
lint-legal-scope-block-placement.sh -- gate 1 of #7387

  --base <ref>      Diff base. Default: MERGE_GROUP_BASE_SHA, else origin/$GITHUB_BASE_REF,
                    else origin/main.
  --print-vocab     Print every classifier vocabulary (markers and all five regexes) and exit.
  -h, --help        This text.

Exit codes: 0 clean, 1 violation, 2 cannot decide.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    # `$# -lt 2` guarded: a bare trailing `--base` would otherwise make `shift 2` fail, and
    # inside a `while` BODY that is not exempt from `set -e` -- the gate died with rc=1 and
    # no output, i.e. "cannot decide" mislabelled as "violation".
    --base)
      if [[ $# -lt 2 ]]; then echo "::error::--base requires a value" >&2; exit 2; fi
      BASE_REF="$2"; shift 2 ;;
    --print-vocab) PRINT_VOCAB=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "::error::unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------
# Vocabulary. Derived by measuring the live corpus, never recalled: the issue's own examples
# (`**Scope.**`, `**What this covers.**`, "describes plugin-local processing") appear ZERO
# times in either surface, so a memory-derived list would reject the motivating change and
# match nothing real.
# ---------------------------------------------------------------------------------------

# Cloud markers: prose that means "this section governs cloud processing".
# Live counts at derivation (2026-08-10): Web Platform 555, app.soleur.ai 140,
# acts as Controller 2, Cloud Execution 2, server-side monitoring 2.
MARKERS=(
  'Web Platform'
  'app\.soleur\.ai'
  'acts as Controller'
  'Cloud Execution'
  'server-side monitoring'
)
MARKER_RE=$(IFS='|'; printf '%s' "${MARKERS[*]}")

# A locality assertion is a claim about the SCOPE OF THE TEXT, not about the product.
#
# The discriminator is the VERB, and getting this wrong in either direction is expensive.
# Too narrow (the first implementation required the literal token `only` after one of five
# verbs) and six realistic phrasings evade the gate entirely. Too broad (a bare locality
# family) and it matches ordinary descriptive prose: measured over the live corpus, a
# verb-free family matched 18 sentences like "The Plugin operates locally on your machine;
# the Web Platform operates on cloud infrastructure" -- product-behaviour statements, not
# scope statements. Reporting those on every clean run is the wallpaper problem: a constant
# disclaimer nobody reads.
#
# A scope block says what THIS TEXT covers ("applies to", "describes", "is limited to").
# A product statement says what the software DOES ("operates locally", "runs on your
# machine"). Only the former can be over-broad about its own referent, which is the whole
# defect class.
SCOPE_VERB_RE='(applies|refers|pertains|is limited|is confined|describes|covers|governs|concerns)'
LOCALITY_CLAIM_RE='([Pp]lugin (only|alone)|plugin-local|local-only|locally-installed|locally|on-device|(your|the User.s) own (machine|filesystem|device|CLI))'
LOCALITY_RE="${SCOPE_VERB_RE}[^.]{0,60}${LOCALITY_CLAIM_RE}"

# Referents, split by the scope they declare. Case-insensitive on the noun: the live corpus
# uses capitalised `This Section` / `The Section` 11 times, which is house style -- a
# case-sensitive match rejected them at arm 0 so no arm ever ran.
#
# The section referent must be in SUBJECT position -- the noun must be followed by a scope
# verb. A bare `(This|The) [Ss]ection` also matches the CROSS-REFERENCE that a correct block
# uses to discharge itself ("...see the Section 4.3 below"), so a correctly-narrowed
# paragraph-scoped block was red-lined for citing a section. Measured while fixing the
# both-referent laundering path: that widening introduced exactly the false-positive class
# the CLO withdrew the first draft over, which is why the fix is subject position rather than
# simply dropping the paragraph-referent exemption.
SECTION_REF_RE="(This|The|this|the) [Ss]ection[^.]{0,30}${SCOPE_VERB_RE}"
PARA_REF_RE='(The|the) (paragraph|two paragraphs|bullets?|three bullets|clause) above'

# A block discharges its scope by disclaiming the reading or by pointing at the surface it
# disclaims. Both forms are live on main: 3 of the 4 canonical scope blocks carry no negative
# delimiter and discharge via a cross-reference instead, so requiring the delimiter alone
# would red-line correct text.
NEG_DELIM_RE='must not be read as|does not (describe|cover|apply to)|do not (describe|cover|apply to)|do(es)? \*\*not\*\* (describe|cover|apply to)|shall not be (read|construed)'
XREF_RE='[Ss]ee (Section|section|§|the)|[Ff]or the (Soleur )?Web Platform|as set out in (Section|§)|see \[.*\]\('

if [[ "$PRINT_VOCAB" == "1" ]]; then
  printf 'MARKER\t%s\n' "${MARKERS[@]}"
  printf 'LOCALITY\t%s\n' "$LOCALITY_RE"
  printf 'SECTION_REF\t%s\n' "$SECTION_REF_RE"
  printf 'PARA_REF\t%s\n' "$PARA_REF_RE"
  printf 'NEG_DELIM\t%s\n' "$NEG_DELIM_RE"
  printf 'XREF\t%s\n' "$XREF_RE"
  exit 0
fi

# ---------------------------------------------------------------------------------------
# Base resolution -- shared with gate 2 so the two cannot disagree about what "added" means.
# ---------------------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_LIB="$REPO_ROOT/scripts/lib/legal-base-ref.sh"
if [[ ! -f "$BASE_LIB" ]]; then
  echo "::error::shared base resolver missing: $BASE_LIB" >&2
  exit 2
fi
# shellcheck source=lib/legal-base-ref.sh
. "$BASE_LIB"

base_out=""
base_rc=0
base_out=$(legal_resolve_base "$BASE_REF") || base_rc=$?
if (( base_rc != 0 )); then
  exit 2
fi
RESOLVED_REF="${base_out%%$'\t'*}"
MERGE_BASE="${base_out##*$'\t'}"

# ---------------------------------------------------------------------------------------
# Corpus readability floor.
#
# PER-SURFACE, not the conjunction. The original `canon == 0 && mirror == 0` meant that if
# the mirror moved and only some call sites were updated, the floor stayed satisfied while
# the gate scanned ZERO mirror lines and printed "0 violations" -- the only fail-open path in
# the corpus toolchain, since the other two gates fail loudly on that same half-move.
#
# This is a floor on the CORPUS, never on added lines: a PR touching no legal doc
# legitimately has zero added lines and must exit 0.
# ---------------------------------------------------------------------------------------

CANONICAL_DIR="docs/legal"
MIRROR_DIR="plugins/soleur/docs/pages/legal"

shopt -s nullglob
canon_files=("$CANONICAL_DIR"/*.md)
mirror_files=("$MIRROR_DIR"/*.md)
shopt -u nullglob

if (( ${#canon_files[@]} == 0 )); then
  echo "::error::${CANONICAL_DIR}/ contains no .md (cwd: $(pwd)); the corpus is unreadable, refusing to report clean" >&2
  exit 2
fi
if (( ${#mirror_files[@]} == 0 )); then
  echo "::error::${MIRROR_DIR}/ contains no .md (cwd: $(pwd)); the mirror surface would be scanned as empty, refusing to report clean" >&2
  exit 2
fi

# ---------------------------------------------------------------------------------------
# Added-line extraction.
#
# The diff is captured as its OWN command with its status checked. It used to be
# `git diff … | awk … || true`, which discarded git's stderr AND its status, so ANY git
# failure (an unreadable blob, a partial clone, ENOSPC killing the awk) produced an empty
# result that the next branch read as "the PR touched no legal doc" and reported as a clean
# pass. Measured: `chmod 000` on one corpus file made the gate print "no added lines in the
# legal corpus" and exit 0 on a tree that exits 1 when the file is readable. That is exactly
# the vacuous 0 this file's header forbids.
#
# Hunk headers appear in four shapes and all four occur in real legal diffs:
#   @@ -a,b +c,d @@   @@ -a +c @@   @@ -a,0 +c @@   @@ -a,b +c,0 @@
# An absent `,N` means 1; `+c,0` is a pure deletion contributing no added lines. The `+c,d`
# field is taken by POSITION (field 3), not by a greedy strip to the last `+`: `git diff -U0`
# appends funcname context, the corpus has 88 `+`-bearing lines and two of them are already
# git-default funcname anchors, so a greedy strip yielded start=0 (disabling the section scan
# for that hunk) or misattributed the block to an unrelated line.
#
# `+++ ` is only honoured in HEADER position -- immediately after a `--- ` line. A corpus
# line whose own content begins `++ ` is emitted by `-U0` as `+++ …`, and treating that as a
# file header reset the path and silently dropped every remaining added line in the file.
#
# The indent width is measured in awk and emitted as its own field. Reading it back in the
# shell was wrong: `IFS=$'\t' read` strips a LEADING TAB from the content field, so a
# tab-indented block measured as flush-left and arm (b) never ran.
# ---------------------------------------------------------------------------------------

WORK=$(mktemp -d -t legal-scope.XXXXXXXX) || exit 2
trap 'rm -rf "$WORK"' EXIT

RAW="$WORK/diff.raw"
diff_rc=0
git -c core.quotePath=false diff -U0 --no-color --diff-filter=d "$MERGE_BASE" -- \
      "$CANONICAL_DIR" "$MIRROR_DIR" > "$RAW" 2>"$WORK/diff.err" || diff_rc=$?
if (( diff_rc != 0 )); then
  echo "::error::git diff failed (rc=${diff_rc}) while computing added lines; refusing to report clean" >&2
  head -20 "$WORK/diff.err" >&2 || true
  exit 2
fi

ADDED="$WORK/added.tsv"
awk '
  /^--- /{ prev_minus=1; next }
  /^\+\+\+ /{
    if (!prev_minus) { prev_minus=0; next }   # content line starting "++ ", not a header
    prev_minus=0
    p=$0
    sub(/^\+\+\+ /, "", p)
    if (p == "/dev/null") { path=""; remaining=0; next }
    sub(/^b\//, "", p)
    path=p
    remaining=0
    next
  }
  { prev_minus=0 }
  /^@@ /{
    if (path == "") next
    # Field 3 is "+start[,count]" for every documented hunk shape.
    n=split($0, f, " ")
    if (n < 3) next
    plus=f[3]
    sub(/^\+/, "", plus)
    m=split(plus, a, ",")
    start=a[1] + 0
    count=(m > 1) ? a[2] + 0 : 1
    cur=start
    remaining=count
    next
  }
  /^\+/{
    if (path == "" || remaining <= 0) next
    line=substr($0, 2)
    # Indent is measured in COLUMNS, not characters: CommonMark expands a tab to the next
    # 4-column stop, so a single tab is a full list-continuation indent while a single space
    # is not. Counting characters made one tab measure as 1 and fall under the threshold,
    # i.e. arm (b) was off for every tab-indented document.
    ind=0
    tmp=line
    while (match(tmp, /^[ \t]/)) {
      if (substr(tmp, 1, 1) == "\t") { ind += 4 - (ind % 4) } else { ind++ }
      tmp=substr(tmp, 2)
    }
    printf "%s\t%d\t%d\t%s\n", path, cur, ind, line
    cur++
    remaining--
  }
' "$RAW" > "$ADDED"

if [[ ! -s "$ADDED" ]]; then
  echo "legal scope-block placement: no added lines in the legal corpus; nothing to check."
  echo "  base=${RESOLVED_REF} merge-base=${MERGE_BASE:0:7}"
  echo "  NOT CHECKED: pre-existing text (this gate is added-lines-only, by design), and"
  echo "  scope CORRECTNESS, which is a CLO decision and not mechanically decidable here."
  exit 0
fi

# ---------------------------------------------------------------------------------------
# Candidate pre-filter.
#
# One grep pass over the whole added-line set, instead of one grep PROCESS PER ADDED LINE.
# Measured on a full-corpus rewrite: 5,856 added lines spawned 5,886 processes and took
# 38-49s to find the 16 lines a single pass finds in 0.03s. The remediation this gate's
# sibling schedules for 2026-09-30 is a full mirror resync, so the gate was slowest on
# exactly the PR it most wants to inspect.
# ---------------------------------------------------------------------------------------

CANDIDATES="$WORK/candidates.tsv"
grep -E -- "$LOCALITY_RE" "$ADDED" > "$CANDIDATES" || true

# ---------------------------------------------------------------------------------------
# Section resolution.
#
# The enclosing section is the LAST heading at level 2 or 3 at or above the line, so a later
# h2 correctly resets a stale h3 scope. The HEADING LINE ITSELF is scanned for markers -- it
# is the most authoritative statement of a section's scope, and 46 h2/h3 headings in the live
# corpus carry one. The whole section is scanned, not only the part above the block: an
# opening scope disclaimer with the cloud claims below it is the corpus's natural authoring
# order, and scanning only upwards made that shape invisible.
#
# The scope block's OWN line is excluded. Measured: at three of the four canonical
# locality-assertion sites the only marker in the enclosing section sits on the block's own
# line, and in each case it is the cross-reference that makes the block correct ("For the Web
# Platform, see Section 4.3 below"); the fourth site has no marker in its section at all.
# Scanning the own line would red-line three of four blocks the corpus treats as correct.
# ---------------------------------------------------------------------------------------

section_marker_hit() {
  local file="$1" lineno="$2"
  [[ -f "$file" ]] || return 1
  awk -v target="$lineno" -v mk="$MARKER_RE" '
    BEGIN { in_fence=0; sec_start=0; sec_end=0; found_target_sec=0 }
    /^(```|~~~)/ { in_fence = !in_fence; next }
    !in_fence && /^#{2,3} / {
      if (NR <= target) { sec_start=NR }
      else if (!sec_end) { sec_end=NR }
    }
    { lines[NR]=$0; fence[NR]=in_fence }
    END {
      if (!sec_end) sec_end = NR + 1
      for (i = (sec_start ? sec_start : 1); i < sec_end; i++) {
        if (i == target) continue
        if (fence[i]) continue
        if (lines[i] ~ mk) { printf "%d\t%s\n", i, lines[i]; exit 0 }
      }
      exit 1
    }
  ' "$file"
}

# ---------------------------------------------------------------------------------------
# Evaluation.
#
# All applicable arms are evaluated per line and every finding is reported. Arm (a) used to
# `continue`, so applying its printed remedy flipped the line into arm (c) and produced a
# SECOND CI round-trip for a defect the first report could have named.
# ---------------------------------------------------------------------------------------

violations=0
classified=0
unclassified=0
report="$WORK/report.txt"
: > "$report"
unclassified_report="$WORK/unclassified.txt"
: > "$unclassified_report"

while IFS=$'\t' read -r path lineno indent line; do
  [[ -n "$path" ]] || continue

  is_section_ref=0
  is_para_ref=0
  grep -qE -- "$SECTION_REF_RE" <<<"$line" && is_section_ref=1
  grep -qE -- "$PARA_REF_RE" <<<"$line" && is_para_ref=1

  # A locality assertion whose referent is outside the vocabulary is NOT silently dropped.
  # The remediation tells editors to narrow the referent, and the narrowings outside
  # PARA_REF_RE ("The preceding paragraph", "This paragraph") took the line out of
  # classification entirely -- a one-token path from red to a green that removed all
  # coverage. Reporting it converts a silent bypass into a visible one.
  if (( ! is_section_ref && ! is_para_ref )); then
    unclassified=$((unclassified + 1))
    printf '  %s:%s  locality assertion with no recognised referent (NOT CHECKED)\n    %s\n' \
      "$path" "$lineno" "${line:0:160}" >> "$unclassified_report"
    continue
  fi

  classified=$((classified + 1))

  # arm (a) -- referent/section agreement.
  #
  # Fires on a section-scoped referent regardless of any paragraph mention. `! is_para_ref`
  # was an exemption rather than evidence of narrowing, so appending eight words ("The
  # bullets above are unaffected.") disarmed the arm while the over-broad section claim
  # stayed published. The broader referent wins.
  if (( ARM_A_ENABLED && is_section_ref )); then
    if marker_hit=$(section_marker_hit "$path" "$lineno"); then
      m_line="${marker_hit%%$'\t'*}"
      m_text="${marker_hit##*$'\t'}"
      {
        echo "${path}:${lineno}  arm (a): section-scoped referent inside a section that carries a cloud marker"
        echo "    ${line:0:160}"
        echo "    marker at ${path}:${m_line}: ${m_text:0:110}"
        echo "    Remediation:"
        echo "      1. FIRST verify the claim is not genuinely section-wide. If the whole section IS"
        echo "         plugin-local, the SECTION is mis-scoped and that is a CLO question -- do NOT"
        echo "         narrow a true statement, which would weaken the published page."
        echo "      2. Otherwise narrow the referent in place: 'This section' -> 'The paragraph above'."
        echo "         Do NOT move or delete the block. The narrowed block must still discharge (arm c)."
      } >> "$report"
      violations=$((violations + 1))
    fi
  fi

  # arm (b) -- attachment must match referent. Threshold is 2+ columns: a single leading
  # space is not a CommonMark list continuation under any marker.
  if (( ARM_B_ENABLED && is_section_ref && indent >= 2 )); then
    {
      echo "${path}:${lineno}  arm (b): section-scoped referent indented ${indent} columns (list-item continuation)"
      echo "    ${line:0:160}"
      echo "    Remediation:"
      echo "      1. If the qualification is section-wide, move it flush-left (column 0). Indented,"
      echo "         CommonMark makes it a continuation of the preceding list item, so it qualifies"
      echo "         one bullet while claiming the section. NOTE: moving it flush-left inside a"
      echo "         marker-bearing section will then surface arm (a) -- read that remedy too."
      echo "      2. If it really qualifies only that limb, keep the indent and narrow the referent"
      echo "         to 'The paragraph above'."
    } >> "$report"
    violations=$((violations + 1))
  fi

  # arm (c) -- the block must discharge its own scope, on this line.
  if (( ARM_C_ENABLED )); then
    if ! grep -qE -- "$NEG_DELIM_RE" <<<"$line" && ! grep -qE -- "$XREF_RE" <<<"$line"; then
      {
        echo "${path}:${lineno}  arm (c): scope block discharges nothing"
        echo "    ${line:0:160}"
        echo "    Remediation -- add EITHER, ON THIS LINE (a discharge on the following line does"
        echo "    not satisfy this arm; the check is line-local by design):"
        echo "      1. a negative delimiter -- '... and must not be read as covering it', OR"
        echo "      2. a cross-reference to the surface being disclaimed -- 'For the Web Platform,"
        echo "         see Section 4.3 below'. Three of the four scope blocks on main use this form."
        echo "      Run --print-vocab for the full accepted set."
      } >> "$report"
      violations=$((violations + 1))
    fi
  fi
done < "$CANDIDATES"

if (( violations > 0 )); then
  echo "::error::legal scope-block placement: ${violations} violation(s)" >&2
  # One annotation per violation so findings land inline on the PR diff -- a bare count in
  # the checks view is not actionable for a non-technical operator. Parsed with an explicit
  # match rather than `-F:`, because a colon-split puts "6  arm (a)" in field 2 and emits a
  # malformed `line=` that GitHub drops silently.
  awk '
    match($0, /^[^ ][^:]*:[0-9]+  arm \([abc]\)/) {
      head = substr($0, 1, RLENGTH)
      ci = index(head, ":")
      f = substr(head, 1, ci - 1)
      rest = substr(head, ci + 1)
      li = rest + 0
      desc = $0
      sub(/^[^ ][^:]*:[0-9]+  /, "", desc)
      printf "::error file=%s,line=%d::%s\n", f, li, desc
    }' "$report" >&2 || true
  # Bounded: an unbounded report reached 398 KB at 1000 violations.
  head -120 "$report" >&2
  total_lines=$(grep -cE '.' < "$report" || true)
  (( total_lines > 120 )) && echo "    ... $((total_lines - 120)) more report line(s) suppressed; run locally for the full list" >&2
  if (( unclassified > 0 )); then
    echo "" >&2
    echo "  ${unclassified} locality assertion(s) had no recognised referent and were NOT checked:" >&2
    cat "$unclassified_report" >&2
  fi
  echo "" >&2
  echo "  base=${RESOLVED_REF} merge-base=${MERGE_BASE:0:7}" >&2
  echo "  reproduce: bash scripts/lint-legal-scope-block-placement.sh --base ${RESOLVED_REF}" >&2
  echo "  This gate checks REFERENT AGREEMENT and ATTACHMENT only. It does not decide whether" >&2
  echo "  a scope statement is legally correct -- that is the CLO's call (Amendment 11)." >&2
  exit 1
fi

echo "legal scope-block placement: ${classified} scope block(s) classified in added lines, 0 violations."
echo "  base=${RESOLVED_REF} merge-base=${MERGE_BASE:0:7}"
if (( unclassified > 0 )); then
  echo "  ${unclassified} locality assertion(s) had NO recognised referent and were NOT checked:"
  cat "$unclassified_report"
  echo "  If any of those is a scope block, its referent phrasing is outside this gate's"
  echo "  vocabulary -- extend PARA_REF_RE/SECTION_REF_RE rather than leaving it unchecked."
fi
echo "  NOT CHECKED, and not implied by this pass:"
echo "    - whether the scope statement is legally CORRECT (a CLO decision, Amendment 11);"
echo "    - pre-existing text -- this gate is added-lines-only by design;"
echo "    - DELETIONS: removing a cross-reference, or removing a heading so a clean block is"
echo "      re-parented into a marker-bearing section, adds no line and is invisible here;"
echo "    - ADDING a cloud marker to a section that already contains a scope block -- the"
echo "      added line carries no locality assertion, so it is not classified;"
echo "    - section laundering (rewording a section to shed every cloud marker) and"
echo "      relocation into a marker-free but substantively cloud-scoped section."
exit 0
