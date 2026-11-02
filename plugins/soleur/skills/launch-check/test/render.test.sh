#!/usr/bin/env bash
# Report rendering: banner, counts without a score, living-file diff, accepted/retired/closed, judged schema.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
command -v gitleaks >/dev/null 2>&1 || { echo "FAIL - gitleaks is required for this suite"; exit 1; }
REPORT_REL=$(bash "$LC" report-path)

M=$(fx_minimal rmin); scan_to "$M" "$SCRATCH/m.tsv"
lc render --target "$M" --facts "$SCRATCH/m.tsv" --dry-run > "$SCRATCH/dry.out" 2>"$SCRATCH/dry.err"; rc=$?
check "dry-run exits 0" test "$rc" = 0
check "dry-run writes nothing into the repo" test ! -e "$M/knowledge-base"
check "report opens with a title and the standing banner" bash -c 'grep -q "^# Launch check report" "$1" && grep -q "How to read this report" "$1"' _ "$SCRATCH/dry.out"
check "report has a findings table with a CI-01 row" grep -qE '^\| CI-01 \| high \|' "$SCRATCH/dry.out"
check "no single score is rendered" bash -c '! grep -qiE "score|grade|[0-9]+ ?/ ?100" "$1"' _ "$SCRATCH/dry.out"
check "state block is present with schema_version=1" bash -c 'grep -q "^schema_version=1" "$1" && grep -q "^finding CI-01 open" "$1"' _ "$SCRATCH/dry.out"

lc render --target "$M" --facts "$SCRATCH/m.tsv" > "$SCRATCH/r1.out" 2>&1; rc=$?
check "render writes the living file" test "$rc" = 0 -a -f "$M/$REPORT_REL"
check "no temp file is left in the report directory" test -z "$(find "$M/knowledge-base" -name '.launch-check.*' 2>/dev/null)"
check "verify-report accepts the written file" bash -c 'bash "$1" verify-report --file "$2" | grep -q LAUNCH_CHECK_REPORT_OK' _ "$LC" "$M/$REPORT_REL"

# Re-run after fixing one gap and accepting another.
put "$M/.github/workflows/ci.yml" 'name: ci' 'jobs:' '  t:' '    steps:' '      - run: npm test'; commit_all "$M"
sub_in_place "$M/$REPORT_REL" 's/^finding SEC-03 open$/finding SEC-03 accepted 2026-11-02 prototype only/'
scan_to "$M" "$SCRATCH/m2.tsv"; lc render --target "$M" --facts "$SCRATCH/m2.tsv" > "$SCRATCH/r2.out" 2>&1
check "re-run: the fixed gap is listed under Closed since last run" bash -c 'awk "/^## Closed since last run/{f=1;next} /^## /{f=0} f" "$1" | grep -q "CI-01"' _ "$M/$REPORT_REL"
check "re-run: an accepted finding is not reported as open" bash -c '! awk "/^## Findings/{f=1;next} /^## /{f=0} f" "$1" | grep -q "SEC-03"' _ "$M/$REPORT_REL"
check "re-run: an accepted finding appears under Accepted with its reason" bash -c 'awk "/^## Accepted/{f=1;next} /^## /{f=0} f" "$1" | grep -q "prototype only"' _ "$M/$REPORT_REL"
check "re-run: the accepted line survives in the state block" grep -q '^finding SEC-03 accepted 2026-11-02 prototype only' "$M/$REPORT_REL"
check "re-run: other ids are unchanged" grep -q '^finding CI-02 open' "$M/$REPORT_REL"

# A retired / unknown id in the previous state is retired, not closed.
sub_in_place "$M/$REPORT_REL" '/^finding CI-02 open$/a\
finding OLD-99 open'
lc render --target "$M" --facts "$SCRATCH/m2.tsv" > "$SCRATCH/r3.out" 2>&1
check "an id missing from the catalog is listed as retired" bash -c 'awk "/^## Retired checks/{f=1;next} /^## /{f=0} f" "$1" | grep -q "OLD-99"' _ "$M/$REPORT_REL"
# Catalog change notice.
sub_in_place "$M/$REPORT_REL" 's/^catalog_hash=.*/catalog_hash=deadbeef/'
lc render --target "$M" --facts "$SCRATCH/m2.tsv" > "$SCRATCH/r4.out" 2>&1
check "a changed catalog hash prints SOLEUR_LAUNCH_CHECK_CATALOG_CHANGED" grep -q 'SOLEUR_LAUNCH_CHECK_CATALOG_CHANGED' "$SCRATCH/r4.out"

# Secret-class findings: count only.
S=$(fx_secret rsec); scan_to "$S" "$SCRATCH/s.tsv"
lc render --target "$S" --facts "$SCRATCH/s.tsv" > "$SCRATCH/rs.out" 2>&1
check "secret fixture: report written" test -f "$S/$REPORT_REL"
check "secret fixture: report names SEC-01 without a location or value" bash -c 'grep -q "SEC-01" "$1" && ! grep -qE "config\.js|ghp_" "$1"' _ "$S/$REPORT_REL"

# Judged findings: closed schema.
H=$(fx_healthy rj); scan_to "$H" "$SCRATCH/j.tsv"
printf 'JDG-AUTH\tgap\thigh\tCI-03,REL-01\nJDG-OBS\tok\t-\t-\n' > "$SCRATCH/j1.tsv"
lc render --target "$H" --facts "$SCRATCH/j.tsv" --judged "$SCRATCH/j1.tsv" --dry-run > "$SCRATCH/j1.out" 2>&1; rc=$?
check "judged: a valid line is accepted and rendered with catalog text" bash -c '[ "$1" = 0 ] && grep -qE "^\| JDG-AUTH \| high \|.*Authentication and authorization model" "$2"' _ "$rc" "$SCRATCH/j1.out"
bad_j() { # bad_j <desc> <line>
  printf '%b' "$2" > "$SCRATCH/jb.tsv"
  lc render --target "$H" --facts "$SCRATCH/j.tsv" --judged "$SCRATCH/jb.tsv" --dry-run > "$SCRATCH/jb.out" 2>&1; local r=$?
  check "judged rejected: $1" bash -c '[ "$1" = 2 ] && grep -q "reason=judged-schema" "$2"' _ "$r" "$SCRATCH/jb.out"
}
bad_j "extra free-text field" 'JDG-AUTH\tgap\thigh\tCI-03\tfree text here\n'
bad_j "unknown id" 'JDG-NOPE\tgap\thigh\tCI-03\n'
bad_j "non-judged id" 'CI-01\tgap\thigh\tCI-03\n'
bad_j "severity outside the enum" 'JDG-AUTH\tgap\tcritical\tCI-03\n'
bad_j "evidence id absent from the facts" 'JDG-AUTH\tgap\thigh\tZZ-99\n'
bad_j "status outside the enum" 'JDG-AUTH\tmaybe\thigh\tCI-03\n'

# verify-report negatives and the committed fixture.
check "committed sample passes verify-report" bash -c 'bash "$1" verify-report --file "$2" | grep -q LAUNCH_CHECK_REPORT_OK' _ "$LC" "$SKILL/test/fixtures/report-sample.md"
printf '# no state here\n' > "$SCRATCH/bad.md"
bash "$LC" verify-report --file "$SCRATCH/bad.md" > "$SCRATCH/v.out" 2>&1; rc=$?
check "verify-report rejects a file without a state block (rc 1, REPORT_INVALID)" bash -c '[ "$1" = 1 ] && grep -q SOLEUR_LAUNCH_CHECK_REPORT_INVALID "$2"' _ "$rc" "$SCRATCH/v.out"
finish 28
