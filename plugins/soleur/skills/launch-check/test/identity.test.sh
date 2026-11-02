#!/usr/bin/env bash
# Finding identity is the check id: stable across renames, line shifts and repeated hits.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
K=$(fx_markers ident); scan_to "$K" "$SCRATCH/a.tsv"
gitq "$K" mv src/debt.js src/renamed.js; { printf '// extra\n'; cat "$K/src/renamed.js"; } > "$K/t" && mv "$K/t" "$K/src/renamed.js"; commit_all "$K"
scan_to "$K" "$SCRATCH/b.tsv"
check "rename + line shift: the finding keeps its id and status" test "$(fact "$SCRATCH/a.tsv" DEBT-01)" = "$(fact "$SCRATCH/b.tsv" DEBT-01)"
check "multiple hits in one file collapse to a single row" test "$(awk -F'\t' '$1=="DEBT-01"' "$SCRATCH/a.tsv" | wc -l | tr -d ' ')" = 1
M=$(fx_minimal absence); scan_to "$M" "$SCRATCH/c.tsv"
check "absence check has exactly one row" test "$(awk -F'\t' '$1=="CI-01"' "$SCRATCH/c.tsv" | wc -l | tr -d ' ')" = 1
CAT="$SKILL/references/checks.tsv"
check "catalog ids are unique" test -z "$(awk -F'\t' '!/^#/ && $1!="id" {print $1}' "$CAT" | sort | uniq -d)"
# shellcheck source=/dev/null
source "$SKILL/scripts/lib/safe-walk.sh"; source "$SKILL/scripts/lib/checks.sh"
miss=0; while IFS= read -r id; do declare -F "lc_detect_${id//-/_}" >/dev/null || { fail "detector function missing for $id"; miss=1; }; done < <(awk -F'\t' '!/^#/ && $4=="detector" {print $1}' "$CAT")
[ "$miss" = 0 ] && pass "every detector row has its lc_detect_ function"
scan_to "$(fx_healthy cov_h)" "$SCRATCH/cov_h.tsv"; scan_to "$(fx_secret cov_s)" "$SCRATCH/cov_s.tsv"; scan_to "$(fx_envfile cov_e)" "$SCRATCH/cov_e.tsv"
scan_to "$(fx_markers cov_k)" "$SCRATCH/cov_k.tsv"; scan_to "$(fx_next_nogate cov_n)" "$SCRATCH/cov_n.tsv"; scan_to "$(fx_minimal cov_m)" "$SCRATCH/cov_m.tsv"
cov=0
while IFS= read -r id; do
  oks=0; gaps=0
  for f in cov_h cov_s cov_e cov_k cov_n cov_m; do
    case "$(fact "$SCRATCH/$f.tsv" "$id")" in ok) oks=1 ;; gap) gaps=1 ;; esac
  done
  { [ "$oks" = 1 ] && [ "$gaps" = 1 ]; } || { fail "check $id lacks a positive or a negative fixture (ok=$oks gap=$gaps)"; cov=1; }
done < <(awk -F'\t' '!/^#/ && $1!="id" && $4!="judged" {print $1}' "$CAT")
[ "$cov" = 0 ] && pass "every deterministic check has one positive and one negative fixture"
finish 6
