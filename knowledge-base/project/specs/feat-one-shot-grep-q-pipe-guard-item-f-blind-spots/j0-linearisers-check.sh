#!/usr/bin/env bash
# Item F prototype check (J0c): drives j0-split.awk and j0-fence.awk on built fixtures and prints the reported lines.
# Fixture shapes are built with printf from split pieces so this script holds no literal reader shape (the sweep reads this dir).
set -u
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
B='|'; G='grep -q p'
PAT="$(bash -c 'source <(sed -n "/^OLD=/,/^NEW=/p" "'"$H"'/j0-pattern-prototype.sh"); printf "%s" "$NEW"')"
{ printf '%s\n' "a $B" "  $G f" "b || " "  $G f" "c $B" "# note" "  $G f" "d $B" "" "  $G f" "e $B" ; } > "$W/split.sh"
{ printf '%s\n' "run: $B" "  $G f" "x $B&" "  $G f" "  $B" "$G f" "ok $B" "  wc -l"; } > "$W/split2.yml"
for awk_bin in awk gawk "gawk --posix" "gawk --traditional" mawk busybox\ awk original-awk; do
  command -v "${awk_bin%% *}" >/dev/null 2>&1 || continue
  r=$($awk_bin -f "$H/j0-split.awk" "$W/split.sh" "$W/split2.yml" | grep -E -- "$PAT" | sed "s#$W/##" | tr '\n' ';')
  echo "[$awk_bin] split reports: $r"
done
printf '%s\n' "prose x $B $G" '```bash' "set -o pipefail" "x $B $G" '```' '```sh' "x $B $G" '```' '~~~' "set -euo pipefail" "y $B sudo $G" '```' "still open" '~~~' '    ```' "z $B $G" "    set -o pipefail" '    ```' '````' "set -o pipefail" "w $B $G" '```' "q $B $G" '````' "tail" '```' "u $B env -i $G" "pipefail" > "$W/doc.md"
for awk_bin in awk gawk "gawk --posix" "gawk --traditional" mawk busybox\ awk original-awk; do
  command -v "${awk_bin%% *}" >/dev/null 2>&1 || continue
  r=$($awk_bin -f "$H/j0-fence.awk" "$W/doc.md" | grep -E -- "$PAT" | sed "s#$W/##" | tr '\n' ';')
  echo "[$awk_bin] fence reports: $r"
done
