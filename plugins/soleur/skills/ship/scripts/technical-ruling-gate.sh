#!/usr/bin/env bash
# The /ship Phase 5.5 Technical-Ruling Gate (hard rule hr-technical-fork-is-not-an-operator-question).
#
# Property: no PR reaches ready with a decision-challenges.md or PR-body line that asks the operator a
# TECHNICAL question. Every row of the artifact's `| Item | Class | Ruling |` tables has a valid class;
# every `technical` row carries a `Ruled by CTO|CLO agent, <date>:` cell; no `pending - assumed`
# placeholder survives; and the "Owner decision needed" / "Owner ruling needed" label appears only with
# `(operator: <category>)`. The gate checks FORM, never truth: a model that mislabels a technical
# question as `operator (scope)` still passes (a stated residual, technical-ruling-delegation.md
# section 6); the check on that is review and the operator-visible rendering of operator rows.
#
# Usage:
#   technical-ruling-gate.sh <path>             check one decision-challenges.md
#   technical-ruling-gate.sh --branch           check this branch's artifact under
#                                               knowledge-base/project/specs/<branch>/, or under
#                                               specs/archive/<date>-<slug>/ when archived early;
#                                               an absent artifact is `[PASS] no decision-challenges artifact`
#   technical-ruling-gate.sh --pr-body <file>   check a PR body for an unscoped owner-decision label
#                                               or a surviving `pending - assumed` placeholder
#
# Exit codes:
#   0  every examined row passes (`[PASS]` on stdout). An artifact with NO table is `[WARN]` + exit 0
#      (legacy artifacts and in-flight branches are not blocked); the label and `pending` lints still run.
#   1  at least one failure (`[FAIL] <path>:<line>: <reason> - <remedy>` on stderr, one per finding;
#      <line> is always a line of the checked file)
#   2  could not measure: usage error, an unreadable or EMPTY artifact or PR body (whitespace only counts as
#      empty), a table header with 0 data rows, a header that looks like the Decision Classes header (a
#      separator line follows it) but is not exactly `| Item | Class | Ruling |`, a row whose Class is
#      `technical` that sits OUTSIDE any recognised table (a row after a blank line, a header-less table),
#      an unclosed code fence in the artifact or the PR body (everything after it would be hidden), or an
#      ambiguous archive match. Never a silent pass on something that exists but was not examined.
#
# Table rules (GFM): a table ends at the first line that does not start with `|` (a blank line included);
# a row appended after a blank line is outside the table (a `technical` one is exit 2, never skipped). A
# later writer adds its own header+separator. Inline `code spans` are ignored by the label and pending
# lints (a PR that documents this machinery may quote the strings). A UTF-8 BOM is tolerated. Tables without
# a leading pipe, inside a blockquote or inside a list item are not recognised (residual: the stray-row
# check above catches a `technical` row there).
#
# Reasons (the suite asserts each): bad-class, bad-category, unruled-technical, bad-ruling-shape,
# owner-label-unscoped.
#
# Test seams: TRG_EXEC_LOG (append one line per examined row), TRG_SPECS_ROOT and TRG_BRANCH (the
# `--branch` lookup, so a suite needs no git repository); any of them being set is announced on stderr.
# Lines carrying `# mut:<name>` are the mutation points the suite edits to prove each check can fail.
#
# `set -uo pipefail`, deliberately NOT `-e`: the scanners are pipelines whose `grep` exits 1 on no match.
# Portable to bash 3.2 and to mawk (no `${var,,}`, no `sed -i`, no awk `{m,n}` intervals).

set -uo pipefail
export LC_ALL=C
shopt -s nocasematch

CATEGORIES="money scope priority schedule irreversible production-mutating legal-risk brand"
CATS_RE="${CATEGORIES// /|}"
LABEL_RE='owner[ \t-]+(decision|ruling)s?[ \t]+((is|are)[ \t]+)?(needed|required)|decision[ \t]+needed[ \t]+from[ \t]+the[ \t]+owner|needs?[ \t]+(the[ \t]+)?owner[ \t]+(decision|ruling)'
RULING_RE='^Ruled by (CTO|CLO) agent, [0-9]{4}-[0-9]{2}-[0-9]{2}: .+'
PENDING_RE='pending[ \t]*[^a-z0-9 \t]+[ \t]*assumed'
CTO_REMEDY='spawn soleur:engineering:cto now (at most two attempts, see technical-ruling-delegation.md), write the Ruled by cell, re-run; after two failed attempts leave the PR draft and file one domain/engineering issue, never an operator question'

work_dir=""
UNCLOSED_SEEN=0
cleanup() { [[ -n "$work_dir" ]] && rm -rf "${work_dir:?}"; return 0; }
trap cleanup EXIT

cat_ok() { case " $CATEGORIES " in *" $1 "*) return 0 ;; esac; return 1; } # mut:cat
is_unruled() { [[ -z "$1" ]]; } # mut:unruled
shape_ok() { [[ "$1" =~ $RULING_RE ]]; } # mut:shape

die2() { printf '[ERROR] %s\n' "$*" >&2; cleanup; exit 2; }

# unfenced_match <file> <regex>: `<line>\t<text>` for every unfenced line whose lowercase form matches, with
# inline `code spans` removed first. A fence closes only on the same character, at least as long, with no info
# string (CommonMark); a backtick fence whose info string contains a backtick is inline code, not a fence.
# `@UNCLOSED` is printed when a fence is still open at end of file.
unfenced_match() {
  awk -v re="$2" '
    function fence_toggle(   tok, c, n) {
      tok = $0; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    { sub(/\r$/, ""); if (NR == 1) sub(/^\357\273\277/, "") }
    /^ ? ? ?(```+|~~~+)/ { fence_toggle(); next } # mut:fence
    f { next }
    { line = $0; gsub(/`[^`]*`/, "", line); if (tolower(line) ~ re) printf "%d\t%s\n", NR, $0 }
    END { if (f) print "@UNCLOSED" }
  ' "$1"
}

# table_rows <file>: per unfenced `| Item | Class | Ruling |` header `@TABLE`, then `<line>\t<row>` per data
# row; `@EMPTY` for a table with no data row, `@BADHEADER` for a header-like row followed by a separator
# that is not exactly ours, `@STRAY` for a `technical` row outside any recognised table, `@UNCLOSED` when a
# code fence is still open at end of file.
table_rows() {
  awk '
    function fence_toggle(   tok, c, n) {
      tok = $0; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    function end_table() { if ((state == 3 && rows_in == 0) || state == 2) print "@EMPTY"; state = 0 }
    { sub(/\r$/, ""); if (NR == 1) sub(/^\357\273\277/, "") }
    /^ ? ? ?(```+|~~~+)/ { fence_toggle(); next } # mut:fence-table
    f { next }
    { if (hdr_pending) { if ($0 ~ /^ ? ? ?\|[ :|-]+$/) print "@BADHEADER"; hdr_pending = 0 } }
    { if ((state != 3 || $0 !~ /^ ? ? ?\|/) && tolower($0) ~ /\|[ \t]*technical[ \t]*\|/) print "@STRAY" }
    /^ ? ? ?\|/ {
      line = $0; sub(/^ +/, "", line); sub(/[ \t]+$/, "", line); low = tolower(line)
      if (line ~ /^\|[ \t]*Item[ \t]*\|[ \t]*Class[ \t]*\|[ \t]*Ruling[ \t]*\|$/) { end_table(); print "@TABLE"; state = 2; rows_in = 0; next }
      if (low ~ /item/ && low ~ /class/ && low ~ /ruling/ && state != 3) { hdr_pending = 1; next }
      if (state == 2 && line ~ /^\|[ :|-]+$/) { state = 3; next }
      if (state == 3) { printf "%d\t%s\n", NR, line; rows_in++; next }
      end_table(); next
    }
    { end_table() }
    END { end_table(); if (f) print "@UNCLOSED" }
  ' "$1"
}

check_labels() { # <file> <display-path>; prints [FAIL] lines, returns the count (capped: a status wraps at 256)
  local file="$1" shown="$2" n=0 ln text
  while IFS=$'\t' read -r ln text; do
    [[ -n "$ln" ]] || continue
    if [[ "$ln" == "@UNCLOSED" ]]; then UNCLOSED_SEEN=1; continue; fi
    if [[ ! "$text" =~ \(operator:\ ($CATS_RE)\) ]]; then
      printf '[FAIL] %s:%s: owner-label-unscoped - the owner-decision label may only carry an operator-class item; append (operator: <category>) with a category from the closed list (%s), or route the question to the CTO (technical-ruling-delegation.md)\n' "$shown" "$ln" "$CATEGORIES" >&2
      n=$((n + 1))
    fi
  done < <(unfenced_match "$file" "$LABEL_RE")
  (( n > 255 )) && n=255
  return "$n"
}

check_pending() { # <file> <display-path>; an unresolved placeholder anywhere in the file, returns the count (capped)
  local file="$1" shown="$2" n=0 ln text
  while IFS=$'\t' read -r ln text; do
    [[ -n "$ln" ]] || continue
    if [[ "$ln" == "@UNCLOSED" ]]; then UNCLOSED_SEEN=1; continue; fi
    printf '[FAIL] %s:%s: unruled-technical - a "pending - assumed" placeholder survives: %s\n' "$shown" "$ln" "$CTO_REMEDY" >&2
    n=$((n + 1))
  done < <(unfenced_match "$file" "$PENDING_RE") # mut:pending
  (( n > 255 )) && n=255
  return "$n"
}

check_artifact() { # <file> <display-path>
  local file="$1" shown="$2" idx=0 fails=0 tables=0 ln row inner pipes c2 c3
  [[ -e "$file" ]] || die2 "$shown: no such file"
  [[ -f "$file" && -r "$file" ]] || die2 "$shown: not a readable regular file"
  grep -q '[^[:space:]]' "$file" || die2 "$shown: the artifact is EMPTY; nothing was examined"
  work_dir="$(mktemp -d -t trg.XXXXXXXX)" || die2 "mktemp failed"
  table_rows "$file" > "$work_dir/raw"
  grep -qxF '@UNCLOSED' "$work_dir/raw" && die2 "$shown: a code fence is never closed, so the rest of the file was not examined (close it)"
  grep -qxF '@BADHEADER' "$work_dir/raw" && die2 "$shown: a table header names Item, Class and Ruling but is not exactly '| Item | Class | Ruling |' (fix the header; the rows were not examined)"
  grep -qxF '@STRAY' "$work_dir/raw" && die2 "$shown: a row with Class technical sits outside any '| Item | Class | Ruling |' table (a row after a blank line, or a table without the header); put it in the table or add the header and separator"
  grep -qxF '@EMPTY' "$work_dir/raw" && die2 "$shown: Decision Classes table has 0 rows examined (a header without data rows, or without its separator line)"
  tables="$(grep -cxF '@TABLE' "$work_dir/raw" || true)"
  grep -v '^@' "$work_dir/raw" > "$work_dir/rows" || true
  while IFS=$'\t' read -r ln row; do
    idx=$((idx + 1)) # mut:count
    [[ -n "${TRG_EXEC_LOG:-}" ]] && echo "row $shown:$idx" >> "${TRG_EXEC_LOG:?}"
    inner="${row#|}"; inner="${inner%|}"
    inner="${inner//\\|/$'\001'}"
    pipes="${inner//[^|]/}"
    if [[ ${#pipes} -ne 2 ]]; then
      printf '[FAIL] %s:%s: bad-class - the row must have exactly three cells: Item | Class | Ruling (write a literal pipe as \\|)\n' "$shown" "$ln" >&2
      fails=$((fails + 1)); continue
    fi
    IFS='|' read -r _ c2 c3 _ <<<"$inner"
    c2="${c2#"${c2%%[![:space:]]*}"}"; c2="${c2%"${c2##*[![:space:]]}"}"
    c3="${c3#"${c3%%[![:space:]]*}"}"; c3="${c3%"${c3##*[![:space:]]}"}"
    c2="${c2//$'\001'/|}"; c3="${c3//$'\001'/|}"
    if [[ "$c2" == technical ]]; then
      if [[ "$c3" == "pending - assumed"* ]]; then
        : # reported once, with its line, by the file-wide pending lint below
      elif is_unruled "$c3"; then
        printf '[FAIL] %s:%s: unruled-technical - the row is technical with no ruling: %s\n' "$shown" "$ln" "$CTO_REMEDY" >&2
        fails=$((fails + 1))
      elif ! shape_ok "$c3"; then
        printf '[FAIL] %s:%s: bad-ruling-shape - a technical ruling must start: Ruled by CTO agent, <date>: <decision> - <rationale> (anything else, a bare "pending" included, is not a ruling)\n' "$shown" "$ln" >&2
        fails=$((fails + 1))
      fi
    elif [[ "$c2" == taste ]]; then
      : # user-legible Taste: auto-decided with a recommendation, rendered under Model Dissents, no ruling cell
    elif [[ "$c2" =~ ^operator\ \(([a-z-]+)\)$ ]]; then
      if ! cat_ok "${BASH_REMATCH[1]}"; then
        printf '[FAIL] %s:%s: bad-category - category "%s" is not in the closed list (%s)\n' "$shown" "$ln" "${BASH_REMATCH[1]}" "$CATEGORIES" >&2
        fails=$((fails + 1))
      elif [[ -z "$c3" ]]; then
        printf '[FAIL] %s:%s: bad-ruling-shape - an operator row must name the ACTION being authorised in its Ruling cell\n' "$shown" "$ln" >&2
        fails=$((fails + 1))
      fi
    elif [[ "$c2" == operator ]]; then
      printf '[FAIL] %s:%s: bad-category - a bare "operator" is invalid; write operator (<category>) with a category from the closed list (%s)\n' "$shown" "$ln" "$CATEGORIES" >&2
      fails=$((fails + 1))
    else
      printf '[FAIL] %s:%s: bad-class - Class must be "technical", "taste" or "operator (<category>)", got "%s"\n' "$shown" "$ln" "$c2" >&2
      fails=$((fails + 1))
    fi
  done < "$work_dir/rows"
  check_pending "$file" "$shown"; fails=$((fails + $?))
  check_labels "$file" "$shown"; fails=$((fails + $?))
  if (( fails > 0 )); then return 1; fi
  if (( tables == 0 )); then
    printf '[WARN] %s: no "| Item | Class | Ruling |" table outside a fenced block; label and pending lints ran, rows were not examined (add the table: technical-ruling-delegation.md section 6)\n' "$shown"
    return 0
  fi
  printf '[PASS] %s: %s rows examined\n' "$shown" "$idx"
  return 0
}

if [[ -n "${TRG_SPECS_ROOT:-}${TRG_BRANCH:-}${TRG_EXEC_LOG:-}" ]]; then
  printf '[NOTE] test seam active (TRG_SPECS_ROOT=%s TRG_BRANCH=%s): this is not the live repository lookup\n' "${TRG_SPECS_ROOT:-}" "${TRG_BRANCH:-}" >&2
fi

mode="${1:-}"
case "$mode" in
  --pr-body)
    f="${2:-}"; [[ -n "$f" ]] || die2 "usage: --pr-body <file>"
    [[ -f "$f" && -r "$f" ]] || die2 "$f: not a readable regular file"
    if ! { [[ -s "$f" ]] && grep -q '[^[:space:]]' "$f"; }; then
      die2 "$f: the PR body is EMPTY (the fetch that wrote it most likely failed); nothing was examined"
    fi
    fails=0
    check_pending "$f" "$f"; fails=$((fails + $?))
    check_labels "$f" "$f"; fails=$((fails + $?))
    (( UNCLOSED_SEEN )) && die2 "$f: a code fence in the PR body is never closed, so the rest of it was not examined (close it)"
    if (( fails > 0 )); then exit 1; fi
    printf '[PASS] %s: no unscoped owner-decision label and no pending placeholder\n' "$f"
    exit 0 ;;
  --branch)
    branch="${TRG_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
    [ -n "$branch" ] && [ "$branch" != HEAD ] || die2 "cannot resolve the branch (detached HEAD or no git)"
    if [[ -n "${TRG_SPECS_ROOT:-}" ]]; then
      root="$TRG_SPECS_ROOT"
    else
      top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
      [[ -n "$top" ]] || die2 "not inside a git repository, so the specs directory cannot be located"
      root="$top/knowledge-base/project/specs"
    fi
    safe="${branch//\//-}"; slug="$safe"
    slug="${slug#feature-}"; slug="${slug#feat-}"; slug="${slug#fix-}"
    matches=()
    add_match() { local m; for m in ${matches[@]+"${matches[@]}"}; do [[ "$m" == "$1" ]] && return 0; done; matches+=("$1"); }
    [[ -f "$root/$safe/decision-challenges.md" ]] && add_match "$root/$safe/decision-challenges.md"
    [[ -f "$root/archive/$safe/decision-challenges.md" ]] && add_match "$root/archive/$safe/decision-challenges.md"
    # archive directories are `<date>-<name>`, `<date>-<time>-<name>` or `<date>-<name>`: anchor the whole prefix
    # so a short slug never suffix-matches another feature's longer name.
    for pre in '????-??-??' '????????-??????' '????????'; do
      for nm in "$slug" "$safe"; do
        for cand in "$root"/archive/$pre-"$nm"/decision-challenges.md; do
          [[ -f "$cand" ]] && add_match "$cand"
        done
      done
    done
    if (( ${#matches[@]} == 0 )); then
      printf '[PASS] no decision-challenges artifact for %s\n' "$branch"
      exit 0
    fi
    (( ${#matches[@]} == 1 )) || die2 "ambiguous: ${#matches[@]} decision-challenges.md files match branch $branch (${matches[*]}); examine the right one by path"
    check_artifact "${matches[0]}" "${matches[0]}"; exit $? ;;
  ""|-h|--help)
    die2 "usage: $(basename "$0") <path> | --branch | --pr-body <file>" ;;
  -*) die2 "unknown option: $mode" ;;
  *)
    check_artifact "$mode" "$mode"; exit $? ;;
esac
