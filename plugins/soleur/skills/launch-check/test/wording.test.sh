#!/usr/bin/env bash
# Guard 5: no banned assurance word in any static prose source; the banner is present in every report.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
BW="$SKILL/references/banned-words.txt"
check "banned list is non-empty (anti-vacuity)" test "$(grep -c . "$BW")" -ge 5
lint() { ! grep -iwFf "$BW" "$@" >/dev/null 2>&1; }   # true when clean
prose="$SCRATCH/prose.txt"
awk -F'\t' '!/^#/ && $1!="id" {print $5; print $12}' "$SKILL/references/checks.tsv" > "$prose"
check "checks.tsv titles and remedies are clean" lint "$prose"
check "banner.txt is clean" lint "$SKILL/references/banner.txt"
check "footer.txt is clean" lint "$SKILL/references/footer.txt"
check "phrases.txt is clean" lint "$SKILL/references/phrases.txt"
check "render.sh carries no banned word of its own" lint "$SKILL/scripts/lib/render.sh"
check "baseline.sh carries no banned word of its own" lint "$SKILL/scripts/lib/baseline.sh"
check "launch-check.sh carries no banned word of its own" lint "$SKILL/scripts/launch-check.sh"
check "retired-checks.tsv and baseline-domains.tsv are clean" lint "$SKILL/references/retired-checks.tsv" "$SKILL/references/baseline-domains.tsv"
check "severity-rubric.md is clean" lint "$SKILL/references/severity-rubric.md"
printf 'run npm audit\n' > "$SCRATCH/ok.txt"
check "an allowed phrase ('npm audit') is accepted" lint "$SCRATCH/ok.txt"
not() { ! "$@"; }
for w in "production-ready" "production ready" "Certified" "non-compliant" "has passed" "certification"; do
  printf 'This repo is %s today.\n' "$w" > "$SCRATCH/bad.txt"
  check "mutation: '$w' in prose is caught by the lint helper itself" not lint "$SCRATCH/bad.txt"
done
: > "$SCRATCH/emptybw.txt"; printf 'production-ready\n' > "$SCRATCH/bad2.txt"
check "mutation: an EMPTY banned list catches nothing (this is why the non-empty guard exists)" bash -c '! grep -iwFf "$1" "$2" >/dev/null 2>&1' _ "$SCRATCH/emptybw.txt" "$SCRATCH/bad2.txt"
H=$(fx_healthy wh); scan_to "$H" "$SCRATCH/h.tsv"
lc render --target "$H" --facts "$SCRATCH/h.tsv" --dry-run > "$SCRATCH/rep.out" 2>&1
M=$(fx_minimal wm); scan_to "$M" "$SCRATCH/m.tsv"; lc render --target "$M" --facts "$SCRATCH/m.tsv" --dry-run > "$SCRATCH/repm.out" 2>&1
check "a minimal-repo render (many gaps, not-assessed section) is clean" lint "$SCRATCH/repm.out"
P=$(fx_python wp); scan_to "$P" "$SCRATCH/p.tsv"; lc render --target "$P" --facts "$SCRATCH/p.tsv" --dry-run > "$SCRATCH/repp.out" 2>&1
check "a python-repo render (partial-coverage notice) is clean" lint "$SCRATCH/repp.out"
printf 'JDG-AUTH\tgap\thigh\tCI-01\n' > "$SCRATCH/jj.tsv"; lc render --target "$M" --facts "$SCRATCH/m.tsv" --judged "$SCRATCH/jj.tsv" --dry-run > "$SCRATCH/repj.out" 2>&1
check "a render with a judged gap is clean" lint "$SCRATCH/repj.out"
check "a rendered report is clean" lint "$SCRATCH/rep.out"
check "a rendered report carries the banner" grep -q "How to read this report" "$SCRATCH/rep.out"
check "render.sh has no echo/printf of sentence-length prose (all prose lives in references/)" bash -c '! grep -nE "(echo|printf) .*[A-Za-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+" "$1" | grep -vE "^[0-9]+:[[:space:]]*#"' _ "$SKILL/scripts/lib/render.sh"
finish 25
