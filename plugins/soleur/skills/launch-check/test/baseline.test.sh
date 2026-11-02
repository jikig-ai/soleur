#!/usr/bin/env bash
# The Soleur-baseline checks are derived from guards.tsv at run time, never listed.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
command -v gitleaks >/dev/null 2>&1 || { echo "FAIL - gitleaks is required for this suite"; exit 1; }
G="$PLUGIN/skills/verification-scaffold/references/guards.tsv"
want=$(awk -F'\t' '/^#/ {next} !h && $1=="name" {for(i=1;i<=NF;i++) c[$i]=i; h=1; next} h && $c["tier"]=="v1" {print "BASE-" $c["name"]}' "$G" | sort)
check "guards.tsv has v1 rows (anti-vacuity)" test -n "$want"
H=$(fx_healthy base); scan_to "$H" "$SCRATCH/h.tsv"
got=$(awk -F'\t' '$1 ~ /^BASE-/ {print $1}' "$SCRATCH/h.tsv" | sort)
check "emitted BASE- checks equal the v1 guard names (identity, not count)" test "$got" = "$want"
check "a v2 guard is not emitted as a gap" bash -c '! grep -q "BASE-block-rm-rf" "$1"' _ "$SCRATCH/h.tsv"
check "a fixture without scaffold output has baseline gaps" test "$(fact "$SCRATCH/h.tsv" BASE-secret-scan)" = gap
# Install the guards into a copy, rescan: artifacts present -> ok, never 'satisfied'.
cp -R "$H" "$SCRATCH/base2"; bash "$PLUGIN/skills/verification-scaffold/scripts/verification-scaffold.sh" --target "$SCRATCH/base2" --headless >/dev/null 2>&1
gitq "$SCRATCH/base2" add -A; gitq "$SCRATCH/base2" -c commit.gpgsign=false commit -q -m guards 2>/dev/null
scan_to "$SCRATCH/base2" "$SCRATCH/b2.tsv"
check "after scaffolding: BASE-secret-scan is ok" test "$(fact "$SCRATCH/b2.tsv" BASE-secret-scan)" = ok
check "ok evidence says advisory/unverified, not satisfied" grep -qE '^BASE-secret-scan	ok	.*advisory/unverified' "$SCRATCH/b2.tsv"
# Mutations via an override manifest.
printf '# empty\n' > "$SCRATCH/empty.tsv"
LAUNCH_CHECK_GUARDS_TSV="$SCRATCH/empty.tsv" lc scan --target "$H" --facts "$SCRATCH/e.tsv" > "$SCRATCH/e.out" 2>&1; rc=$?
check "empty manifest: exit 2 reason=baseline-source-empty (not 0 baseline checks)" bash -c '[ "$1" = 2 ] && grep -q "reason=baseline-source-empty" "$2"' _ "$rc" "$SCRATCH/e.out"
{ cat "$G"; printf 'guard-x\tgeneric-after-extraction\thook\t-\tadvisory\tgit\t-\t.claude/hooks/guard-x.sh\tv1\n'; } > "$SCRATCH/plus.tsv"
LAUNCH_CHECK_GUARDS_TSV="$SCRATCH/plus.tsv" lc scan --target "$H" --facts "$SCRATCH/p.tsv" >/dev/null 2>&1
check "a second v1 row appended after a compliant first is emitted too" bash -c 'grep -q "^BASE-guard-x" "$1" && grep -q "^BASE-secret-scan" "$1"' _ "$SCRATCH/p.tsv"
check "no checks.tsv row duplicates a derived guard (double count)" bash -c '! grep -q "^BASE-" "$1"' _ "$SKILL/references/checks.tsv"
check "baseline.sh does not hard-code a guard name" bash -c '! grep -nE "secret-scan|commit-on-main|block-stash|orphan-test" "$1" | grep -v "^[0-9]*:[[:space:]]*#"' _ "$SKILL/scripts/lib/baseline.sh"

# Label and retirement tables stay inside the vocabulary the renderer counts, and a retired id is never reused.
check "baseline-domains.tsv uses only known domains and severities" bash -c 'x=$(awk -F"\t" "!/^#/ && \$1 != \"name\" && \$1 != \"\" && (\$2 !~ /^(security|tests-ci|tech-debt|reliability-ops)\$/ || \$3 !~ /^(critical|high|medium|low)\$/)" "$1"); [ -z "$x" ]' _ "$SKILL/references/baseline-domains.tsv"
check "no catalog id appears in retired-checks.tsv (a retired id cannot come back with a stale acceptance)" bash -c 'ids=$(awk -F"\t" "!/^#/ && \$1 != \"id\" && \$1 != \"\" {print \$1}" "$1"); ret=$(awk -F"\t" "!/^#/ && \$1 != \"id\" && \$1 != \"\" {print \$1}" "$2"); [ -z "$ret" ] || { x=$(printf "%s\n" $ids | grep -xFf <(printf "%s\n" $ret) || true); [ -z "$x" ]; }' _ "$SKILL/references/checks.tsv" "$SKILL/references/retired-checks.tsv"
G2="$SCRATCH/badlabel"; mkdir -p "$G2"
printf 'name\ttier\temits\nx-guard\tv1\tfile.txt\n' > "$G2/g.tsv"
LAUNCH_CHECK_GUARDS_TSV="$G2/g.tsv" lc scan --target "$H" --facts "$SCRATCH/gl.tsv" > "$SCRATCH/gl.out" 2>&1; rc=$?
check "a one-guard manifest derives exactly one BASE- check" bash -c '[ "$1" = 0 ] && grep -q "^BASE-x-guard" "$2"' _ "$rc" "$SCRATCH/gl.tsv"
printf 'name\ttier\ntier-less\tv1\n' > "$G2/h.tsv"
LAUNCH_CHECK_GUARDS_TSV="$G2/h.tsv" lc scan --target "$H" --facts "$SCRATCH/gh.tsv" > "$SCRATCH/gh.out" 2>&1; rc=$?
check "a manifest header that lost the emits column is malformed (not merely empty)" bash -c '[ "$1" = 2 ] && grep -q "reason=baseline-source-malformed" "$2"' _ "$rc" "$SCRATCH/gh.out"
printf 'name\ttier\temits\nbad_name\tv1\tfile.txt\n' > "$G2/i.tsv"
LAUNCH_CHECK_GUARDS_TSV="$G2/i.tsv" lc scan --target "$H" --facts "$SCRATCH/gi.tsv" > "$SCRATCH/gi.out" 2>&1; rc=$?
check "a guard name outside [A-Za-z0-9-] is refused (its BASE- id would fail verify-report)" bash -c '[ "$1" = 2 ] && grep -q "reason=baseline-source-malformed" "$2"' _ "$rc" "$SCRATCH/gi.out"
finish 16
