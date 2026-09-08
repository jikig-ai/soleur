#!/usr/bin/env bash
# generate-kb-index.sh — Generate knowledge-base/INDEX.md from file metadata.
#
# Usage: bash scripts/generate-kb-index.sh [--help] [--out DIR] [--check]
#
# Walks knowledge-base/**/*.md, extracts titles from YAML frontmatter
# (fallback: first # heading, then kebab-to-title-case filename), and
# outputs a flat sorted markdown list grouped by top-level domain.
#
# Excludes archive/ directories and INDEX.md itself. Inside
# knowledge-base/project/specs/<feature>/, only spec.md and tasks.md are
# indexed — other flat files there are per-feature working state (#7399).
#
# Flags:
#   --out DIR   Write INDEX.md, kb-tags.txt and kb-categories.txt into DIR
#               instead of the tracked knowledge-base/ artifacts.
#   --check     Regenerate off to the side and diff against the committed
#               artifacts; print the diff and exit non-zero on any mismatch.
#
# INDEX.md is resolved on merge by scripts/merge-kb-index.sh, registered as
# merge.kb-index.driver by scripts/install-kb-merge-driver.sh and selected by
# the root .gitattributes. If a merge of INDEX.md ever conflicts, re-run the
# merge after fixing that registration -- never resolve it by taking one side.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# KB_DIR is overridable by env so tests can point at a fixture corpus.
KB_DIR="${KB_DIR:-$REPO_ROOT/knowledge-base}"
# Strip a trailing slash before KB_DIR is used in any prefix strip. The rel=
# computation below does "${f#"$KB_DIR/"}", which silently fails to strip on a
# trailing slash and emits absolute paths into every row.
KB_DIR="${KB_DIR%/}"
INDEX_FILE="$KB_DIR/INDEX.md"
LEARNINGS_DIR="$KB_DIR/project/learnings"
TAGS_FILE="$KB_DIR/kb-tags.txt"
CATEGORIES_FILE="$KB_DIR/kb-categories.txt"

# shellcheck source=scripts/lib/kb-index-render.sh
source "$SCRIPT_DIR/lib/kb-index-render.sh"

# --out DIR is the primitive (mirroring regenerate-c4-model.sh --out); --check is
# a thin wrapper around it. Both are additive: the four live callers all invoke
# this script with no arguments and are unaffected.
OUT_DIR=""
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      sed -n '2,/^$/s/^# //p' "$0"
      exit 0
      ;;
    --out)
      OUT_DIR="${2:-}"
      [[ -n "$OUT_DIR" ]] || { echo "ERROR: --out requires a directory" >&2; exit 2; }
      shift 2
      ;;
    --check)
      CHECK=1
      shift
      ;;
    *)
      echo "ERROR: unknown argument '$1' (see --help)" >&2
      exit 2
      ;;
  esac
done

if [[ "$CHECK" == 1 ]]; then
  # Regenerate into a scratch directory and diff against the committed
  # artifacts. This is a REGENERATION DIFF and not a structural lint on purpose:
  # a checklist of structural assertions would re-implement the generator's own
  # row-eligibility predicate in a second place (which ADR-174 warns will
  # drift), and it still could not see title drift, renderer drift, or the
  # rename-plus-edit divergence the merge driver documents as its honest limit.
  # Regenerating catches all of them, including the case where no merge driver
  # was registered at all and git line-merged the file into something that reads
  # as clean.
  [[ -z "$OUT_DIR" ]] || { echo "ERROR: --check and --out are mutually exclusive" >&2; exit 2; }
  _check_dir="$(mktemp -d)"
  trap 'rm -rf "$_check_dir"' EXIT
  "$0" --out "$_check_dir" >/dev/null
  # CAPPED, and on ONE stream. `diff -u` was both the gate and the diagnostic,
  # uncapped and on stdout while the ERROR line went to stderr — so a stale index
  # emitted unbounded interleaved output (measured: 295 lines for a 280-row
  # drift; issue #7401 records main being stale by 3,711 rows, which is ~4.5k
  # lines). That is hr-never-run-commands-with-unbounded-output in the guard the
  # design designates as the last thing between a line-merged index and main.
  # The c4 precedent this flag is modelled on gates on `cmp -s` and caps its
  # diagnostic at `head -20`.
  _check_rc=0
  _check_cap=40
  for _f in INDEX.md kb-tags.txt kb-categories.txt; do
    if ! cmp -s "$KB_DIR/$_f" "$_check_dir/$_f"; then
      {
        echo "ERROR: $KB_DIR/$_f differs from a fresh generation (first $_check_cap diff lines):"
        # `|| true` is load-bearing: `diff` exits 1 when files differ — which is
        # the whole reason we are here — and under `pipefail` that status
        # survives `head`, so `set -e` killed the script mid-diagnostic before
        # `_check_rc=1` was ever reached. The guard still exited non-zero, so it
        # LOOKED correct, while the remediation line never printed and the two
        # mutation rows pinning that exit path went vacuous. Caught by this
        # change's own battery (C1/C2 SURVIVED).
        diff -u "$KB_DIR/$_f" "$_check_dir/$_f" | head -n "$_check_cap" || true
      } >&2
      _check_rc=1
    fi
  done
  if [[ "$_check_rc" -ne 0 ]]; then
    echo "Run: bash scripts/generate-kb-index.sh" >&2
    exit 1
  fi
  echo "kb index artifacts are fresh."
  exit 0
fi

if [[ -n "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"
  INDEX_FILE="$OUT_DIR/INDEX.md"
  TAGS_FILE="$OUT_DIR/kb-tags.txt"
  CATEGORIES_FILE="$OUT_DIR/kb-categories.txt"
fi

if [[ ! -d "$KB_DIR" ]]; then
  echo "ERROR: knowledge-base/ directory not found at $KB_DIR" >&2
  exit 1
fi

# Collect all eligible .md files (exclude archive/, INDEX.md, non-.md, symlinks)
#
# The third group implements the spec-directory allowlist (ADR-174):
# a spec directory contributes its spec.md and its tasks.md — the two files
# that NAME a feature — plus anything the author deliberately organised into a
# SUBDIRECTORY. Files sitting flat alongside spec.md/tasks.md are
# branch-lifetime working state (session-state.md and a long tail of one-off
# names) and are not indexed.
#
# An allowlist, not a denylist: filename invention is the norm here, so any
# enumerated deny set is stale the next time someone writes a phase0-evidence.md.
# ADR-174 holds the dated measurements; deliberately not repeated here, because
# a count in a comment rots and this comment is also --help output.
#
# The fourth arm is what keeps the rule FLAT. `-path '*/project/specs/*/*/*'`
# needs two literal `/` after specs/, so specs/feat-x/tasks.md (one) is excluded
# while specs/feat-x/case-studies/01-a.md (two) is kept. Without it the
# exclusion is depth-unbounded and silently drops nested durable content —
# vendor interface reference under specs/external/, for instance, which lives in
# dirs that have no spec.md or tasks.md at all and would retain ZERO rows.
#
# The patterns are single-quoted and NOT interpolated with $KB_DIR on purpose.
# `-path "$KB_DIR/project/specs/*"` makes the predicate depend on the TEXTUAL
# form of KB_DIR: a trailing slash yields a `//` no find-emitted path contains,
# so the exclusion silently evaluates true for everything and the whole feature
# no-ops with exit 0 and a green suite.
mapfile -t all_files < <(
  find "$KB_DIR" -type f -not -type l -name '*.md' \
    -not -path '*/archive/*' \
    -not -name 'INDEX.md' \
    \( -not -path '*/project/specs/*' -o -name 'spec.md' -o -name 'tasks.md' \
       -o -path '*/project/specs/*/*/*' \) \
    | LC_ALL=C sort
)

total=${#all_files[@]}

if [[ $total -eq 0 ]]; then
  echo "WARNING: no markdown files found in $KB_DIR" >&2
  exit 0
fi

# Extract titles in parallel batches using xargs -P.
# Each batch processes ~100 files in a single bash process, 4 batches at a time.
# Output: one "rel_path\ttitle" per line, sorted.
tmpfile=$(mktemp)
facets_tmp=$(mktemp)
trap 'rm -f "$tmpfile" "$facets_tmp"' EXIT

printf '%s\0' "${all_files[@]}" | xargs -0 -P4 -n100 bash -c '
  KB_DIR="$1"; shift
  sq=$(printf "\x27")
  for f in "$@"; do
    rel="${f#"$KB_DIR/"}"
    title="" heading="" fm=0 nr=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      ((nr++)); ((nr > 30)) && break
      if [[ "$line" == "---" ]]; then ((fm++)); ((fm >= 2)) && break; continue; fi
      if ((fm == 1)) && [[ "$line" == title:* ]]; then
        title="${line#title:}"; title="${title# }"
        title="${title#\"}"; title="${title%\"}"
        title="${title#$sq}"; title="${title%$sq}"
        break
      fi
      [[ -z "$heading" && "$line" == "# "* ]] && heading="${line#\# }"
    done < "$f"
    [[ -n "$title" ]] || title="$heading"
    if [[ -z "$title" ]]; then
      n=$(basename "$f" .md)
      n="${n#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
      title=$(printf "%s" "$n" | tr "-" " ")
    fi
    # Escape [ and ] in titles to prevent markdown link injection
    title="${title//\[/\\[}"
    title="${title//]/\\]}"
    printf "%s\t%s\n" "$rel" "$title"
  done
' _ "$KB_DIR" | LC_ALL=C sort > "$tmpfile"

# Build the index from the sorted entries.
#
# The layout lives in scripts/lib/kb-index-render.sh, sourced above, because
# scripts/merge-kb-index.sh must emit byte-identical content from git's three
# merge inputs. A second copy here would drift, and the drift would be invisible
# -- both files would still look like an index.
# PUBLISHED ATOMICALLY, mirroring regenerate-c4-model.sh's `--out` contract
# rather than only its flag shape. A bare `> "$INDEX_FILE"` truncates the TRACKED
# artifact before the renderer runs, so a SIGINT, a full disk, or an OOM-killed
# xargs child leaves knowledge-base/INDEX.md destroyed on disk (measured: 156
# bytes -> 8 bytes of partial output). lefthook runs this generator on every
# commit touching knowledge-base/, so that window is routine.
_index_tmp="$INDEX_FILE.tmp.$$"
kb_render_index "$tmpfile" > "$_index_tmp"
mv -f "$_index_tmp" "$INDEX_FILE"

echo "Generated $INDEX_FILE ($total files indexed)"

# ---------------------------------------------------------------------------
# Facet extraction: emit kb-tags.txt and kb-categories.txt from learnings/.
#
# Scoped to knowledge-base/project/learnings/ per FR14. Output files are
# sorted, unique, lowercased. Safe to regenerate at any time; regeneration
# is deterministic across runs.
#
# Parsing rules (TR1, TR6, TR7, TR10, TR11):
#   - Frontmatter delimited by the first pair of ^---$ lines (`c==1` idiom).
#     Body ^---$ horizontal rules do not re-open frontmatter.
#   - Inline tags: `tags: [a, b, c]` — split on commas, trim, strip outer quotes.
#   - Block tags:  `tags:\n  - a\n  - b` — continue while lines match indent+dash.
#     Exit block state on `^[a-z_]+:` (next sibling key).
#   - Category: single scalar, strip outer quotes, lowercase.
#   - Empty `tags: []` emits nothing.
#   - Files without frontmatter or without these fields are silently skipped.
#
# Implementation: single awk invocation per xargs batch, run SERIALLY.
#
# This walk deliberately has no `-P` flag. It previously ran `-P4` with the
# redirect below, which is a data race: the redirect is on the whole pipeline,
# so `$facets_tmp` is a REGULAR FILE and every parallel awk child inherits the
# same open file description on it. PIPE_BUF atomicity does not apply to
# regular files at all, and awk block-buffers its stdout, so a 4 KB flush
# boundary lands mid-line and another child's write splices into the gap.
# `cut -f2` then keeps the splice and DISCARDS the real value — so a torn line
# fabricates a tag and destroys a true one.
#
# That was not theoretical: it shipped `agent-worcat` (from `agent-workflow,
# mcp-integration`), `blast-radcat`, `cloudflacat` and ~11 more into
# kb-tags.txt/kb-categories.txt, and kb-search validates `--tag`/`--category`
# against those files, so a torn value makes a real tag report as invalid.
# Measured: 5 runs over one unchanged corpus produced 5 distinct outputs.
# Serial produces 1, and it is byte-identical to the `stdbuf -oL` fix.
#
# Serial is not slower here (2,119 files, measured within noise of -P4), and it
# needs no `stdbuf`, which is absent from stock macOS. Do not re-add `-P`
# without either line-buffering the children or giving each batch its own file.
#
# Deduplication happens via `sort -u` after collection.
# ---------------------------------------------------------------------------

if [[ -d "$LEARNINGS_DIR" ]]; then
  find "$LEARNINGS_DIR" -type f -not -type l -name '*.md' \
    -not -path '*/archive/*' -print0 \
    | xargs -0 -n100 awk '
      FNR == 1 { c = 0; in_block = 0 }

      /^---$/ { c++; next }
      c != 1 { next }

      # Block continuation: indented `- value`
      in_block && /^[[:space:]]+-[[:space:]]+/ {
        val = $0
        sub(/^[[:space:]]+-[[:space:]]+/, "", val)
        gsub(/^["\047]|["\047]$/, "", val)
        val = tolower(val)
        if (val != "") print "tag\t" val
        next
      }
      # Block terminator: any line that is not a continuation of the list.
      # Matches the next top-level frontmatter key (alpha, digit, or underscore)
      # or a blank/body line. Only indented "- value" lines stay in block state.
      in_block && /^[^[:space:]-]/ { in_block = 0 }

      # Empty inline array: tags: []
      /^tags:[[:space:]]*\[[[:space:]]*\][[:space:]]*$/ { next }

      # Inline form: tags: [a, b, c]
      /^tags:[[:space:]]*\[.*\][[:space:]]*$/ {
        line = $0
        sub(/^tags:[[:space:]]*\[/, "", line)
        sub(/\][[:space:]]*$/, "", line)
        n = split(line, parts, /[[:space:]]*,[[:space:]]*/)
        for (i = 1; i <= n; i++) {
          val = parts[i]
          gsub(/^["\047]|["\047]$/, "", val)
          val = tolower(val)
          if (val != "") print "tag\t" val
        }
        next
      }

      # Block form start: tags:\n  - a\n  - b
      /^tags:[[:space:]]*$/ { in_block = 1; next }

      # Category: single scalar
      /^category:[[:space:]]*/ {
        val = $0
        sub(/^category:[[:space:]]*/, "", val)
        gsub(/^["\047]|["\047]$/, "", val)
        val = tolower(val)
        if (val != "") print "cat\t" val
      }
    ' > "$facets_tmp"

  # Split the tagged stream into two sorted, unique artifacts.
  # `grep ... || true` avoids set -e tripping when a facet type has no entries.
  # Same atomic-publish contract as the index above.
  { grep $'^tag\t' "$facets_tmp" || true; } | cut -f2 | LC_ALL=C sort -u > "$TAGS_FILE.tmp.$$"
  mv -f "$TAGS_FILE.tmp.$$" "$TAGS_FILE"
  { grep $'^cat\t' "$facets_tmp" || true; } | cut -f2 | LC_ALL=C sort -u > "$CATEGORIES_FILE.tmp.$$"
  mv -f "$CATEGORIES_FILE.tmp.$$" "$CATEGORIES_FILE"

  tag_count=$(wc -l < "$TAGS_FILE" | tr -d '[:space:]')
  cat_count=$(wc -l < "$CATEGORIES_FILE" | tr -d '[:space:]')
  echo "Generated $TAGS_FILE ($tag_count tags) and $CATEGORIES_FILE ($cat_count categories)"
else
  # Emit empty artifacts so downstream tooling has a stable contract.
  : > "$TAGS_FILE"
  : > "$CATEGORIES_FILE"
  echo "Note: $LEARNINGS_DIR not found; emitted empty facet artifacts."
fi
