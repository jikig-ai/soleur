#!/usr/bin/env bash
# Item F: the markdown figures in the guard header, as one command. Counts, over the tracked .md files outside knowledge-base, the lines the widened reader
# pattern matches, split into fenced lines (a fence that holds the token pipefail, or one that does not: j0-fence-all.awk prints every fence line with a 0/1
# flag) and prose lines. The pattern is read from the guard, so it moves with it. No reader shape is written in this file (the sweep reads this directory).
set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(git -C "$H" rev-parse --show-toplevel)"; cd "$R" || exit 9
GUARD=.claude/hooks/grep-q-pipe-guard.test.sh
PAT="$(bash -c 'eval "$(sed -n "/^SWEEP_LEAD=/,/^PATTERN_V2=/p" "$1")"; printf "%s" "$PATTERN_V2"' _ "$GUARD")"
[ -n "$PAT" ] || { echo "no pattern read from the guard"; exit 9; }
mapfile -t F < <(git -c core.excludesFile=/dev/null ls-files -- '*.md' ':(exclude)knowledge-base')
echo "md files: ${#F[@]}"
all="$(git -c core.excludesFile=/dev/null grep --no-index -anE -e "$PAT" -- "${F[@]}" | grep -av -E '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
fence="$(awk -f "$H/j0-fence-all.awk" "${F[@]}")"
# fence lines are path:ln:text:flag; key the join on path:ln
keys() { cut -d: -f1,2; }
n_all=$(printf '%s\n' "$all" | grep -c . || true)
inf=0; inf_pf=0; inf_nopf=0; files_nopf=""
while IFS= read -r l; do
  [ -n "$l" ] || continue
  k="$(printf '%s' "$l" | keys)"
  row="$(printf '%s\n' "$fence" | grep -a -F -- "$k:" | head -1)"
  if [ -n "$row" ]; then
    inf=$((inf + 1))
    if [ "${row##*:}" = 1 ]; then inf_pf=$((inf_pf + 1)); else inf_nopf=$((inf_nopf + 1)); files_nopf+="${l%%:*}"$'\n'; fi
  fi
done <<<"$all"
echo "matching lines (comment lines dropped): $n_all"
echo "  inside a fence: $inf (in a fence holding pipefail: $inf_pf, in a fence without it: $inf_nopf, in $(printf '%s' "$files_nopf" | sort -u | grep -c .) files)"
echo "  prose (outside any fence): $((n_all - inf))"
