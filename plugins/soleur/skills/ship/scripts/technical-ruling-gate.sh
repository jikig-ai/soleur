#!/usr/bin/env bash
# The /ship Phase 5.5 Technical-Ruling Gate (hard rule hr-technical-fork-is-not-an-operator-question).
#
# Property: no PR reaches ready with a decision-challenges.md or PR-body line that asks the operator a
# TECHNICAL question. Every persisted decision has a valid row in the artifact's `## Decision Classes`
# table; every `technical` row carries a well-formed `Ruled by` cell that does not contradict what was
# built; the "Owner decision needed" / "Owner ruling needed" label appears only with
# `(operator: <category>)`. The gate checks FORM, never truth: a model that mislabels a decision can
# still write a plausible `operator (scope)` row. See technical-ruling-delegation.md (section 6).
#
# Usage:
#   technical-ruling-gate.sh <path>             check one decision-challenges.md
#   technical-ruling-gate.sh --branch           check this branch's artifact under
#                                               knowledge-base/project/specs/<branch>/, or under
#                                               specs/archive/*-<branch>/ when archived early;
#                                               an absent artifact is `[PASS] no decision-challenges artifact`
#   technical-ruling-gate.sh --pr-body <file>   check a PR body for an unscoped owner-decision label
#
# Exit codes:
#   0  every examined row passes (a `[PASS]` line on stdout)
#   1  at least one failure (`[FAIL] <path>:<row>: <reason> - <remedy>` on stderr, one per finding)
#   2  usage error, unreadable path, no `## Decision Classes` table, or a table with 0 rows. Never a
#      silent pass: "could not measure" is not "measured clean".
#
# Reasons (the suite asserts each): bad-class, bad-category, unruled-technical, bad-ruling-shape,
# ruling-contradicts-assumed, owner-label-unscoped.
#
# Test seams: TRG_EXEC_LOG (append one line per examined row), TRG_SPECS_ROOT and TRG_BRANCH (the
# `--branch` lookup, so a suite needs no git repository). Lines carrying `# mut:<name>` are the
# mutation points the suite edits to prove each check can fail.
#
# `set -uo pipefail`, deliberately NOT `-e`: the scanners are pipelines whose `grep` exits 1 on no match.

set -uo pipefail
export LC_ALL=C

CATEGORIES="money scope priority schedule irreversible production-mutating legal-risk brand"
CATS_RE="${CATEGORIES// /|}"
LABEL_RE='(owner (decision|ruling)s? needed|decision needed from the owner)'
RULING_RE='^Ruled by (CTO|CLO) agent, [0-9]{4}-[0-9]{2}-[0-9]{2}: .+ - .+; conforms: (yes|no|n/a)( .*)?$'
CTO_REMEDY='spawn soleur:engineering:cto now (at most two attempts, see technical-ruling-delegation.md), write the Ruled by cell, re-run; after two failed attempts leave the PR draft and file one domain/engineering issue, never an operator question'

cat_ok() { case " $CATEGORIES " in *" $1 "*) return 0 ;; esac; return 1; } # mut:cat
is_unruled() { [[ -z "$1" || "$1" == pending* ]]; } # mut:unruled
shape_ok() { [[ "$1" =~ $RULING_RE ]]; } # mut:shape
conforms_no() { [[ "$1" =~ conforms:\ no($|\ ) ]]; } # mut:conforms

die2() { printf '[ERROR] %s\n' "$*" >&2; exit 2; }

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# label_lines <file>: `<line>\t<text>` for every unfenced line that carries an owner-decision label.
label_lines() {
  awk -v re="$LABEL_RE" '
    /^ {0,3}(```|~~~)/ { f = !f; next } # mut:fence
    f { next }
    tolower($0) ~ re { printf "%d\t%s\n", NR, $0 }
  ' "$1"
}

# table_rows <file>: `@HEADING` once if the (unfenced) heading exists, then `<line>\t<row>` per data row.
table_rows() {
  awk '
    /^ {0,3}(```|~~~)/ { f = !f; next } # mut:fence-table
    f { next }
    $0 == "## Decision Classes" { if (!seen) { print "@HEADING"; seen = 1; state = 1 } next }
    state == 1 && /^[[:space:]]*$/ { next }
    state == 1 && /^\|/ { state = 2; next }
    state == 2 && /^\|[ :|-]+$/ { state = 3; next }
    state == 3 && /^\|/ { printf "%d\t%s\n", NR, $0; next }
    state == 3 { state = 4 }
    state == 1 || state == 2 { state = 4 }
  ' "$1"
}

check_labels() { # <file> <display-path>; prints [FAIL] lines, returns the count
  local file="$1" shown="$2" n=0 ln text low
  while IFS=$'\t' read -r ln text; do
    [[ -n "$ln" ]] || continue
    low="${text,,}"
    if [[ ! "$low" =~ \(operator:\ ($CATS_RE)\) ]]; then
      printf '[FAIL] %s:%s: owner-label-unscoped - the owner-decision label may only carry an operator-class item; append (operator: <category>) with a category from the closed list (%s), or route the question to the CTO (technical-ruling-delegation.md)\n' "$shown" "$ln" "$CATEGORIES" >&2
      n=$((n + 1))
    fi
  done < <(label_lines "$file")
  return "$n"
}

check_artifact() { # <file> <display-path>
  local file="$1" shown="$2" rows_file idx=0 rows_examined=0 fails=0 ln row inner c1 c2 c3 extra
  [[ -e "$file" ]] || die2 "$shown: no such file"
  [[ -f "$file" && -r "$file" ]] || die2 "$shown: not a readable regular file"
  rows_file="$(mktemp -t trg-rows.XXXXXXXX)" || die2 "mktemp failed"
  trap 'rm -f "$rows_file"' RETURN
  table_rows "$file" > "$rows_file"
  grep -qxF '@HEADING' "$rows_file" || die2 "$shown: no '## Decision Classes' table outside a fenced block"
  sed -i '/^@HEADING$/d' "$rows_file"
  # mut:scan
  [[ -s "$rows_file" ]] || die2 "$shown: Decision Classes table has 0 rows examined"
  while IFS=$'\t' read -r ln row; do
    idx=$((idx + 1))
    rows_examined=$((rows_examined + 1)) # mut:count
    [[ -n "${TRG_EXEC_LOG:-}" ]] && echo "row $shown:$idx" >> "$TRG_EXEC_LOG"
    inner="${row#|}"; inner="${inner%|}"
    if [[ "$(tr -cd '|' <<<"$inner" | wc -c | tr -d ' ')" != "2" ]]; then
      printf '[FAIL] %s:%s: bad-class - row %s (line %s) must have exactly three cells: Item | Class | Ruling\n' "$shown" "$idx" "$idx" "$ln" >&2
      fails=$((fails + 1)); continue
    fi
    IFS='|' read -r c1 c2 c3 extra <<<"$inner"
    c2="$(trim "$c2")"; c3="$(trim "$c3")"
    if [[ "$c2" == technical ]]; then
      if is_unruled "$c3"; then
        printf '[FAIL] %s:%s: unruled-technical - row %s (line %s) is technical with no ruling: %s\n' "$shown" "$idx" "$idx" "$ln" "$CTO_REMEDY" >&2
        fails=$((fails + 1))
      elif ! shape_ok "$c3"; then
        printf '[FAIL] %s:%s: bad-ruling-shape - row %s (line %s) ruling must read: Ruled by CTO agent, <date>: <decision> - <rationale>; conforms: yes|no|n/a (<note>)\n' "$shown" "$idx" "$idx" "$ln" >&2
        fails=$((fails + 1))
      elif conforms_no "$c3"; then
        printf '[FAIL] %s:%s: ruling-contradicts-assumed - row %s (line %s): the ruling differs from what was built on the assumption; re-enter work for this item, or record conforms: n/a (nothing built on the assumption)\n' "$shown" "$idx" "$idx" "$ln" >&2
        fails=$((fails + 1))
      fi
    elif [[ "$c2" =~ ^operator\ \(([a-z-]+)\)$ ]]; then
      if ! cat_ok "${BASH_REMATCH[1]}"; then
        printf '[FAIL] %s:%s: bad-category - row %s (line %s) category "%s" is not in the closed list (%s)\n' "$shown" "$idx" "$idx" "$ln" "${BASH_REMATCH[1]}" "$CATEGORIES" >&2
        fails=$((fails + 1))
      elif [[ -z "$c3" ]]; then
        printf '[FAIL] %s:%s: bad-ruling-shape - row %s (line %s) an operator row must name the ACTION being authorised in its Ruling cell\n' "$shown" "$idx" "$idx" "$ln" >&2
        fails=$((fails + 1))
      fi
    elif [[ "$c2" == operator ]]; then
      printf '[FAIL] %s:%s: bad-category - row %s (line %s) a bare "operator" is invalid; write operator (<category>) with a category from the closed list (%s)\n' "$shown" "$idx" "$idx" "$ln" "$CATEGORIES" >&2
      fails=$((fails + 1))
    else
      printf '[FAIL] %s:%s: bad-class - row %s (line %s) Class must be "technical" or "operator (<category>)", got "%s"\n' "$shown" "$idx" "$idx" "$ln" "$c2" >&2
      fails=$((fails + 1))
    fi
  done < "$rows_file"
  check_labels "$file" "$shown"; fails=$((fails + $?))
  if (( fails > 0 )); then return 1; fi
  printf '[PASS] %s: %s rows examined\n' "$shown" "$rows_examined"
  return 0
}

mode="${1:-}"
case "$mode" in
  --pr-body)
    f="${2:-}"; [[ -n "$f" ]] || die2 "usage: --pr-body <file>"
    [[ -f "$f" && -r "$f" ]] || die2 "$f: not a readable regular file"
    check_labels "$f" "$f"; n=$?
    if (( n > 0 )); then exit 1; fi
    printf '[PASS] %s: no unscoped owner-decision label\n' "$f"
    exit 0 ;;
  --branch)
    branch="${TRG_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
    [[ -n "$branch" && "$branch" != HEAD ]] || die2 "cannot resolve the branch (detached HEAD or no git)"
    root="${TRG_SPECS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)/knowledge-base/project/specs}"
    found=""
    if [[ -f "$root/$branch/decision-challenges.md" ]]; then
      found="$root/$branch/decision-challenges.md"
    else
      for cand in "$root"/archive/*-"$branch"/decision-challenges.md "$root/archive/$branch/decision-challenges.md"; do
        [[ -f "$cand" ]] && found="$cand"
      done
    fi
    if [[ -z "$found" ]]; then
      printf '[PASS] no decision-challenges artifact for %s\n' "$branch"
      exit 0
    fi
    check_artifact "$found" "$found"; exit $? ;;
  ""|-h|--help)
    die2 "usage: $(basename "$0") <path> | --branch | --pr-body <file>" ;;
  -*) die2 "unknown option: $mode" ;;
  *)
    check_artifact "$mode" "$mode"; exit $? ;;
esac
