#!/usr/bin/env bash
# kb-drift-walker.sh — PR-H (#3244) Phase 5.
#
# Two checks against the knowledge-base + AGENTS.md:
#   (1) Broken intra-KB markdown links: every `](path.md)` target must exist.
#   (2) Code-anchor drift: every `path/to/file.ext:line` anchor in AGENTS.md
#       rule bodies + knowledge-base/project/learnings/**/*.md must point to
#       an existing file (existence-only; line-number bound check deferred
#       to #4073 semantic re-anchor).
#
# Skips: archive/ and .git/.
#
# Output: a single JSON object on stdout with shape:
#   { "findings": [ { "kind": "broken-link"|"broken-anchor",
#                     "source_path": "<rel-path>",
#                     "target": "<rel-path-or-anchor>",
#                     "source_ref": "link-<sha256[:16]>" | "anchor-<sha256[:16]>" } ],
#     "counts": { "broken_link": N, "broken_anchor": M } }
#
# Exit 0 always; findings live in the JSON. The ingest route is the
# fail-closed boundary, not this script.
#
# Test toggle: KB_DRIFT_FIXTURE_ROOT — override repo root (default: git toplevel).

set -euo pipefail

REPO_ROOT="${KB_DRIFT_FIXTURE_ROOT:-$(git rev-parse --show-toplevel)}"
KB_DIR="$REPO_ROOT/knowledge-base"
AGENTS_FILES=(
  "$REPO_ROOT/AGENTS.md"
  "$REPO_ROOT/AGENTS.core.md"
  "$REPO_ROOT/AGENTS.docs.md"
  "$REPO_ROOT/AGENTS.rest.md"
)
LEARNINGS_DIR="$KB_DIR/project/learnings"

# JSON-safe escape: backslash + double-quote + control chars; no `jq` dep so
# the script stays portable across CI runners.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# Stable 16-char dedup id from "source + target". Both supabase-js INSERT
# and the partial-unique index treat source_ref as opaque text — the
# hash is computed at script time so the same finding produces the same
# source_ref on every run (idempotent ingest).
sha16() {
  printf '%s' "$1" | sha256sum | head -c 16
}

# Emit one finding to a temp accumulator that we'll splice into the final
# JSON. Args: kind source_path target.
accumulator="$(mktemp)"
trap 'rm -f "$accumulator"' EXIT
broken_link=0
broken_anchor=0

emit_finding() {
  local kind="$1" source_path="$2" target="$3"
  local prefix
  case "$kind" in
    broken-link) prefix="link-"; broken_link=$((broken_link + 1)) ;;
    broken-anchor) prefix="anchor-"; broken_anchor=$((broken_anchor + 1)) ;;
    *) return 1 ;;
  esac
  local ref="${prefix}$(sha16 "${source_path}${target}")"
  printf '%s\n' "$(printf '{"kind":"%s","source_path":"%s","target":"%s","source_ref":"%s"}' \
    "$(json_escape "$kind")" \
    "$(json_escape "$source_path")" \
    "$(json_escape "$target")" \
    "$(json_escape "$ref")")" >> "$accumulator"
}

# ---- Check 1: broken intra-KB links ---------------------------------------
# Walk every .md under knowledge-base/ (except archive/) and for each
# `](path.md...)` extract the target. Targets are interpreted relative to
# the markdown file's parent directory; existence-only check, no anchor
# (#section) traversal.
while IFS= read -r -d '' md; do
  rel_md="${md#"$REPO_ROOT/"}"
  src_dir="$(dirname "$md")"
  # POSIX-portable grep: matches the first .md target inside parens.
  # `-o` prints just the match; trailing chars after `.md` (anchors etc.)
  # are stripped via parameter expansion.
  while IFS= read -r line; do
    target="${line%%)*}"
    target="${target#*\](}"
    # Strip any #anchor or query-string from the target.
    target_clean="${target%%#*}"
    target_clean="${target_clean%% *}"
    # Skip protocol URLs (http://, mailto:, etc.) and empty targets.
    case "$target_clean" in
      ""|http://*|https://*|mailto:*|"#"*) continue ;;
    esac
    # Only .md targets are in scope for the broken-intra-KB-link check.
    case "$target_clean" in
      *.md) ;;
      *) continue ;;
    esac
    # Resolve relative to the markdown file's parent.
    case "$target_clean" in
      /*) resolved="$REPO_ROOT$target_clean" ;;
      *)  resolved="$src_dir/$target_clean" ;;
    esac
    if [[ ! -e "$resolved" ]]; then
      emit_finding "broken-link" "$rel_md" "$target_clean"
    fi
  done < <(grep -oE '\]\([^)]+\.md[^)]*\)' "$md" 2>/dev/null || true)
done < <(find "$KB_DIR" -type f -name "*.md" ! -path "*/archive/*" ! -path "*/.git/*" -print0 2>/dev/null)

# ---- Check 2: code-anchor drift ------------------------------------------
# Source files to scan: AGENTS.{core,docs,rest}.md + every learning .md.
# Pattern: `path/to/file.ext:NN` where NN is a line number. Resolve path
# relative to repo root.
declare -a anchor_sources=()
for f in "${AGENTS_FILES[@]}"; do
  [[ -f "$f" ]] && anchor_sources+=("$f")
done
if [[ -d "$LEARNINGS_DIR" ]]; then
  while IFS= read -r -d '' f; do
    anchor_sources+=("$f")
  done < <(find "$LEARNINGS_DIR" -type f -name "*.md" ! -path "*/archive/*" -print0 2>/dev/null)
fi

for src in "${anchor_sources[@]}"; do
  rel_src="${src#"$REPO_ROOT/"}"
  while IFS= read -r anchor; do
    # Strip surrounding backticks if present.
    anchor="${anchor//\`/}"
    # Split on `:` from the right — paths may contain colons only on Windows
    # which we don't support, so the last `:N` is the line number suffix.
    path="${anchor%:*}"
    line="${anchor##*:}"
    # Heuristic: require path to look file-like (contains a directory sep AND
    # an extension dot, and the line component is all-digit).
    case "$path" in
      */*) ;;
      *) continue ;;
    esac
    case "$path" in
      *.*) ;;
      *) continue ;;
    esac
    case "$line" in
      ''|*[!0-9]*) continue ;;
    esac
    # Strip leading `./` for normalization.
    path="${path#./}"
    if [[ ! -e "$REPO_ROOT/$path" ]]; then
      emit_finding "broken-anchor" "$rel_src" "$path:$line"
    fi
  done < <(grep -oE '\b[A-Za-z0-9_./@-]+\.[A-Za-z0-9]+:[0-9]+\b' "$src" 2>/dev/null || true)
done

# ---- Emit final JSON ------------------------------------------------------
printf '{"findings":['
first=1
while IFS= read -r line; do
  if (( first )); then
    first=0
  else
    printf ','
  fi
  printf '%s' "$line"
done < "$accumulator"
printf '],"counts":{"broken_link":%d,"broken_anchor":%d}}\n' "$broken_link" "$broken_anchor"
