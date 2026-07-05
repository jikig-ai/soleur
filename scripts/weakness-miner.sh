#!/usr/bin/env bash
# Read-only weakness-miner (#6037) — Self-Harness "weakness mining" stage,
# detection-only. Clusters recently-added session-failure learnings into a
# ranked recurring-failure-pattern digest for a human to triage into /compound.
#
# ZERO MUTATION SURFACE: the digest at DIGEST_PATH is the ONLY write target.
# This script never edits AGENTS.md, skills, hooks, or any other file. The
# workflow's `bot-pr-with-synthetic-checks` `add-paths` (single digest path) is
# the operative CI mutation boundary; this script's single `> "$DIGEST_PATH"`
# redirect is the runtime one.
#
# Clustering key (decided by the Phase-0.4 real-corpus spike, plan 2026-07-05):
# multi-tag CO-OCCURRENCE — learnings sharing a tag PAIR (>= 2 shared tags),
# ranked by member count (>= MIN_MEMBERS). Frontmatter `category` was rejected
# as taxonomy echo. Error-signature n-grams + an LLM theme pass are v1.1.
#
# Recency: git FIRST-APPEARANCE date (--diff-filter=A) within WINDOW_DAYS — NOT
# last-touch (a bulk lint/rename commit must not resurrect an old learning).
#
# Env overrides (also the test seams):
#   SOLEUR_WM_LEARNINGS_DIR  dir to scan            (default knowledge-base/project/learnings)
#   SOLEUR_WM_DIGEST_PATH    output digest          (default knowledge-base/project/weakness-digest.md)
#   SOLEUR_WM_WINDOW_DAYS    recency window in days (default 7)
#   SOLEUR_WM_MIN_MEMBERS    cluster threshold      (default 3)
#   SOLEUR_WM_SINCE          explicit ISO cutoff, overrides WINDOW_DAYS (test determinism)
#   SOLEUR_WM_FILES          explicit newline file list, bypasses git selection (test seam)
set -uo pipefail

LEARNINGS_DIR="${SOLEUR_WM_LEARNINGS_DIR:-knowledge-base/project/learnings}"
DIGEST_PATH="${SOLEUR_WM_DIGEST_PATH:-knowledge-base/project/weakness-digest.md}"
WINDOW_DAYS="${SOLEUR_WM_WINDOW_DAYS:-7}"
MIN_MEMBERS="${SOLEUR_WM_MIN_MEMBERS:-3}"

# Learning files first-added within the window, by git --diff-filter=A date.
select_recent_files() {
  if [[ -n "${SOLEUR_WM_FILES:-}" ]]; then
    printf '%s\n' "${SOLEUR_WM_FILES}"
    return 0
  fi
  local since="${SOLEUR_WM_SINCE:-}"
  if [[ -z "$since" ]]; then
    since="$(date -u -d "${WINDOW_DAYS} days ago" +%Y-%m-%d 2>/dev/null \
             || date -u -v-"${WINDOW_DAYS}"d +%Y-%m-%d 2>/dev/null)"
  fi
  git log --since="$since" --diff-filter=A --name-only --format= -- "$LEARNINGS_DIR" 2>/dev/null \
    | grep '\.md$' | sort -u
}

# Sorted-unique tag list from a learning's frontmatter `tags: [a, b, c]`.
tags_of() {
  awk '/^tags:/ { gsub(/^tags:[[:space:]]*\[|\][[:space:]]*$/, ""); print; exit }' "$1" \
    | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u
}

main() {
  local DELIM=$'\x1f'   # unit separator: cannot appear in a YAML frontmatter tag
  declare -A pair_count pair_paths
  local n_files=0 f key i j
  local -a tags
  # Count each co-occurring tag PAIR and the FULL PATHS (not basenames — same
  # basename in different subdirs must not collapse) of the learnings that carry it.
  while IFS= read -r f; do
    [[ -n "$f" && -f "$f" ]] || continue
    n_files=$((n_files + 1))
    mapfile -t tags < <(tags_of "$f")
    for ((i = 0; i < ${#tags[@]}; i++)); do
      for ((j = i + 1; j < ${#tags[@]}; j++)); do
        key="${tags[i]}${DELIM}${tags[j]}"   # tags[] already sorted → stable key
        pair_count["$key"]=$(( ${pair_count["$key"]:-0} + 1 ))
        pair_paths["$key"]="${pair_paths["$key"]:-}${f}"$'\n'
      done
    done
  done < <(select_recent_files)

  # Collapse every pair that describes the SAME member-set into ONE cluster, so
  # K files sharing K>=3 tags produce one heading (labelled with the shared tag
  # set), not K-choose-2 near-identical headings. Member-set identity = a hash of
  # its sorted full-path list.
  declare -A ms_tags ms_paths ms_count
  local sig a b members
  for key in "${!pair_count[@]}"; do
    [[ "${pair_count[$key]}" -ge "$MIN_MEMBERS" ]] || continue
    members="$(printf '%s' "${pair_paths[$key]}" | grep -v '^$' | sort -u)"
    sig="$(printf '%s' "$members" | sha1sum | cut -c1-16)"
    a="${key%%"${DELIM}"*}"; b="${key##*"${DELIM}"}"
    ms_tags["$sig"]="${ms_tags["$sig"]:-}${a}"$'\n'"${b}"$'\n'
    ms_paths["$sig"]="$members"
    ms_count["$sig"]="$(printf '%s\n' "$members" | grep -c .)"
  done

  # Rank distinct member-sets by size, desc.
  local ranked
  ranked="$(for sig in "${!ms_count[@]}"; do
    printf '%s\t%s\n' "${ms_count[$sig]}" "$sig"
  done | sort -rn -k1,1)"

  # The single write sink.
  {
    echo "# Weakness Digest"
    echo
    echo "_Read-only recurring-failure signal from learnings added in the last ${WINDOW_DAYS}d (#6037)."
    echo "Triage clusters into \`/compound\`; this file never edits the harness._"
    echo
    echo "Learnings in window: ${n_files}"
    echo
    if [[ -z "$ranked" ]]; then
      echo "No recurring pattern (>= ${MIN_MEMBERS} learnings sharing >= 2 tags) this window."
    else
      echo "## Recurring failure patterns"
      echo
      echo "_Clusters of learnings sharing >= 2 tags, ranked by size (>= ${MIN_MEMBERS} members)._"
      echo
      local label p
      while IFS=$'\t' read -r count sig; do
        [[ -n "$sig" ]] || continue
        label="$(printf '%s' "${ms_tags[$sig]}" | grep -v '^$' | sort -u | paste -sd '+' - | sed 's/+/ + /g')"
        echo "### ${label} — ${count} learnings"
        printf '%s\n' "${ms_paths[$sig]}" | grep -v '^$' | while IFS= read -r p; do
          echo "- $(basename "$p")"
        done
        echo
      done <<< "$ranked"
    fi
  } > "$DIGEST_PATH"
}

main "$@"
