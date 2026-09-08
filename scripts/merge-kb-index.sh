#!/usr/bin/env bash
# merge-kb-index.sh — git merge driver for knowledge-base/INDEX.md (#7935).
#
# Registered as `merge.kb-index.driver` by scripts/install-kb-merge-driver.sh and
# selected by the root .gitattributes. Git invokes it as:
#
#     bash scripts/merge-kb-index.sh %O %A %B %P
#
# overwriting %A on success (exit 0), or exiting non-zero to raise a conflict.
#
# WHY THIS DOES NOT REGENERATE FROM THE TREE. The issue that motivated this
# asked for a driver that resolves by re-running generate-kb-index.sh against
# the merged tree. Measured (git 2.53.0): at driver time the working tree AND
# the index are still on the OURS side — the incoming side's files are not on
# disk, and MERGE_HEAD / REBASE_HEAD / CHERRY_PICK_HEAD are all unset. A
# generator run here would index the ours-side file set and drop exactly the
# incoming rows this driver exists to preserve. Deferring to `pre-merge-commit`
# fails too: that hook does see the merged tree, but `git merge` computes its
# tree before the hook runs, so the hook's `git add` is discarded. The driver's
# only inputs are the three files git hands it, so the merge is set arithmetic
# over their rows.
#
# WHERE THAT DIVERGES FROM A TRUE REGENERATION — three cases, all real and none
# visible to a structural check: (1) one side renames X.md to Y.md while the
# other edits X.md's title, so the row set sees a delete plus an add carrying
# the PRE-edit title; (2) a generator rule change on one branch (eligibility,
# title extraction, escaping) leaves the other side's rows rendered under the
# old rules; (3) a future title source outside the file itself. This is exactly
# why the CI guard is `generate-kb-index.sh --check` — a regeneration diff — and
# not a structural lint: only re-running the generator over the merged tree
# catches all three. The driver makes the common case (both sides only added
# files) correct and conflict-free; the guard makes the uncommon case loud.
#
# EVERY FAILURE PATH WRITES A SENTINEL. Measured: when a merge driver exits
# non-zero, git reports `CONFLICT (content)`, marks the path `UU`, leaves ours
# content in place — and writes NO conflict markers. The file reads as clean, so
# `guardrails:block-conflict-markers` never fires and the repo's own merge-pr
# guidance ("read the file with conflict markers") leads straight to `git add`
# of a wrong index. That is the very row-drop this driver exists to close, one
# level down. The sentinel below is what makes the failure visible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/kb-index-render.sh
source "$SCRIPT_DIR/lib/kb-index-render.sh"

readonly EXPECTED_PATH="knowledge-base/INDEX.md"
readonly SENTINEL='<<<<<<< kb-index: merge driver could not resolve — re-run the merge after fixing registration'
# Far above any real row (the longest in a 6,432-row corpus is ~200 bytes). This
# is a memory bound on adversarial input, not a format rule.
readonly MAX_LINE_BYTES=8192

O="${1:-}"; A="${2:-}"; B="${3:-}"; P="${4:-}"

_sentinel_written=0
write_sentinel() {
  (( _sentinel_written == 0 )) || return 0
  _sentinel_written=1
  [[ -n "$A" && -f "$A" ]] || return 0
  # SCRATCH FILE BESIDE %A, DELIBERATELY NOT mktemp. The sentinel's whole job is
  # to be written on the paths where something has already gone wrong, and one
  # of those paths is a broken TMPDIR -- which is exactly when `mktemp` also
  # fails. A sentinel writer that depends on mktemp is silent in the case it
  # exists for. %A's directory is writable by definition: git just wrote %A into
  # it. Found by this file's own mutation battery (row G7), which survived until
  # the mktemp dependency was removed.
  local tmp="$A.kbi-sentinel.$$"
  # PREPENDED, so a human opening the file sees it first, and kept to a single
  # line so AC6's `grep -c '^<<<<<<< kb-index'` is an exact-count assertion.
  if { printf '%s\n' "$SENTINEL"; cat "$A"; } > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$A" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  return 0
}

# THE TRAP IS THE MECHANISM; the explicit die() calls are defence in depth.
#
# Under `set -euo pipefail` an UNHANDLED failure — an awk crash on adversarial
# input, an unbound variable, a read failure on an embedded NUL, disk-full while
# writing %A — terminates this script through the shell's own -e path without
# ever reaching a hand-placed sentinel write. That reproduces the markerless
# conflict described above, specifically on the adversarial-input paths this
# design must assume are reachable. So the trap is installed BEFORE any parsing.
trap 'write_sentinel; exit 1' ERR

WORKDIR=""
cleanup() { [[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT INT TERM HUP

die() {
  printf 'merge-kb-index: %s\n' "$1" >&2
  write_sentinel
  exit 1
}

# --- 0. Refuse any path but the one this driver understands -------------------
#
# .gitattributes is a committed, PR-mergeable file, so a `merge=kb-index` line
# redirected onto arbitrary paths would otherwise have this driver parse
# unrelated content as index rows and spray conflicts repo-wide. Not an RCE
# vector — the driver COMMAND comes only from local config, never from
# .gitattributes — but a cheap denial-of-service lever, closed in one line.
[[ "$P" == "$EXPECTED_PATH" ]] || die "refusing to run on '$P'; this driver only handles $EXPECTED_PATH"
[[ -f "$O" && -f "$A" && -f "$B" ]] || die "expected three readable input files (%O %A %B)"

WORKDIR="$(mktemp -d)"

# --- 1. Parse one rendered index into a rel<TAB>title TSV ---------------------
#
# THE PARSE ASSUMES ADVERSARIAL INPUT, BECAUSE IT ALREADY IS. The generator
# escapes only `[` and `]` in titles, so a `title:` frontmatter value containing
# `$(...)`, backticks, quotes or semicolons reaches a committed INDEX.md row
# verbatim through any ordinary PR today. Hence: no eval, no command line built
# from row content, line-by-line reads (never a whole-file multi-line regex that
# would let a crafted blob smuggle content across row boundaries), and every
# expansion quoted.
#
# Titles are kept in their RENDERED (already-escaped) form — the same form the
# generator writes into its own TSV — so re-rendering is byte-exact with no
# unescape step to disagree with the generator's escape step.
parse_index() {
  local src="$1" out="$2"
  : > "$out"
  local line body title rel
  while IFS= read -r line || [[ -n "$line" ]]; do
    # NO CR STRIPPING HERE, DELIBERATELY. An earlier revision stripped a trailing
    # \r on the theory that a CRLF side would otherwise split the rel-keyed set
    # into spurious duplicate rows. Measured: it cannot. Round-trip validation
    # below re-renders every parsed row with LF endings and byte-compares
    # against the input, so a CRLF file fails validation and raises a conflict
    # before the set arithmetic ever runs -- with the strip line present OR
    # absent. The line changed only which error message appeared, never an
    # outcome, and its own mutation row survived because of that. A guard that
    # cannot change an outcome but reads as protective is worse than no guard.
    # CRLF is not a canonical generated index; failing closed on it is correct.
    (( ${#line} <= MAX_LINE_BYTES )) || die "input line exceeds ${MAX_LINE_BYTES} bytes in $src"
    [[ "$line" == "- ["* ]] || continue
    [[ "$line" == *")" ]] || die "malformed row (no closing paren) in $src"
    body="${line#- [}"
    body="${body%)}"
    [[ "$body" == *"](" ]] && die "malformed row (empty rel) in $src"
    [[ "$body" == *"]("* ]] || die "malformed row (no ]( separator) in $src"
    # Split on the LAST `](`: a title may legitimately contain `](`-free
    # brackets, and anchoring on the last occurrence is what the renderer's
    # own output shape guarantees.
    title="${body%](*}"
    rel="${body##*](}"
    printf '%s\t%s\n' "$rel" "$title" >> "$out"
  done < "$src"
}

# --- 2. Validate by round-trip, never by checklist ----------------------------
#
# Re-render the parsed rows and byte-compare against the input. This is strictly
# stronger than a list of structural assertions: it makes a MISPARSE impossible
# to act on (a title containing `](`, a rel containing `)`, a stray bracket all
# fail here rather than silently producing a wrong row), and it pins the
# extracted renderer's byte-identity to the generator's on every merge rather
# than only in a parity test. All three inputs are validated — the ancestor is
# the base of the set arithmetic and is exactly as capable of being corrupt.
validate_roundtrip() {
  local src="$1" tsv="$2" rendered="$WORKDIR/rt.$$"
  kb_render_index "$tsv" > "$rendered"
  cmp -s "$rendered" "$src" || die "round-trip validation failed for $src (not a canonical generated index)"
  rm -f "$rendered"
}

# --- 3. Containment: a rel is a path the consumers will follow ----------------
#
# Unlike the generator — which only ever emits a row for a file it found itself
# under KB_DIR — this driver's row set is a pure function of whatever rel
# strings appear in the three inputs. A branch that hand-edits INDEX.md can
# introduce `- [Note](../../.env)`, and that row round-trips byte-identically,
# so validation above cannot see it. Five skills and agents treat index rows as
# trustworthy relative paths and follow them.
validate_rels() {
  local tsv="$1" rel _t
  while IFS=$'\t' read -r rel _t; do
    [[ -n "$rel" ]] || die "empty rel in a row"
    [[ "$rel" != /* ]] || die "absolute rel '$rel' is not permitted in the index"
    case "/$rel/" in
      */../*) die "rel '$rel' escapes knowledge-base/ via a .. segment" ;;
    esac
  done < "$tsv"
}

load() {
  local src="$1" tsv="$2"
  parse_index "$src" "$tsv"
  validate_roundtrip "$src" "$tsv"
  validate_rels "$tsv"
}

TSV_O="$WORKDIR/o.tsv"; TSV_A="$WORKDIR/a.tsv"; TSV_B="$WORKDIR/b.tsv"
load "$O" "$TSV_O"
load "$A" "$TSV_A"
load "$B" "$TSV_B"

# --- 4. Three-way merge keyed on rel -----------------------------------------
declare -A base=() ours=() theirs=()
declare -A have_base=() have_ours=() have_theirs=()
read_map() {
  local tsv="$1" which="$2" rel title
  while IFS=$'\t' read -r rel title; do
    case "$which" in
      base)   base["$rel"]="$title";   have_base["$rel"]=1 ;;
      ours)   ours["$rel"]="$title";   have_ours["$rel"]=1 ;;
      theirs) theirs["$rel"]="$title"; have_theirs["$rel"]=1 ;;
    esac
  done < "$tsv"
}
read_map "$TSV_O" base
read_map "$TSV_A" ours
read_map "$TSV_B" theirs

declare -A merged=()
declare -A seen=()
for rel in "${!have_base[@]}" "${!have_ours[@]}" "${!have_theirs[@]}"; do
  seen["$rel"]=1
done

for rel in "${!seen[@]}"; do
  in_o="${have_base[$rel]:-0}"; in_a="${have_ours[$rel]:-0}"; in_b="${have_theirs[$rel]:-0}"
  if [[ "$in_o" == 1 ]]; then
    # Deleted on either side => deleted in the result. A file removed on one
    # branch must not be resurrected by the other branch's untouched row.
    if [[ "$in_a" != 1 || "$in_b" != 1 ]]; then
      continue
    fi
    t_o="${base[$rel]}"; t_a="${ours[$rel]}"; t_b="${theirs[$rel]}"
    if [[ "$t_a" == "$t_b" ]]; then
      merged["$rel"]="$t_a"
    elif [[ "$t_a" == "$t_o" ]]; then
      merged["$rel"]="$t_b"
    elif [[ "$t_b" == "$t_o" ]]; then
      merged["$rel"]="$t_a"
    else
      die "both sides retitled '$rel' differently; refusing to pick one"
    fi
  else
    # Added on one or both sides.
    if [[ "$in_a" == 1 && "$in_b" == 1 ]]; then
      # A rel absent from the ancestor and independently added on BOTH sides
      # with different titles is a distinct shape from the retitle case above,
      # and "add rows added on either side" does not say which title wins. It
      # must not silently pick one: that would break byte-identity with a fresh
      # generation for this input while still exiting 0.
      if [[ "${ours[$rel]}" == "${theirs[$rel]}" ]]; then
        merged["$rel"]="${ours[$rel]}"
      else
        die "'$rel' was added on both sides with different titles; refusing to pick one"
      fi
    elif [[ "$in_a" == 1 ]]; then
      merged["$rel"]="${ours[$rel]}"
    else
      merged["$rel"]="${theirs[$rel]}"
    fi
  fi
done

# --- 5. Render ----------------------------------------------------------------
#
# `LC_ALL=C sort` BY REL, matching the generator exactly. The generator sorts
# its rel<TAB>title stream, not its rendered lines, and the two orders differ
# because a row renders title-first.
OUT_TSV="$WORKDIR/merged.tsv"
: > "$OUT_TSV"
for rel in "${!merged[@]}"; do
  printf '%s\t%s\n' "$rel" "${merged[$rel]}"
done | LC_ALL=C sort > "$OUT_TSV"

kb_render_index "$OUT_TSV" > "$WORKDIR/merged.md"
cat "$WORKDIR/merged.md" > "$A"
exit 0
