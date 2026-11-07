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
# --- PR-B: the issue writer (scripts/lib/issues.sh, references/issue-body.template) and the autolink shapes ---
# A missing file must FAIL (a grep over a missing file reads as clean), so every row below requires the file first.
lint_file() { [ -f "$1" ] && lint "$1"; }
ISSUES_SH="$SKILL/scripts/lib/issues.sh"; TPL="$SKILL/references/issue-body.template"
check "issues.sh exists and carries no banned word of its own" lint_file "$ISSUES_SH"
check "issue-body.template exists and is clean" lint_file "$TPL"
check "the plan-sample fixture (issue body and epic) is clean" bash -c 'for f in "$1"/issues/*.md "$1"/epic.md; do [ -f "$f" ] || exit 1; ! grep -iwFf "$2" "$f" >/dev/null 2>&1 || exit 1; done' _ "$SKILL/test/fixtures/plan-sample" "$BW"
check "issues.sh has no echo/printf of sentence-length prose (all prose lives in references/)" bash -c '[ -f "$1" ] && ! grep -nE "(echo|printf) .*[A-Za-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+ [a-z]+" "$1" | grep -vE "^[0-9]+:[[:space:]]*#"' _ "$ISSUES_SH"
check "issues.sh has no \${var//pat/repl} substitution (render.sh and checks.sh already carry some; the ban is scoped to issues.sh)" bash -c '[ -f "$1" ] && ! grep -nE "\$\{[^}]*//" "$1" | grep -vE "^[0-9]+:[[:space:]]*#"' _ "$ISSUES_SH"
# Autolink shapes outside code spans: a user mention, owner/repo#N, an issue URL, a bare #N, GH-N, a 7-40 hex run.
# autolink_hits and autolink_clean come from lib.sh (one copy)
awk -F'\t' '!/^#/ && $1!="id" {print $5; print $11; print $12}' "$SKILL/references/checks.tsv" > "$SCRATCH/prose3.txt"
check "autolink lint: checks.tsv titles, commands and remedies carry no autolink shape" autolink_clean "$SCRATCH/prose3.txt"
check "autolink lint: phrases.txt, banner.txt and footer.txt carry no autolink shape" autolink_clean "$SKILL/references/phrases.txt" "$SKILL/references/banner.txt" "$SKILL/references/footer.txt"
tpl_clean() { [ -f "$TPL" ] && autolink_clean "$TPL"; }
check "autolink lint: issue-body.template exists and carries no autolink shape" tpl_clean
printf '%s\n' 'see owner/repo#12' 'ping @someone' 'item #7' 'related GH-9' 'commit deadbeef1' 'https://example.invalid/o/r/issues/3' > "$SCRATCH/al-bad.txt"
check "autolink lint canary: each of the six shapes is caught by the lint helper itself" test "$(autolink_hits "$SCRATCH/al-bad.txt" | wc -l | tr -d ' ')" = 6
printf 'path `node_modules/@types/node/index.d.ts` only\n' > "$SCRATCH/al-ok.txt"
check "autolink lint canary: a code span is exempt (an @scope/pkg path inside backticks is not a mention)" autolink_clean "$SCRATCH/al-ok.txt"
ctl_alc() { autolink_clean "$SCRATCH/al-ok.txt" && ! autolink_clean "$SCRATCH/al-ok.txt" "$SCRATCH/no-such-file" && ! autolink_clean "$SCRATCH/no-such-file" && ! autolink_clean "$SCRATCH" && ! autolink_clean && ! autolink_clean "$SCRATCH/al-ok.txt" "$SCRATCH/al-bad.txt"; }
check "control (autolink_clean): a missing file, a directory, no argument or one bad file among good ones fails it; a clean file passes" ctl_alc
finish 36
