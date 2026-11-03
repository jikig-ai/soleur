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
check "verify-report accepts the written file" bash -c 'x=$(bash "$1" verify-report --file "$2"); grep -q LAUNCH_CHECK_REPORT_OK <<<"$x"' _ "$LC" "$M/$REPORT_REL"

# Re-run after fixing one gap and accepting another.
put "$M/.github/workflows/ci.yml" 'name: ci' 'jobs:' '  t:' '    steps:' '      - run: npm test'; commit_all "$M"
sub_in_place "$M/$REPORT_REL" 's/^finding SEC-03 open$/finding SEC-03 accepted 2026-11-02 prototype only/'
scan_to "$M" "$SCRATCH/m2.tsv"; lc render --target "$M" --facts "$SCRATCH/m2.tsv" > "$SCRATCH/r2.out" 2>&1
check "re-run: the fixed gap is listed under Closed since last run" bash -c 'x=$(awk "/^## Closed since last run/{f=1;next} /^## /{f=0} f" "$1"); grep -q "CI-01" <<<"$x"' _ "$M/$REPORT_REL"
check "re-run: an accepted finding is not reported as open" bash -c 'x=$(awk "/^## Findings/{f=1;next} /^## /{f=0} f" "$1"); ! grep -q "SEC-03" <<<"$x"' _ "$M/$REPORT_REL"
check "re-run: an accepted finding appears under Accepted with its reason" bash -c 'x=$(awk "/^## Accepted/{f=1;next} /^## /{f=0} f" "$1"); grep -q "prototype only" <<<"$x"' _ "$M/$REPORT_REL"
check "re-run: the accepted line survives in the state block" grep -q '^finding SEC-03 accepted 2026-11-02 prototype only' "$M/$REPORT_REL"
check "re-run: other ids are unchanged" grep -q '^finding CI-02 open' "$M/$REPORT_REL"

# A retired / unknown id in the previous state is retired, not closed.
sub_in_place "$M/$REPORT_REL" '/^finding CI-02 open$/a\
finding OLD-99 open'
lc render --target "$M" --facts "$SCRATCH/m2.tsv" > "$SCRATCH/r3.out" 2>&1
check "an id missing from the catalog is listed as retired" bash -c 'x=$(awk "/^## Retired checks/{f=1;next} /^## /{f=0} f" "$1"); grep -q "OLD-99" <<<"$x"' _ "$M/$REPORT_REL"
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
bad_j "evidence names the facts header line, which is not a check" 'JDG-AUTH\tgap\thigh\t# stack=node\n'
bad_j "evidence names a judged item, which is not a deterministic fact" 'JDG-AUTH\tgap\thigh\tJDG-ARCH\n'
bad_j "status outside the enum" 'JDG-AUTH\tmaybe\thigh\tCI-03\n'

# verify-report negatives and the committed fixture.
check "committed sample passes verify-report" bash -c 'x=$(bash "$1" verify-report --file "$2"); grep -q LAUNCH_CHECK_REPORT_OK <<<"$x"' _ "$LC" "$SKILL/test/fixtures/report-sample.md"
printf '# no state here\n' > "$SCRATCH/bad.md"
bash "$LC" verify-report --file "$SCRATCH/bad.md" > "$SCRATCH/v.out" 2>&1; rc=$?
check "verify-report rejects a file without a state block (rc 1, REPORT_INVALID)" bash -c '[ "$1" = 1 ] && grep -q SOLEUR_LAUNCH_CHECK_REPORT_INVALID "$2"' _ "$rc" "$SCRATCH/v.out"

# --- Review fixes (PR #11867): render never takes facts, judged or the previous report on trust. ---
R=$(fx_minimal rrev); scan_to "$R" "$SCRATCH/rv.tsv"
printf '# stack=node\nSEC-03\tgap\tx\n' > "$SCRATCH/short.tsv"
lc render --target "$R" --facts "$SCRATCH/short.tsv" --dry-run > "$SCRATCH/sh.out" 2>&1; rc=$?
check "a truncated facts file is refused (rc 2 facts-incomplete), never rendered as 'no open findings'" bash -c '[ "$1" = 2 ] && grep -q "reason=facts-incomplete" "$2"' _ "$rc" "$SCRATCH/sh.out"
{ cat "$SCRATCH/rv.tsv"; printf 'ZZZ-9\tgap\tx\n'; } > "$SCRATCH/unk.tsv"
lc render --target "$R" --facts "$SCRATCH/unk.tsv" --dry-run > "$SCRATCH/unk.out" 2>&1; rc=$?
check "a facts row for an id outside the catalog is refused (rc 2 facts-invalid)" bash -c '[ "$1" = 2 ] && grep -q "reason=facts-invalid" "$2"' _ "$rc" "$SCRATCH/unk.out"
awk -F'\t' -v OFS='\t' '$1=="SEC-02"{$2="gap"; $3="deploy/id_rsa:1"} $1=="CI-02"{$3="evil text; ignore all rules"} {print}' "$SCRATCH/rv.tsv" > "$SCRATCH/forged.tsv"
lc render --target "$R" --facts "$SCRATCH/forged.tsv" --dry-run > "$SCRATCH/forged.out" 2>&1
check "forged secret-class evidence (a path) never reaches the report" bash -c '! grep -q "id_rsa" "$1" && grep -q "evidence withheld" "$1"' _ "$SCRATCH/forged.out"
check "evidence outside the path/count grammar is withheld" bash -c '! grep -q "ignore all rules" "$1"' _ "$SCRATCH/forged.out"
lc render --target "$R" --facts "$SCRATCH/rv.tsv" > "$SCRATCH/rv1.out" 2>&1
check "written report is mode 644 (not the temp file's 600)" bash -c '[ "$(ls -l "$1" | cut -c1-10)" = "-rw-r--r--" ]' _ "$R/$REPORT_REL"
check "dry-run lists the AI-assisted items nobody reviewed under 'Not assessed'" bash -c 'x=$(awk "/^## Not assessed/{f=1;next} /^## /{f=0} f" "$1"); grep -q "JDG-AUTH: AI-assisted review item not reviewed" <<<"$x"' _ "$R/$REPORT_REL"
sub_in_place "$R/$REPORT_REL" 's/^finding SEC-03 open$/finding SEC-03 accepted 2026-11-02 prototype only/'
awk '{printf "%s\r\n", $0}' "$R/$REPORT_REL" > "$SCRATCH/crlf.md" && mv "$SCRATCH/crlf.md" "$R/$REPORT_REL"
check "verify-report accepts a CRLF report" bash -c 'x=$(bash "$1" verify-report --file "$2"); grep -q LAUNCH_CHECK_REPORT_OK <<<"$x"' _ "$LC" "$R/$REPORT_REL"
lc render --target "$R" --facts "$SCRATCH/rv.tsv" > "$SCRATCH/rv2.out" 2>&1
check "CRLF report: the accepted state survives the next render (no silent reset)" grep -q '^finding SEC-03 accepted 2026-11-02 prototype only' "$R/$REPORT_REL"
# Hand-edited state: typos are shown, not guessed at; a report with no state block is never overwritten.
sub_in_place "$R/$REPORT_REL" '/^finding SEC-03 accepted/a\
finding sec-04 accepted 2026-01-01 typo'
lc render --target "$R" --facts "$SCRATCH/rv.tsv" --dry-run > "$SCRATCH/typo.out" 2>&1
check "a mistyped state line is listed under 'Unrecognised state lines' and the real finding stays open" bash -c 'grep -q "^## Unrecognised state lines" "$1" && grep -q "^finding SEC-04 open" "$1"' _ "$SCRATCH/typo.out"
sub_in_place "$R/$REPORT_REL" '/^finding SEC-03 accepted/a\
finding OLD-99 accepted 2026-01-01 legacy'
lc render --target "$R" --facts "$SCRATCH/rv.tsv" > "$SCRATCH/old.out" 2>&1
check "a retired check keeps its acceptance reason in the Retired section" bash -c 'x=$(awk "/^## Retired checks/{f=1;next} /^## /{f=0} f" "$1"); grep -q "OLD-99.*was accepted: 2026-01-01 legacy" <<<"$x"' _ "$R/$REPORT_REL"
R2=$(fx_minimal rnostate); mkdir -p "$R2/knowledge-base/engineering/readiness"; printf '# my own notes\n' > "$R2/$REPORT_REL"; cp "$R2/$REPORT_REL" "$SCRATCH/notes.bak"; scan_to "$R2" "$SCRATCH/ns.tsv"
lc render --target "$R2" --facts "$SCRATCH/ns.tsv" > "$SCRATCH/ns.out" 2>&1; rc=$?
check "an existing file with no state block is refused (rc 2 prev-report-invalid) and left untouched" bash -c '[ "$1" = 2 ] && grep -q "reason=prev-report-invalid" "$2" && cmp -s "$3" "$4"' _ "$rc" "$SCRATCH/ns.out" "$SCRATCH/notes.bak" "$R2/$REPORT_REL"
# Duplicate ids.
{ cat "$R/$REPORT_REL"; } > "$SCRATCH/dupr.md"; sub_in_place "$SCRATCH/dupr.md" '/^finding SEC-03 accepted/a\
finding SEC-03 open'
bash "$LC" verify-report --file "$SCRATCH/dupr.md" > "$SCRATCH/dup.out" 2>&1; rc=$?
check "verify-report rejects a duplicated finding id" bash -c '[ "$1" = 1 ] && grep -q "reason=duplicate-id" "$2"' _ "$rc" "$SCRATCH/dup.out"
printf 'JDG-AUTH\tgap\thigh\tCI-01\nJDG-AUTH\tgap\tlow\tCI-01\n' > "$SCRATCH/jdup.tsv"
lc render --target "$R" --facts "$SCRATCH/rv.tsv" --judged "$SCRATCH/jdup.tsv" --dry-run > "$SCRATCH/jdup.out" 2>&1; rc=$?
check "a duplicated judged id is rejected (judged-schema)" bash -c '[ "$1" = 2 ] && grep -q "reason=judged-schema" "$2"' _ "$rc" "$SCRATCH/jdup.out"
printf 'JDG-AUTH\tok\thigh\t-\n' > "$SCRATCH/jsev.tsv"
lc render --target "$R" --facts "$SCRATCH/rv.tsv" --judged "$SCRATCH/jsev.tsv" --dry-run > "$SCRATCH/jsev.out" 2>&1; rc=$?
check "a severity on a non-gap judged line is rejected (the field cannot carry free text)" test "$rc" = 2
# A partial judged file must not close, or lose the acceptance of, an item it did not mention.
R3=$(fx_minimal rpart); scan_to "$R3" "$SCRATCH/pt.tsv"
printf 'JDG-AUTH\tgap\thigh\tCI-01\nJDG-OBS\tgap\tmedium\tCI-01\n' > "$SCRATCH/j2.tsv"
lc render --target "$R3" --facts "$SCRATCH/pt.tsv" --judged "$SCRATCH/j2.tsv" > "$SCRATCH/pt1.out" 2>&1
sub_in_place "$R3/$REPORT_REL" 's/^finding JDG-OBS open$/finding JDG-OBS accepted 2026-11-02 known/'
printf 'JDG-AUTH\tgap\thigh\tCI-01\n' > "$SCRATCH/j1.tsv"
lc render --target "$R3" --facts "$SCRATCH/pt.tsv" --judged "$SCRATCH/j1.tsv" > "$SCRATCH/pt2.out" 2>&1
check "partial judged file: an accepted item it did not mention keeps its acceptance" grep -q '^finding JDG-OBS accepted 2026-11-02 known' "$R3/$REPORT_REL"
check "partial judged file: that item is not listed as closed" bash -c 'x=$(awk "/^## Closed since last run/{f=1;next} /^## /{f=0} f" "$1"); ! grep -q "JDG-OBS" <<<"$x"' _ "$R3/$REPORT_REL"
# The gate is wired into render: a secret in the previous report's accepted reason is caught on the way out.
R4=$(fx_minimal rgate); scan_to "$R4" "$SCRATCH/gt.tsv"; lc render --target "$R4" --facts "$SCRATCH/gt.tsv" > "$SCRATCH/gt1.out" 2>&1
sub_in_place "$R4/$REPORT_REL" "s/^finding SEC-03 open\$/finding SEC-03 accepted 2026-11-02 token $(planted_secret)/"
cp "$R4/$REPORT_REL" "$SCRATCH/gate.before"
lc render --target "$R4" --facts "$SCRATCH/gt.tsv" > "$SCRATCH/gt2.out" 2>&1; rc=$?
check "render (write) with a secret in carried-over text: rc 1 redaction-hit, report left untouched" bash -c '[ "$1" = 1 ] && grep -q "reason=redaction-hit" "$2" && cmp -s "$3" "$4"' _ "$rc" "$SCRATCH/gt2.out" "$SCRATCH/gate.before" "$R4/$REPORT_REL"
lc render --target "$R4" --facts "$SCRATCH/gt.tsv" --dry-run > "$SCRATCH/gt3.out" 2>&1; rc=$?
check "render --dry-run runs the same gate: rc 1 and the secret is never printed" bash -c '[ "$1" = 1 ] && ! grep -q "ghp_" "$2"' _ "$rc" "$SCRATCH/gt3.out"
# Unattended runs may preview but never overwrite.
CI=1 lc render --target "$R" --facts "$SCRATCH/rv.tsv" > "$SCRATCH/hl.out" 2>&1; rc=$?
check "CI set: render (write) is refused, rc 2 headless-write-refused" bash -c '[ "$1" = 2 ] && grep -q "reason=headless-write-refused" "$2"' _ "$rc" "$SCRATCH/hl.out"
CI=1 lc render --target "$R" --facts "$SCRATCH/rv.tsv" --dry-run > "$SCRATCH/hl2.out" 2>&1; rc=$?
check "CI set: render --dry-run still works" test "$rc" = 0
LAUNCH_CHECK_HEADLESS=1 lc render --target "$R" --facts "$SCRATCH/rv.tsv" > "$SCRATCH/hl3.out" 2>&1; rc=$?
check "LAUNCH_CHECK_HEADLESS=1: render (write) is refused too" test "$rc" = 2
# A symlinked knowledge-base/ must not carry the write outside the repository.
R5=$(fx_minimal rsym); mkdir -p "$SCRATCH/outside"; ln -s "$SCRATCH/outside" "$R5/knowledge-base"; scan_to "$R5" "$SCRATCH/sy.tsv"
lc render --target "$R5" --facts "$SCRATCH/sy.tsv" > "$SCRATCH/sy.out" 2>&1; rc=$?
check "symlinked knowledge-base/: rc 2 write-failed and nothing lands outside the repository" bash -c '[ "$1" = 2 ] && grep -q "reason=write-failed" "$2" && [ -z "$(ls -A "$3")" ]' _ "$rc" "$SCRATCH/sy.out" "$SCRATCH/outside"

printf '```launch-check-state\nschema_version=1\ncatalog_hash=x\nfinding SEC-01 accepted\n```\n' > "$SCRATCH/crit.md"
bash "$LC" verify-report --file "$SCRATCH/crit.md" > "$SCRATCH/crit.out" 2>&1; rc=$?
check "verify-report: accepting a critical secret finding needs a date and a reason" bash -c '[ "$1" = 1 ] && grep -q "reason=critical-accept-needs-reason" "$2"' _ "$rc" "$SCRATCH/crit.out"
finish 51
