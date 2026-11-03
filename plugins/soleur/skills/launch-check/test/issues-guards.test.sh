#!/usr/bin/env bash
# issues (1 of 2): preview, --check-plan, Guard 1 (saved-plan-only gh writes) and Guard 2 (authored bytes are scanned bytes).
# The resume and epic-section guards (3 and 4) are in issues-resume.test.sh; both source issues-common.sh, which also holds the
# interface this pair of suites assumes. Every case runs against test/gh-stub.sh (a stateful fake gh on PATH): no real gh, no network.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/issues-common.sh"
check "instrument self-test" selftest
check "the 1 s pause between writes is forced to 0 for the suite" test "$LAUNCH_CHECK_PAUSE" = 0


# ---------------------------------------------------------------- 0. the instrument itself (a recorder that cannot record proves nothing)
stub_reset acme/demo private
gh api -X POST repos/acme/demo/labels -f name=canary -f color=ededed >/dev/null 2>&1
check "recorder canary: a direct write at the stub leaves exactly one write record" test "$(n_writes)" = 1
check "recorder canary: the record carries the field values (name=canary)" test "$(cj '[.[0].fields[]|select(.k=="name")|.v]|first')" = canary
canary_cases=0
calls_reset
gh api -X GET repos/acme/demo/labels --bogus-flag >/dev/null 2>&1; rc=$?
check "stub contract: an unknown flag exits 64 and is refused (not recorded as a call)" bash -c '[ "$1" = 64 ] && [ "$2" = 0 ] && [ -s "$3" ]' _ "$rc" "$(n_calls)" "$ST/refused.log"
calls_reset
gh api -X DELETE repos/acme/demo/labels >/dev/null 2>&1; rc=$?
check "stub contract: a method outside GET/POST/PATCH exits 64" test "$rc" = 64
calls_reset
gh api -X PATCH repos/acme/demo/issues/101 -f state=closed >/dev/null 2>&1; rc=$?
check "stub contract: a PATCH carrying a state field exits 64" test "$rc" = 64
calls_reset
gh api repos/acme/demo >/dev/null 2>&1
check "stub contract: an api call with no explicit -X is logged as a violation" test -s "$ST/violations.log"
stub_reset acme/demo private; seed 101 open stub-user lc:epic,lc:launch-check ''; seed 102 open stub-user lc:launch-check ''
gh api -X POST repos/acme/demo/issues/101/sub_issues -f sub_issue_id=4000001326 >/dev/null 2>&1; rc=$?
check "stub contract: a string-typed sub_issue_id (-f) is a 422 and logged as a violation" bash -c '[ "$1" = 1 ] && [ -s "$2" ]' _ "$rc" "$ST/violations.log"
gh api -X POST repos/acme/demo/issues/101/sub_issues -F sub_issue_id=4000001326 >/dev/null 2>&1; rc=$?
check "stub contract: the integer form links the child to its parent" bash -c '[ "$1" = 0 ] && [ "$(jq "[.[]|select(.parent==101)]|length" "$2")" = 1 ]' _ "$rc" "$ST/issues.json"
stub_reset acme/demo private; for i in 1 2 3 4 5 6 7; do seed $((200 + i)) closed stub-user lc:launch-check "<!-- launch-check:gap=CI-0$i -->"; done
calls_reset
cnt=$(GH_STUB_PER_PAGE=2 gh api -X GET repos/acme/demo/issues -f labels=lc:launch-check -f state=all -f per_page=100 --paginate --jq '.[]|[.number,.state]|@tsv' 2>/dev/null | wc -l | tr -d ' ')
check "stub contract: --paginate with a forced page size serves every row across 4 pages" bash -c '[ "$1" = 7 ] && [ "$(cut -f2 "$2")" = 4 ]' _ "$cnt" "$ST/pages.log"
calls_reset
cnt=$(gh api -X GET repos/acme/demo/issues -f labels=lc:launch-check -f state=all --jq '.[]|.number' 2>/dev/null | wc -l | tr -d ' ')
check "stub contract: without --paginate only the first page is served" test "$cnt" = 7

# ---------------------------------------------------------------- 1. the library exists; source scans
check "scripts/lib/issues.sh exists" test -f "$ISS"
verbs=$(find "$SKILL/scripts" "$SKILL/references" "$SKILL/SKILL.md" -type f -exec grep -nE 'gh[[:space:]]+(issue|label|pr)([[:space:]]|$)' {} + 2>/dev/null || true)
check "no gh issue / gh label / gh pr verb anywhere in the skill (REST via gh api only)" test -z "$verbs"
jq_fn_violations() { grep -h -- '--jq' "$@" 2>/dev/null | sed -e 's/.*--jq//' | grep -oE '[a-z_][a-z_0-9]*\(' | sort -u | grep -vxE '(scan|select|test)\(' || true; }
check "every shipped --jq expression stays inside the pinned function list (scan, //, @tsv, select, test)" bash -c '[ -f "$1" ] && [ -z "$2" ] && grep -q -- "--jq" "$1"' _ "$ISS" "$(jq_fn_violations "$ISS")"
mkdir -p "$SCRATCH/scan1"; printf "x --jq 'ltrimstr(\"a\")'\n" > "$SCRATCH/scan1/jqbad.sh"
check "pinned-list canary: a function outside the list is flagged" test -n "$(jq_fn_violations "$SCRATCH/scan1/jqbad.sh")"
gh_cmd_lines() { # command-position gh invocations (not 'command -v gh'), each with the function that holds it
  awk 'FNR == 1 { fn = "" } /^[a-zA-Z_][a-zA-Z_0-9]*\(\) *\{/ { fn = $1 } /^[[:space:]]*#/ { next }
       /(^|[[:space:]|;&(])gh[[:space:]]+("|\$|-|api|auth|repo)/ && !/command -v gh/ { print FILENAME ":" fn }' "$@"
}
others=$(gh_cmd_lines "$SKILL"/scripts/*.sh "$SKILL"/scripts/lib/*.sh | grep -v 'lc__gh_exec' || true)
check "gh is invoked only inside lc__gh_exec, and it is invoked there (anti-vacuous)" bash -c '[ -f "$1" ] && [ -z "$2" ] && [ -n "$3" ]' _ "$ISS" "$others" "$(gh_cmd_lines "$ISS")"
{ cat "$ISS" 2>/dev/null; printf '\nlc_extra() {\n  gh api -X POST repos/o/r/issues -f title=x\n}\n'; } > "$SCRATCH/scan1/issues.sh"
check "mutation (Guard 1 row 5): a second gh call site outside lc__gh_exec is caught by the scan" bash -c '[ -f "$1" ] && [ -n "$2" ]' _ "$ISS" "$(gh_cmd_lines "$SCRATCH/scan1/issues.sh" | grep -v lc__gh_exec || true)"
subst_hits() { grep -nE '\$\{[^}]*//' "$@" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' || true; }
check "issues.sh contains no \${var//pat/repl} substitution (& is special in a replacement)" bash -c '[ -f "$1" ] && [ -z "$2" ]' _ "$ISS" "$(subst_hits "$ISS")"
printf 'x=${y//a/b}\n' > "$SCRATCH/scan1/sub.sh"
check "mutation (Guard 2 row 7): introducing a substitution is caught by the scan" test -n "$(subst_hits "$SCRATCH/scan1/sub.sh")"
leak=$(grep -nE 'SOLEUR_LAUNCH_CHECK_(ISSUES|PLAN_OK)' "$PLUGIN"/skills/*/scripts/*.sh 2>/dev/null || true)
check "no skills/*/scripts/*.sh emits an ISSUES or PLAN_OK marker (they live in scripts/lib/issues.sh, outside the drift guard's walk)" bash -c '[ -f "$1" ] && [ -z "$2" ] && grep -q "SOLEUR_LAUNCH_CHECK_ISSUES" "$1"' _ "$ISS" "$leak"
hdr=$(sed -n '1,80p' "$LC")
miss=""; for r in headless-write-refused report-missing report-stale plan-missing plan-invalid plan-repo-mismatch confirm-public-required redaction-hit epic-closed epic-ambiguous issues-unavailable write-shape-refused issues-incomplete; do case "$hdr" in *"$r"*) ;; *) miss="$miss $r" ;; esac; done
check "launch-check.sh header lists every abort reason (the exit-code table)" test -z "$miss"
check "the issue template exists and passes the autolink lint" file_and_clean "$SKILL/references/issue-body.template"
check "the sample plan's issue body passes the autolink lint" file_and_clean "$SAMPLE/issues/CI-01.md"
check "the sample epic.md carries the epic, begin and end markers exactly once each" bash -c '[ "$(grep -c "launch-check:epic" "$1")" = 1 ] && [ "$(grep -c "launch-check:begin" "$1")" = 1 ] && [ "$(grep -c "launch-check:end" "$1")" = 1 ]' _ "$SAMPLE/epic.md"

# ---------------------------------------------------------------- 2. fixtures: one rendered report, copied per case
check "fixture: the base report is written and verifies" bash -c 'x=$(bash "$1" verify-report --file "$2"); grep -q REPORT_OK <<<"$x"' _ "$LC" "$BASE/$REPORT_REL"

# ---------------------------------------------------------------- 3. --check-plan (parse-only: no network, no scanner, no jq)
calls_reset
runi chk --check-plan --plan "$SAMPLE"
check "check-plan: the committed sample prints SOLEUR_LAUNCH_CHECK_PLAN_OK on stdout (rc 0)" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_PLAN_OK" "$2"' _ "$RC" "$OUT"
check "check-plan: makes no gh call of any kind" test "$(n_calls)" = 0
MINBIN="$SCRATCH/minbin"; mkdir -p "$MINBIN"
for t in bash sh awk sed cat tr cut head tail sort uniq wc grep find ls cp mv rm mkdir mktemp cmp comm date dirname basename readlink realpath stat id env printf chmod od sleep diff expr uname touch tee git seq timeout xargs; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -sf "$p" "$MINBIN/$t"
done
check "the minimal PATH really has no gh, jq or gitleaks" bash -c '! PATH="$1" command -v gh >/dev/null && ! PATH="$1" command -v jq >/dev/null && ! PATH="$1" command -v gitleaks >/dev/null' _ "$MINBIN"
env -i PATH="$MINBIN" HOME=/tmp bash "$LC" issues --check-plan --plan "$SAMPLE" > "$SCRATCH/chk2.out" 2>/dev/null; rc=$?
check "check-plan: also passes under env -i with no gh, jq or gitleaks (the discoverability probe; stdout only)" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_PLAN_OK" "$2"' _ "$rc" "$SCRATCH/chk2.out"
chkmut() { local d="$SCRATCH/cm.$1"; cp -R "$SAMPLE" "$d"; "$2" "$d"; runi "chk.$1" --check-plan --plan "$d"; }
m_badid() { T="../CI-01" awk -F'\t' -v OFS='\t' 'NF == 6 && $1 != "id" && !d { $1 = ENVIRON["T"]; d = 1 } { print }' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
m_symlink() { rm -f "$1/issues/CI-01.md"; ln -s /etc/hostname "$1/issues/CI-01.md"; }
m_big() { head -c 70000 /dev/zero | tr '\0' a >> "$1/issues/CI-01.md"; }
m_twomark() { printf '<!-- launch-check:gap=CI-02 -->\n' >> "$1/issues/CI-01.md"; }
m_nomark() { sed '1d' "$1/issues/CI-01.md" > "$1/n.new" && mv "$1/n.new" "$1/issues/CI-01.md"; }
m_badrepo() { sed 's#^repo=.*#repo=acme/../evil#' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
m_extra() { printf 'x\n' > "$1/issues/EXTRA-01.md"; }
for m in badid symlink big twomark nomark badrepo extra; do
  calls_reset; chkmut "$m" "m_$m"
  check "check-plan rejects a hand-edited plan ($m): plan-invalid on stdout, rc 2, zero gh calls" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ABORT reason=plan-invalid" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ]' _ "$OUT" "$RC" "$(n_calls)"
done
runi plm --create --target "$BASE" --facts "$FACTS" --judged "$JUD" --plan "$SCRATCH/no-such-plan" --confirm-repo acme/demo --confirm-count 1
check "plan-missing: a vanished plan directory aborts with the recovery sentence (scan, render, preview)" grep -qi "preview" "$OUT"
check "plan-missing: abort marker and exit code" abort_is 2 plan-missing

# ---------------------------------------------------------------- 4. preview
newcase; only_first "$R" 3; calls_reset; prev
check "preview: exit 0 and the ISSUES_PLAN marker with create=3 for 3 open gaps" bash -c '[ "$1" = 0 ] && [ "$2" = 3 ]' _ "$RC" "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN create)"
check "preview: the plan directory exists with mode 700 and holds three create rows" bash -c '[ "$1" = 3 ]' _ "$(plan_n)"
check "preview: the plan directory mode is 700" mode700 "$PLAN"
check "preview: zero write records (it never writes to the tracker)" test "$(n_writes)" = 0
check "preview: names the repo and its visibility" bash -c 'grep -q "acme/demo" "$1" && grep -qi "private" "$1"' _ "$OUT"
check "preview: prints the full ID | severity | title table for every item to file" table_rows_present "$OUT" "$PLAN/plan.tsv"
check "preview: prints the cap rule and the exact create command with both confirm flags" bash -c 'grep -q "at most 30" "$1" && grep -q -- "--create" "$1" && grep -q -- "--confirm-repo acme/demo" "$1" && grep -q -- "--confirm-count 3" "$1"' _ "$OUT"
check "preview: every printed line is one scrubbed line (no tab or carriage return)" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES_PLAN" "$1" && ! grep -q "$(printf "\t")" "$1" && ! grep -q "$(printf "\r")" "$1"' _ "$OUT"
check "preview: plan.tsv records repo, host, visibility, catalog_hash, report_hash and created" bash -c 'for k in repo host visibility catalog_hash report_hash created; do grep -q "^$k=" "$1" || exit 1; done' _ "$PLAN/plan.tsv"
GOODPLAN="$PLAN"
newcase; rm -f "$R/$REPORT_REL"; prev
check "preview: no written report aborts report-missing (rc 2)" abort_is 2 report-missing
check "preview: report-missing writes no plan" bash -c '[ -z "$(ls -A "$1" 2>/dev/null)" ]' _ "$SCRATCH/po$N"
newcase; sed 's/^catalog_hash=.*/catalog_hash=deadbeef/' "$R/$REPORT_REL" > "$R/r.new" && mv "$R/r.new" "$R/$REPORT_REL"; prev
check "preview: a report from another catalog aborts report-stale (rc 2)" abort_is 2 report-stale
HB=$(fx_healthy hbase); gitq "$HB" remote add origin https://github.com/acme/demo.git
HF="$SCRATCH/hf.tsv"; scan_to "$HB" "$HF"; lc render --target "$HB" --facts "$HF" --judged "$JUD" > "$SCRATCH/hb.render" 2>&1
gitq "$HB" rm -q .github/workflows/ci.yml; gitq "$HB" -c commit.gpgsign=false commit -q -m drop-ci; scan_to "$HB" "$HF"
stub_reset acme/demo private
runi pvst --preview --target "$HB" --facts "$HF" --judged "$JUD" --plan-out "$SCRATCH/pohb"
check "preview: facts rescanned after the report was rendered (a new gap the report lacks) aborts report-stale" abort_is 2 report-stale
newcase; stub_reset acme/demo public; only_first "$R" 3; prev
check "preview: a PUBLIC repo prints a warning and the --confirm-public command line" bash -c 'grep -qi "public" "$1" && grep -q -- "--confirm-public" "$1" && [ "$2" = PUBLIC ]' _ "$OUT" "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN visibility)"
newcase; stub_reset acme/demo private true; only_first "$R" 3; prev
check "preview: a fork names the resolved owner/name and the fork flag" bash -c 'grep -q "acme/demo" "$1" && grep -qi "fork" "$1"' _ "$OUT"
newcase; stub_reset other/thing private; only_first "$R" 3; prev
check "preview: a resolved slug that differs from origin's aborts repo-unresolved unless --repo is passed" abort_is 2 repo-unresolved
prev --repo other/thing
check "preview: --repo <slug> accepts the explicit target" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES_PLAN" "$2"' _ "$RC" "$OUT"

# preflight failures: report-only on preview (exit 0, no plan), issues-unavailable on create
pre_case() { # pre_case <label> <cause> <setup-fn>
  newcase; only_first "$R" 3; "$3"; prev
  check "preview preflight ($1): mode=report-only reason=$2, exit 0, no plan, zero writes" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES mode=report-only reason=$2" "$3" && [ -z "$(ls -A "$4" 2>/dev/null)" ] && [ "$5" = 0 ]' _ "$RC" "$2" "$OUT" "$SCRATCH/po$N" "$(n_writes)"
}
s_unauth() { export GH_STUB_AUTH=fail; }
s_unres() { export GH_STUB_REPO=unresolved; }
s_ambig() { export GH_STUB_REPO=ambiguous; }
s_noissues() { jq '.has_issues=false' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; }
s_archived() { jq '.archived=true' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; }
s_nopush() { jq '.permissions.push=false' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; }
pre_case "unauthenticated" gh-unauthenticated s_unauth; unset GH_STUB_AUTH
pre_case "repo unresolved" repo-unresolved s_unres; unset GH_STUB_REPO
pre_case "multiple remotes, no TTY" repo-unresolved s_ambig; unset GH_STUB_REPO
pre_case "issues disabled" issues-disabled s_noissues
pre_case "archived" repo-archived s_archived
pre_case "no push permission" no-write-permission s_nopush
NOGH="$SCRATCH/nogh"; mkdir -p "$NOGH"; for t in "$MINBIN"/*; do ln -sf "$(readlink "$t")" "$NOGH/$(basename "$t")"; done
ln -sf "$(command -v jq)" "$NOGH/jq"; ln -sf "$(command -v gitleaks)" "$NOGH/gitleaks"
newcase; only_first "$R" 3; OUT="$SCRATCH/pvnogh.out"
PATH="$NOGH" lcs issues --preview --target "$R" --facts "$FACTS" --judged "$JUD" --plan-out "$SCRATCH/po-nogh" > "$OUT" 2>&1; RC=$?
check "preview preflight (gh missing): mode=report-only reason=gh-missing, exit 0" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES mode=report-only reason=gh-missing" "$2"' _ "$RC" "$OUT"
newcase; only_first "$R" 3; prev; s_unauth; calls_reset; create; unset GH_STUB_AUTH
check "create preflight: an unusable environment writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "create preflight: aborts issues-unavailable (rc 2)" abort_is 2 issues-unavailable

# the 30-issue cap, with a synthesized 45-guard manifest so there are more than 35 gaps to file
BIGG="$SCRATCH/big-guards.tsv"; { printf 'name\ttier\temits\n'; for i in $(seq 1 45); do printf 'bg%02d\tv1\tnever-present-%02d.txt\n' "$i" "$i"; done; } > "$BIGG"
export LAUNCH_CHECK_GUARDS_TSV="$BIGG"
BIGB=$(fx_minimal bigbase); gitq "$BIGB" remote add origin https://github.com/acme/demo.git
BIGF="$SCRATCH/bigf.tsv"; scan_to "$BIGB" "$BIGF"; lc render --target "$BIGB" --facts "$BIGF" --judged "$JUD" > "$SCRATCH/big.render" 2>&1
cap_case() { N=$((N + 1)); R="$SCRATCH/case$N"; cp -R "$BIGB" "$R"; stub_reset acme/demo private; only_first "$R" "$1"; FACTS="$BIGF" prev "${@:2}"; FACTS="$SCRATCH/facts.tsv"; }
cap_case 35
check "cap: 35 open gaps -> create=30 capped=5 in the marker and the plan, and the cap line is printed" bash -c '[ "$1" = 30 ] && [ "$2" = 5 ] && [ "$3" = 30 ] && grep -q "at most 30" "$4"' _ "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN create)" "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN capped)" "$(plan_n)" "$OUT"
# only_first edits the state block, not the table: the oracle keeps the table rows whose id is still open in the state block
open_now=$(awk '/^```launch-check-state$/ {f=1} /^```$/ && f {f=0} f && /^finding [A-Z]+-[A-Za-z0-9-]+ open$/ {printf " %s", $2}' "$R/$REPORT_REL")
expect_capped=$(awk -F' [|] ' -v open="$open_now " '/^\| [A-Z]+-[A-Za-z0-9-]+ [|] (critical|high|medium|low) [|]/ { id = substr($1, 3); if (index(open, " " id " ") == 0) next; s = $2; r = (s=="critical")?1:(s=="high")?2:(s=="medium")?3:4; print r "\t" id }' "$R/$REPORT_REL" | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 | tail -n 5 | cut -f2 | LC_ALL=C sort | tr '\n' ' ')
got_capped=$(awk -F'\t' 'NF == 6 && $1 != "id" && $5 == "capped" {print $1}' "$PLAN/plan.tsv" | LC_ALL=C sort | tr '\n' ' ')
check "cap: the capped ids are the last five by severity rank then id (independent oracle from the report table)" bash -c '[ -n "$1" ] && [ "$1" = "$2" ]' _ "$expect_capped" "$got_capped"

cap_case 30
check "cap: exactly 30 open gaps -> create=30 capped=0" bash -c '[ "$1" = 30 ] && [ "$2" = 0 ]' _ "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN create)" "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN capped)"
cap_case 31
check "cap: exactly 31 open gaps -> create=30 capped=1" bash -c '[ "$1" = 30 ] && [ "$2" = 1 ]' _ "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN create)" "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN capped)"
cap_case 35 --exclude-domain tech-debt --exclude-class baseline
check "excludes: --exclude-domain and --exclude-class remove items from the plan (excluded>0, no create row in an excluded domain or class)" bash -c '[ "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN excluded)" -gt 0 ] && [ -z "$(awk -F"\t" "NF==6 && \$5==\"create\" && (\$3==\"tech-debt\" || \$4==\"baseline\")" "$2")" ]' _ "$OUT" "$PLAN/plan.tsv"
cap_case 35 --exclude-domain not-a-domain
check "excludes: an unknown domain is a usage error that names the flag (closed vocabulary)" bash -c 'grep -qi "exclude" "$1"' _ "$OUT"; check "excludes: ... with the usage marker" abort_is 2 usage
unset LAUNCH_CHECK_GUARDS_TSV

# ---------------------------------------------------------------- 5. Guard 1: saved-plan-only gh writes
newcase; only_first "$R" 3; prev; calls_reset
runi g1a --create --target "$R" --facts "$FACTS" --judged "$JUD" --confirm-repo acme/demo --confirm-count 3
check "G1.1: --create with no --plan makes zero recorded calls" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"
check "G1.1: --create with no --plan aborts usage (rc 2) and names --plan" bash -c 'grep -q -- "--plan" "$1"' _ "$OUT"; check "G1.1: ... with the usage marker" abort_is 2 usage
calls_reset; create --dry-run
check "G1.2: --create --dry-run records zero writes (reads allowed)" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G1.2: --create --dry-run exits 0 and says it is a dry run" bash -c '[ "$1" = 0 ] && grep -qi "dry" "$2"' _ "$RC" "$OUT"
calls_reset; with CI=1 -- create; canary_cases=$((canary_cases + 1))
check "G1.3: CI=1 -> zero calls of any kind (not even reads)" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"
check "G1.3: CI=1 -> headless-write-refused, rc 2" abort_is 2 headless-write-refused
calls_reset; with LAUNCH_CHECK_HEADLESS=1 -- create; canary_cases=$((canary_cases + 1))
check "G1.3: LAUNCH_CHECK_HEADLESS=1 -> zero calls of any kind" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"
check "G1.3: LAUNCH_CHECK_HEADLESS=1 -> headless-write-refused, rc 2" abort_is 2 headless-write-refused
check "G1.3: both headless cases ran (canary-count floor: dropping a case fails here)" test "$canary_cases" -ge 2
calls_reset; with CI=1 -- runi g1h --preview --target "$R" --facts "$FACTS" --judged "$JUD" --plan-out "$SCRATCH/po-ci" --dry-run
check "G1.3: preview --dry-run is allowed headless (like render --dry-run)" bash -c 'grep -qE "^SOLEUR_LAUNCH_CHECK_ISSUES_PLAN|mode=report-only" "$1"' _ "$OUT"

probe() { # probe <skill-root> <inject-file|-> <env-assignments> <command...>: call a library function directly; stub state in $ST
  local root=$1 inject=$2 envs=$3; shift 3
  # shellcheck disable=SC2086  # $envs is deliberately split into NAME=value words
  env $envs SKILL_DIR="$root" PLUGIN_DIR="$PLUGIN" LIBDIR="$root/scripts/lib" INJECT="$inject" WORK="$SCRATCH/probe-work" TARGET="${R:-$BASE}" \
    ISSUES_REPO=acme/demo ISSUES_PLAN_DIR="${PLAN:-$SCRATCH}" bash -c '
      set +e; mkdir -p "$WORK"
      for f in common safe-walk checks baseline redact-gate render issues; do source "$LIBDIR/$f.sh" 2>/dev/null; done
      [ "$INJECT" = - ] || source "$INJECT"
      declare -F lc_gh_write >/dev/null || { echo PROBE_NO_FUNCTION; exit 99; }
      "$@"' _ "$@" > "$SCRATCH/probe.out" 2>&1
  PRC=$?
}
stub_reset acme/demo private
probe "$SKILL" - "CI=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=probe -f color=ededed
check "G1.4: lc_gh_write called directly under CI=1 aborts headless-write-refused (rc 2) and reaches nothing" bash -c '[ "$1" = 2 ] && grep -q "reason=headless-write-refused" "$2" && [ "$3" = 0 ]' _ "$PRC" "$SCRATCH/probe.out" "$(n_calls)"
probe "$SKILL" - "LC_DRY=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=probe -f color=ededed
check "G1.4: lc_gh_write called directly under LC_DRY=1 returns 0 and reaches nothing (the function exists)" bash -c '[ "$1" = 0 ] && [ "$2" = 0 ]' _ "$PRC" "$(n_calls)"
probe "$SKILL" - "X=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=probe -f color=ededed
check "G1.4 twin: the same compliant call with neither switch reaches the stub exactly once" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
shape() { # shape <desc> <args...>: a call outside the four allowlisted shapes
  local d=$1; shift; calls_reset; probe "$SKILL" - "X=1" lc_gh_write "$@"
  check "G1.7: $d -> write-shape-refused, rc 2, nothing recorded and nothing refused by the stub" bash -c 'grep -q "reason=write-shape-refused" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ] && [ ! -s "$4" ]' _ "$SCRATCH/probe.out" "$PRC" "$(n_calls)" "$ST/refused.log"
  SEEN_REASONS="$SEEN_REASONS write-shape-refused"
}
shape "-X DELETE" api -X DELETE repos/acme/demo/issues/101
shape "a labels PATCH" api -X PATCH repos/acme/demo/labels -f name=x
shape "a different slug" api -X POST repos/evil/other/issues -f title=x
shape "state on the PATCH shape" api -X PATCH repos/acme/demo/issues/101 -f state=closed
shape "an @file operand outside the plan directory" api -X PATCH repos/acme/demo/issues/101 -F body=@/etc/hostname
shape "a non-digit issue number" api -X PATCH repos/acme/demo/issues/10x -f title=x
shape "an issue verb form" issue create --title x
calls_reset; probe "$SKILL" - "X=1" lc_gh_read api repos/acme/demo/issues -f labels=lc:launch-check -f state=all
check "G1.8: a read-helper call with -f and no -X GET never reaches the stub as an implicit method (injected or refused)" bash -c '[ ! -s "$1" ] && [ "$(jq -sr "[.[]|select(.explicit_method|not)]|length" "$2" 2>/dev/null || echo 0)" = 0 ]' _ "$ST/violations.log" "$ST/calls.log"
check "G1.8: and any call that did get through is a GET" bash -c '[ "$(jq -sr "[.[]|select(.method!=\"GET\")]|length" "$1" 2>/dev/null || echo 0)" = 0 ]' _ "$ST/calls.log"
calls_reset; probe "$SKILL" - "X=1" lc_gh_read api -X POST repos/acme/demo/labels -f name=x
check "G1.8: lc_gh_read refuses a non-GET method (no write record, non-zero rc, the function exists)" bash -c '[ "$1" = 0 ] && [ "$2" != 0 ] && [ "$2" != 99 ]' _ "$(n_writes)" "$PRC"

newcase; only_first "$R" 3; prev; GP="$PLAN"
[ -d "$GP" ] && sed 's#^repo=.*#repo=other/thing#' "$GP/plan.tsv" > "$GP/p.new" && mv "$GP/p.new" "$GP/plan.tsv"
calls_reset; CREPO=other/thing create; unset CREPO
check "G1.6: a hand-edited plan repo= (resolved repo differs) writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G1.6: a hand-edited plan repo= aborts plan-repo-mismatch (rc 2)" abort_is 2 plan-repo-mismatch
newcase; only_first "$R" 3; prev; stub_reset third/party private; calls_reset; create
check "G1.6: executing the plan from a checkout whose resolved repo differs writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G1.6: that second form aborts plan-repo-mismatch (rc 2)" abort_is 2 plan-repo-mismatch
newcase; only_first "$R" 3; prev
conf() { calls_reset; runi "cf$N.$1" --create --target "$R" --facts "$FACTS" --judged "$JUD" --plan "$PLAN" "${@:2}"; }
conf wrongrepo --confirm-repo acme/other --confirm-count 3
check "G1.10: a wrong --confirm-repo makes zero calls" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"; check "G1.10: a wrong --confirm-repo aborts usage and names the confirm flags" bash -c 'grep -qi "confirm" "$1"' _ "$OUT"; check "G1.10: ... with the usage marker (wrong --confirm-repo)" abort_is 2 usage
conf wrongcount --confirm-repo acme/demo --confirm-count 4
check "G1.10: a wrong --confirm-count makes zero calls" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"; check "G1.10: a wrong --confirm-count aborts usage and names the confirm flags" bash -c 'grep -qi "confirm" "$1"' _ "$OUT"; check "G1.10: ... with the usage marker (wrong --confirm-count)" abort_is 2 usage
conf norepo --confirm-count 3
check "G1.10: a missing --confirm-repo makes zero calls" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"; check "G1.10: a missing --confirm-repo aborts usage and names the confirm flags" bash -c 'grep -qi "confirm" "$1"' _ "$OUT"; check "G1.10: ... with the usage marker (missing --confirm-repo)" abort_is 2 usage
conf nocount --confirm-repo acme/demo
check "G1.10: a missing --confirm-count makes zero calls" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"; check "G1.10: a missing --confirm-count aborts usage and names the confirm flags" bash -c 'grep -qi "confirm" "$1"' _ "$OUT"; check "G1.10: ... with the usage marker (missing --confirm-count)" abort_is 2 usage
prev_create() { prev; create; }
newcase; only_first "$R" 3; calls_reset
with GH_HOST=evil.example GH_REPO=other/repo GH_DEBUG=api HTTPS_PROXY=http://proxy.invalid:3128 GH_CONFIG_DIR="$SCRATCH/cfg" -- prev_create
check "G1.9: the run completed against the stub (anti-vacuous: calls and writes were recorded)" bash -c '[ "$1" -gt 3 ] && [ "$2" -gt 0 ]' _ "$(n_calls)" "$(n_writes)"
check "G1.9: no recorded call carries GH_HOST, GH_REPO, GH_DEBUG, GH_CONFIG_DIR or a proxy variable (and there are recorded calls)" bash -c '[ "$1" -gt 0 ] && [ "$2" = 0 ]' _ "$(n_calls)" "$(cj '[.[]|select(.env != {})]|length')"
check "G1.9: after the slug is resolved no call runs with the customer repository as its working directory" bash -c '[ -s "$3" ] && [ "$(jq -sr --arg r "$1" "[.[]|select(.class!=\"repo\" and .class!=\"auth\")|select(.cwd|startswith(\$r))]|length" "$3")" = 0 ]' _ "$R" x "$ST/calls.log"
newcase; only_first "$R" 3; prev; [ -d "$PLAN" ] && sed 's/^host=.*/host=ghe.example/' "$PLAN/plan.tsv" > "$PLAN/p.new" && mv "$PLAN/p.new" "$PLAN/plan.tsv"; calls_reset; create
check "G1.9: a plan for a non-github.com host is refused without --host (rc 2, an ABORT marker naming the host, zero writes)" bash -c '[ "$1" = 2 ] && [ "$2" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ABORT" "$3" && grep -qi "host" "$3"' _ "$RC" "$(n_writes)" "$OUT"
calls_reset; create --host ghe.example
check "G1.9: --host ghe.example makes the same plan runnable and the host reaches a call (hostname flag or GH_HOST)" bash -c '[ "$(jq -sr "[.[]|select(.hostname==\"ghe.example\" or .env.GH_HOST==\"ghe.example\")]|length>0" "$1" 2>/dev/null)" = true ]' _ "$ST/calls.log"

# ---------------------------------------------------------------- 6. Guard 2: authored bytes are scanned bytes
check "sandbox: the pristine copy parses and has the seams injected" bash -c 'bash -n "$1" && grep -q LC_TEST_NOGATE "$1"' _ "$SB0"
# Guard 1 mutation battery: each edit removes one check from the wrapper in a sandbox copy; the matching direct-call row above must
# then see the write reach the stub (otherwise that row could not fail).
sbx_lib() { local r; r=$(mk_sbx "$1"); dirname "$(dirname "$r")"; }   # -> the sandbox skill root
sbx_edit() { # sbx_edit <name> <sed expression>: prints the sandbox skill root, with issues.sh edited
  local root; root=$(sbx_lib "$1"); sed -e "$2" "$root/scripts/lib/issues.sh" > "$root/scripts/lib/issues.sh.new" && mv "$root/scripts/lib/issues.sh.new" "$root/scripts/lib/issues.sh"; printf '%s' "$root"
}
mut_landed() { bash -n "$1/scripts/lib/issues.sh" && ! cmp -s "$1/scripts/lib/issues.sh" "$ISS"; }
M1=$(sbx_edit nohead '/if lc_is_headless; then lc_abort headless-write-refused/d')
check "G1 mutation landed (headless check removed from lc_gh_write in the sandbox copy)" mut_landed "$M1"
stub_reset acme/demo private; probe "$M1" - "CI=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=probe -f color=ededed
check "G1 mutation (headless check removed): the CI=1 call now reaches the stub, so the G1.4 row is sensitive" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
M2=$(sbx_edit nodry '/\[ "\${LC_DRY:-0}" = 1 \] && return 0/d')
check "G1 mutation landed (dry-run check removed from lc_gh_write in the sandbox copy)" mut_landed "$M2"
stub_reset acme/demo private; probe "$M2" - "LC_DRY=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=probe -f color=ededed
check "G1 mutation (dry-run check removed): the LC_DRY=1 call now reaches the stub, so the G1.4 dry-run row is sensitive" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
M3=$(sbx_edit nofile 's/lc__file_ok "${val#@}" || lc__refuse file-operand/:/')
check "G1 mutation landed (@file confinement removed from the sandbox copy)" mut_landed "$M3"
stub_reset acme/demo private; seed 101 open stub-user lc:launch-check ''; calls_reset
probe "$M3" - "X=1" lc_gh_write api -X PATCH repos/acme/demo/issues/101 -F body=@/etc/hostname
check "G1 mutation (@file confinement removed): an operand outside the plan directory now reaches the stub, so the G1.7 row is sensitive" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
M4=$(sbx_edit nokeys 's/case "$allowed" in \*" $key "\*) ;; \*) lc__refuse field-key ;; esac/:/')
check "G1 mutation landed (field-key allowlist removed from the sandbox copy)" mut_landed "$M4"
stub_reset acme/demo private; seed 101 open stub-user lc:launch-check ''; calls_reset
probe "$M4" - "X=1" lc_gh_write api -X PATCH repos/acme/demo/issues/101 -f state=closed
check "G1 mutation (field-key allowlist removed): a state field now reaches the stub (which refuses it), so the G1.7 row is sensitive" bash -c '[ "$1" = 64 ] && [ -s "$2" ]' _ "$PRC" "$ST/refused.log"
hostile_facts() { # hostile_facts <out> <evidence>: the first non-count-only gap gets the evidence; prints its id
  local id; id=$(awk -F'\t' '$2 == "gap" && $1 !~ /^SEC-0[12]$/ {print $1; exit}' "$FACTS")
  awk -F'\t' -v OFS='\t' -v id="$id" -v ev="$2" '$1 == id { $3 = ev } { print }' "$FACTS" > "$1"; printf '%s' "$id"
}
OFACTS="$FACTS"
newcase; HID=$(hostile_facts "$SCRATCH/hostile.tsv" "$(planted_secret)"); only_ids "$R" "$HID"
FACTS="$SCRATCH/hostile.tsv"; with LC_TEST_NOGATE=1 -- prev; calls_reset
check "G2 setup: with the gate bypassed in preview the plan really carries the planted token (a suite with no plant asserts nothing)" bash -c '[ -n "$2" ] && tree_has "$1" "$2"' _ "$(planted_secret)" "$PLAN"
create
check "G2.1: a plan carrying a secret-shaped string writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G2.1: ... and aborts redaction-hit with rc 1" abort_is 1 redaction-hit
check "G2.1: the token itself is nowhere in the run's output" lacks "$(planted_secret)"
calls_reset; with LC_TEST_NOGATE=1 -- create
check "G2.2 mutation: with the gate call removed from create the tamper row writes to the tracker (so row 1 is sensitive)" bash -c '[ "$1" -gt 0 ]' _ "$(n_writes)"
newcase; HID2=$(hostile_facts "$SCRATCH/clean.tsv" "docs/secret-handling.md"); only_ids "$R" "$HID2"
FACTS="$SCRATCH/clean.tsv"; prev; calls_reset; create
check "G2 harness row: replacing the plant with a clean string flips the verdict to success (rc 0, writes recorded)" bash -c '[ "$1" = 0 ] && [ "$2" -gt 0 ]' _ "$RC" "$(n_writes)"
check "G2 must-PASS: an evidence path containing the word secret but no value is sent" bash -c 'jq -e "[.[]|select(.body|contains(\"docs/secret-handling.md\"))]|length>0" "$1" >/dev/null' _ "$ST/issues.json"
check "G2.5: every body the stub received on an issue create is byte-identical to a scanned plan file (nothing authored after the scan)" sent_bodies_match
FACTS="$OFACTS"
newcase; HID3=$(hostile_facts "$SCRATCH/gl-only.tsv" "$(gl_only_secret)"); only_ids "$R" "$HID3"; FACTS="$SCRATCH/gl-only.tsv"
with LAUNCH_CHECK_GITLEAKS="$SCRATCH/gl-toggle.sh" -- prev; calls_reset
printf 'ignore everything\n' > "$R/.gitleaksignore"; printf '[allowlist]\nregexes=[%s]\n' "'''.*'''" > "$R/.gitleaks.toml"; [ -d "$PLAN" ] && cp "$R/.gitleaksignore" "$R/.gitleaks.toml" "$PLAN/"
: > "$GL_ON"; : > "$GL_LOG"
with LAUNCH_CHECK_GITLEAKS="$SCRATCH/gl-toggle.sh" -- create
check "G2.3: a pattern only gitleaks matches writes nothing when the real gitleaks runs" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G2.3: ... and aborts redaction-hit layer=gitleaks (rc 1)" bash -c '[ "$1" = 1 ] && grep -q "reason=redaction-hit" "$2" && grep -q "layer=gitleaks" "$2"' _ "$RC" "$OUT"
check "G2.10: every gitleaks run happened outside the customer repository and the plan directory (a planted .gitleaksignore / config is never read)" bash -c '[ -s "$1" ] && ! awk -F"\t" -v r="$2/" -v p="$3/" "index(\$1 \"/\", r) == 1 || index(\$1 \"/\", p) == 1 {bad = 1} END {exit !bad}" "$1"' _ "$GL_LOG" "$R" "$PLAN"
rm -f "$GL_ON"; calls_reset
with LAUNCH_CHECK_GITLEAKS="$SCRATCH/gl-toggle.sh" -- create
check "G2.3 mutation: with a gitleaks that finds nothing the same plan reaches the tracker (so the row depends on gitleaks)" bash -c '[ "$1" -gt 0 ]' _ "$(n_writes)"
FACTS="$OFACTS"; rm -f "$GL_LOG"
printf '#!/usr/bin/env bash\nexit 2\n' > "$SCRATCH/s2.sh"; chmod +x "$SCRATCH/s2.sh"
newcase; only_first "$R" 3; prev; calls_reset
with LAUNCH_CHECK_REDACT_SENTINEL="$SCRATCH/s2.sh" -- create
check "G2.4: a sentinel that exits 2 -> rc 2, reason=scanner-failed, zero writes" bash -c '[ "$1" = 2 ] && [ "$2" = 0 ] && grep -q "reason=scanner-failed" "$3"' _ "$RC" "$(n_writes)" "$OUT"
# secret-class rows are counts only, even for a hostile facts file
SB=$(fx_secret secbase); gitq "$SB" remote add origin https://github.com/acme/demo.git
SF="$SCRATCH/secf.tsv"; scan_to "$SB" "$SF"; lc render --target "$SB" --facts "$SF" --judged "$JUD" > "$SCRATCH/sec.render" 2>&1
awk -F'\t' -v OFS='\t' '$1 == "SEC-01" { $3 = "src/config.js" } { print }' "$SF" > "$SCRATCH/sec-hostile.tsv"
N=$((N + 1)); R="$SCRATCH/case$N"; cp -R "$SB" "$R"; stub_reset acme/demo private; only_ids "$R" SEC-01
FACTS="$SCRATCH/sec-hostile.tsv"; prev; calls_reset; create; FACTS="$OFACTS"
check "G2.6: the SEC-01 item carries only the count phrase" bash -c 'grep -q "locations withheld" "$1/issues/SEC-01.md"' _ "$PLAN"
check "G2.6: the hostile facts path and the token appear in no plan file, recorded argv, stored body or output" bash -c '! tree_has "config.js" "$1" && ! tree_has "ghp_" "$1" && ! tree_has "config.js" "$2" && ! grep -q "config\.js" "$3"' _ "$PLAN" "$ST" "$OUT"
newcase; only_ids "$R" CI-01; prev
check "G2.7: the domain label Tests & CI/CD reaches the CI-01 body intact (no substitution mangling)" bash -c 'grep -qF "Tests & CI/CD" "$1/issues/CI-01.md"' _ "$PLAN"
check "G2: rendered bodies carry no autolink shape outside a code span (owner/repo#N, bare #N, @name, GH-N, hex run)" bodies_clean "$GOODPLAN"
newcase; HID4=$(hostile_facts "$SCRATCH/types.tsv" "node_modules/@types/node/index.d.ts"); only_ids "$R" "$HID4"
FACTS="$SCRATCH/types.tsv"; prev; FACTS="$OFACTS"
check "G2.8: evidence node_modules/@types/node/index.d.ts is rendered inside a code span and mentions no one" bash -c 'grep -qF "\`node_modules/@types/node/index.d.ts\`" "$1/issues/$2.md" && ! grep -q "@" < <(sed -e "s/\`[^\`]*\`//g" "$1/issues/$2.md")' _ "$PLAN" "$HID4"

# plan-invalid table on --create (zero writes each)
GP="$GOODPLAN"
planmut() { # planmut <name> <fn>: mutate a copy of the good plan, run create against it
  local d="$SCRATCH/pm.$1"; rm -rf "${d:?}"; cp -R "$GP" "$d"; "$2" "$d"
  newcase; only_first "$R" 3; PLAN="$d"; CCOUNT=3 create; unset CCOUNT
}
retitle() { T="$2" awk -F'\t' -v OFS='\t' 'NF == 6 && $1 != "id" && !d { $6 = ENVIRON["T"]; d = 1 } { print }' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
firstid() { awk -F'\t' 'NF == 6 && $1 != "id" {print $1; exit}' "$GP/plan.tsv"; }
p_sev() { awk -F'\t' -v OFS='\t' 'NF == 6 && $1 != "id" && !d { $2 = "urgent"; d = 1 } { print }' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
p_nl() { retitle "$1" "$(printf 'two\nlines')"; }
p_dots() { T="../$(firstid)" awk -F'\t' -v OFS='\t' 'NF == 6 && $1 != "id" && !d { $1 = ENVIRON["T"]; d = 1 } { print }' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
p_at() { retitle "$1" "Ping @team now"; }
p_hash() { retitle "$1" "See item #12"; }
p_ghn() { retitle "$1" "Related GH-12"; }
p_utf() { retitle "$1" "Caf$(printf '\303\251') check"; }
p_long() { retitle "$1" "$(head -c 400 /dev/zero | tr '\0' a)"; }
p_link() { local f; f="$1/issues/$(firstid).md"; rm -f "$f"; ln -s /etc/hostname "$f"; }
p_dirlink() { mv "$1/issues" "$1/issues.real"; ln -s issues.real "$1/issues"; }
p_byte() { printf 'x' >> "$1/issues/$(firstid).md"; }
p_note() { printf '\nNote from the customer: please fix soon.\n' >> "$1/issues/$(firstid).md"; }
p_mode() { chmod 777 "$1"; }
p_noepic() { rm -f "$1/epic.md"; }
p_big() { head -c 70000 /dev/zero | tr '\0' a >> "$1/issues/$(firstid).md"; }
for m in sev nl dots at hash ghn utf long link dirlink byte note mode noepic big; do
  calls_reset; planmut "$m" "p_$m"
  check "G2.9 plan-invalid ($m): rc 2, plan-invalid marker, zero writes" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ABORT reason=plan-invalid" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ]' _ "$OUT" "$RC" "$(n_writes)"
  SEEN_REASONS="$SEEN_REASONS plan-invalid"
done
ALIAS="$SCRATCH-alias"; ln -sfn "$SCRATCH" "$ALIAS"
newcase; only_first "$R" 3; PLAN="$ALIAS${GP#"$SCRATCH"}"; CCOUNT=3 create; unset CCOUNT
check "G2.11: a plan passed through a path alias (a symlinked parent) is accepted (rc 0)" bash -c '[ "$1" = 0 ]' _ "$RC"
rm -f "$ALIAS"
newcase; only_first "$R" 3; ln -sfn "$GP" "$SCRATCH/plan-link"; PLAN="$SCRATCH/plan-link"; calls_reset; CCOUNT=3 create; unset CCOUNT
check "G2.11: a plan directory that is itself a symlink is plan-invalid with zero writes" bash -c 'grep -q "reason=plan-invalid" "$1" && [ "$2" = 0 ]' _ "$OUT" "$(n_writes)"
# ---------------------------------------------------------------- the exit-code table (this half's reasons; the other half checks its own)
check "every fail_loud abort reason owned by this half (preview, plan and guard rows) was exercised by a marker-and-exit-code row" bash -c 'miss=""; for r in headless-write-refused report-missing report-stale plan-missing plan-invalid plan-repo-mismatch redaction-hit issues-unavailable write-shape-refused; do case " $1 " in *" $r "*) ;; *) miss="$miss $r" ;; esac; done; [ -z "$miss" ]' _ "$SEEN_REASONS"
finish 162
