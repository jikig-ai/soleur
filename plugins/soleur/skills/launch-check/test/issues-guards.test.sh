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

# known-bad controls for the helpers every later row leans on: a helper that cannot fail would let every row that uses it pass
ctl_out="$SCRATCH/ctl.out"; printf 'SOLEUR_LAUNCH_CHECK_ABORT reason=alpha detail=x\nSOLEUR_LAUNCH_CHECK_ISSUES_PLAN create=3 plan=/p\n' > "$ctl_out"
ctl_abort_is() ( SEEN_REASONS=""; RC=2; OUT="$ctl_out"
  ! abort_is 3 alpha && ! abort_is 2 alph && ! abort_is 2 beta && [ -z "$SEEN_REASONS" ] && abort_is 2 alpha && [ "$SEEN_REASONS" = " alpha" ] )
check "control (abort_is): a wrong exit code, a wrong reason or a prefix of the real one fails, and only a held assertion records its reason" ctl_abort_is
ctl_lacks() ( OUT="$ctl_out"; ! lacks alpha && lacks zzz-not-there )
check "control (lacks): a string that is in the output fails it, one that is not passes it" ctl_lacks
ctl_kv() { [ "$(kv "$ctl_out" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN create)" = 3 ] && [ -z "$(kv "$ctl_out" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN nokey)" ] && [ -z "$(kv "$ctl_out" SOLEUR_LAUNCH_CHECK_ISSUES create)" ] && [ -z "$(kv "$ctl_out" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN crea)" ]; }
check "control (kv): the value of an exact key on an exact marker; a missing key, a different marker and a key prefix read as empty" ctl_kv
stub_reset acme/demo private; calls_reset
gh api -X GET repos/acme/demo >/dev/null 2>&1
check "control (n_writes): a read is a call and not a write" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$(n_writes)" "$(n_calls)"
ctl_sbm() (
  PLAN="$SCRATCH/ctlplan"; mkdir -p "$PLAN/issues"; printf 'planned body\n' > "$PLAN/issues/a.md"; printf 'planned body\n' > "$PLAN/epic.md"
  stub_reset acme/demo private; calls_reset
  ! sent_bodies_match || return 1
  printf 'planned body\n' > "$SCRATCH/ctl.b1"; gh api -X POST repos/acme/demo/issues -f title=t -F body=@"$SCRATCH/ctl.b1" >/dev/null 2>&1
  sent_bodies_match || return 1
  printf 'planned body, edited\n' > "$SCRATCH/ctl.b2"; gh api -X POST repos/acme/demo/issues -f title=t2 -F body=@"$SCRATCH/ctl.b2" >/dev/null 2>&1
  ! sent_bodies_match
)
check "control (sent_bodies_match): nothing sent fails, a body that is a plan file passes, one extra edited body fails it" ctl_sbm
printf 'TOP\n<!-- launch-check:begin -->\nINNER\n<!-- launch-check:end -->\nBOTTOM\n' > "$SCRATCH/ctl.ep"
printf 'TOP\r\n<!-- launch-check:begin -->\r\nINNER\r\n<!-- launch-check:end -->\r\nBOTTOM\r\n' > "$SCRATCH/ctl.epcr"
check "control (outside): the text between the markers is dropped (LF and CRLF), the text outside stays" bash -c '[ "$(outside "$1")" = "$(printf "TOP\nBOTTOM")" ] && ! outside "$2" | grep -q INNER && outside "$2" | grep -q BOTTOM && outside "$2" | grep -q TOP' _ "$SCRATCH/ctl.ep" "$SCRATCH/ctl.epcr"
stub_reset acme/demo private

# ---------------------------------------------------------------- 1. the library exists; source scans
check "scripts/lib/issues.sh exists" test -f "$ISS"
verbs=$(find "$SKILL/scripts" "$SKILL/references" "$SKILL/SKILL.md" -type f -exec grep -nE 'gh[[:space:]]+(issue|label|pr)([[:space:]]|$)' {} + 2>/dev/null || true)
check "no gh issue / gh label / gh pr verb anywhere in the skill (REST via gh api only)" test -z "$verbs"
jq_fn_violations() { grep -h -- '--jq' "$@" 2>/dev/null | sed -e 's/.*--jq//' | grep -oE '[a-z_][a-z_0-9]*\(' | sort -u | grep -vxE '(scan|select|test)\(' || true; }
check "every shipped --jq expression stays inside the pinned function list (scan, //, @tsv, select, test)" bash -c '[ -f "$1" ] && [ -z "$2" ] && grep -q -- "--jq" "$1"' _ "$ISS" "$(jq_fn_violations "$ISS")"
mkdir -p "$SCRATCH/scan1"; printf "x --jq 'ltrimstr(\"a\")'\n" > "$SCRATCH/scan1/jqbad.sh"
check "pinned-list canary: a function outside the list is flagged" test -n "$(jq_fn_violations "$SCRATCH/scan1/jqbad.sh")"
gh_cmd_lines() { # every `gh` token in code (not a comment line, not `command -v gh`, not a path such as gh.out), each with the function that holds it
  awk 'FNR == 1 { fn = "" } /^[a-zA-Z_][a-zA-Z_0-9]*\(\) *\{/ { fn = $1 } /^[[:space:]]*#/ { next }
       /(^|[^A-Za-z0-9_.\/-])gh([^A-Za-z0-9_.\/-]|$)/ && !/command -v gh/ { print FILENAME ":" fn }' "$@"
}
others=$(gh_cmd_lines "$SKILL"/scripts/*.sh "$SKILL"/scripts/lib/*.sh | grep -v 'lc__gh_exec' || true)
check "gh is invoked only inside lc__gh_exec, and it is invoked there (anti-vacuous)" bash -c '[ -f "$1" ] && [ -z "$2" ] && [ -n "$3" ]' _ "$ISS" "$others" "$(gh_cmd_lines "$ISS")"
{ cat "$ISS" 2>/dev/null; printf '\nlc_extra() {\n  gh api -X POST repos/o/r/issues -f title=x\n}\n'; } > "$SCRATCH/scan1/issues.sh"
check "mutation (Guard 1 row 5): a second gh call site outside lc__gh_exec is caught by the scan" bash -c '[ -f "$1" ] && [ -n "$2" ]' _ "$ISS" "$(gh_cmd_lines "$SCRATCH/scan1/issues.sh" | grep -v lc__gh_exec || true)"
# any gh token counts, not a list of spellings: a verb the first draft's list did not name, a tab separator and an exec form are all caught
for spell in 'gh extension install x' 'exec gh version' 'x=$(gh	browse)' 'gh -R o/r issue list'; do
  printf 'lc_extra() {\n  %s\n}\n' "$spell" > "$SCRATCH/scan1/spell.sh"
  check "mutation (Guard 1 scan, any gh token): '$spell' outside lc__gh_exec is caught" test -n "$(gh_cmd_lines "$SCRATCH/scan1/spell.sh")"
done
printf 'lc_ok() {\n  command -v gh >/dev/null\n  x=$WORK/gh.out; ISSUES_REASON=gh-missing\n  # gh api is only a comment\n}\n' > "$SCRATCH/scan1/ok.sh"
check "scan control: command -v gh, a gh.out path, gh-missing and a comment line are not call sites" test -z "$(gh_cmd_lines "$SCRATCH/scan1/ok.sh")"
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
m_dirlink() { mv "$1/issues" "$1/issues.real"; ln -s issues.real "$1/issues"; }
# (a symlinked issues/ directory is reached here: --create's strict mode refuses it earlier, for its mode)
for md in badid:id symlink:symlink big:size twomark:marker nomark:marker badrepo:repo extra:body-files dirlink:issues-dir; do
  m=${md%%:*}; det=${md#*:}
  calls_reset; chkmut "$m" "m_$m"
  check "check-plan rejects a hand-edited plan ($m): plan-invalid detail=$det on stdout, rc 2, zero gh calls" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ABORT reason=plan-invalid detail=$4\( \|\$\)" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ]' _ "$OUT" "$RC" "$(n_calls)" "$det"
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
check "preview: a PUBLIC repo prints the warning and the create command WITHOUT --confirm-public, and a separate line that names the flag" bash -c 'c=$(cmd_line "$1"); [ -n "$c" ] && ! grep -q -- "--confirm-public" <<<"$c" && grep -qi "public" "$1" && grep -q "append --confirm-public" "$1" && [ "$2" = PUBLIC ]' _ "$OUT" "$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN visibility)"
for vis in internal weird; do
  newcase; stub_reset acme/demo "$vis"; only_first "$R" 3; prev
  check "preview ($vis visibility): the create command has no --confirm-public and the separate line is printed" bash -c 'c=$(cmd_line "$1"); [ -n "$c" ] && ! grep -q -- "--confirm-public" <<<"$c" && grep -q "append --confirm-public" "$1"' _ "$OUT"
done
newcase; only_first "$R" 3; prev
check "preview: a PRIVATE repo prints the create command and no --confirm-public line" bash -c 'c=$(cmd_line "$1"); [ -n "$c" ] && ! grep -q -- "--confirm-public" "$1"' _ "$OUT"
newcase; stub_reset acme/demo private true; only_first "$R" 3; prev
check "preview: a fork names the resolved owner/name and the fork flag" bash -c 'grep -q "acme/demo" "$1" && grep -qi "fork" "$1"' _ "$OUT"
newcase; stub_reset other/thing private; only_first "$R" 3; prev
check "preview: a resolved slug that differs from origin's aborts repo-unresolved unless --repo is passed" abort_is 2 repo-unresolved
prev --repo other/thing
check "preview: --repo <slug> acknowledges the repository gh resolved when it differs from origin (it does not choose the target)" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES_PLAN" "$2"' _ "$RC" "$OUT"
prev --repo acme/demo
check "preview: --repo does not retarget: naming origin's slug while gh resolved another repository aborts repo-unresolved detail=repo-flag-differs" bash -c 'grep -q "detail=repo-flag-differs" "$1"' _ "$OUT"; check "preview: ... with the marker and rc 2" abort_is 2 repo-unresolved

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
for hv in true TRUE Yes; do
  calls_reset; with LAUNCH_CHECK_HEADLESS=$hv -- create
  check "G1.3: LAUNCH_CHECK_HEADLESS=$hv -> zero calls and headless-write-refused (1, true and yes in any case all mean unattended)" bash -c '[ "$1" = 0 ]' _ "$(n_calls)"
  check "G1.3: ... LAUNCH_CHECK_HEADLESS=$hv aborts headless-write-refused (rc 2)" abort_is 2 headless-write-refused
done
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
probe "$SKILL" - "CI=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=lc:probe -f color=ededed
check "G1.4: lc_gh_write called directly under CI=1 aborts headless-write-refused (rc 2) and reaches nothing" bash -c '[ "$1" = 2 ] && grep -q "reason=headless-write-refused" "$2" && [ "$3" = 0 ]' _ "$PRC" "$SCRATCH/probe.out" "$(n_calls)"
probe "$SKILL" - "LC_DRY=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=lc:probe -f color=ededed
check "G1.4: lc_gh_write called directly under LC_DRY=1 returns 0 and reaches nothing (the function exists)" bash -c '[ "$1" = 0 ] && [ "$2" = 0 ]' _ "$PRC" "$(n_calls)"
probe "$SKILL" - "X=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=lc:probe -f color=ededed
check "G1.4 twin: the same compliant call with neither switch reaches the stub exactly once" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
# lc_is_headless itself: CI non-empty, or LAUNCH_CHECK_HEADLESS 1, true or yes in any case; nothing else, and no TTY test
for hv in 1 true TRUE True yes YES Yes; do
  probe "$SKILL" - "LAUNCH_CHECK_HEADLESS=$hv" lc_is_headless
  check "lc_is_headless: LAUNCH_CHECK_HEADLESS=$hv is unattended" test "$PRC" = 0
done
for hv in 0 false no off ""; do
  probe "$SKILL" - "LAUNCH_CHECK_HEADLESS=$hv" lc_is_headless
  check "lc_is_headless: LAUNCH_CHECK_HEADLESS='$hv' is not unattended (rc 1, the function exists)" test "$PRC" = 1
done
probe "$SKILL" - "CI=false" lc_is_headless
check "lc_is_headless: any non-empty CI (even false) is unattended" test "$PRC" = 0
shape_with() { # shape_with <env-assignment> <detail> <desc> <args...>: a call outside the allowlisted shapes -> write-shape-refused with exactly this detail token
  local e=$1 det=$2 d=$3; shift 3; calls_reset; probe "$SKILL" - "$e" lc_gh_write "$@"
  check "G1.7: $d -> write-shape-refused detail=$det, rc 2, nothing recorded and nothing refused by the stub" bash -c 'grep -q "reason=write-shape-refused detail=$4\( \|\$\)" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ] && [ ! -s "$5" ]' _ "$SCRATCH/probe.out" "$PRC" "$(n_calls)" "$det" "$ST/refused.log" && seen write-shape-refused
}
shape() { local det=$1 d=$2; shift 2; shape_with EPIC_NUM=101 "$det" "$d" "$@"; }
PLAN=""; printf 'body\n' > "$SCRATCH/body.txt"
shape shape "-X DELETE" api -X DELETE repos/acme/demo/issues/101
shape shape "a labels PATCH" api -X PATCH repos/acme/demo/labels -f name=x
shape shape "a different slug" api -X POST repos/evil/other/issues -f title=x
shape field-key "state on the PATCH shape" api -X PATCH repos/acme/demo/issues/101 -f state=closed
shape file-operand "an @file operand outside the plan directory" api -X PATCH repos/acme/demo/issues/101 -F body=@/etc/hostname
shape issue-number "a non-digit issue number on a PATCH that carries a valid body file (nothing else about it is wrong)" api -X PATCH repos/acme/demo/issues/10x -F "body=@$SCRATCH/body.txt"
shape issue-number "a non-digit parent on a link that carries a valid integer id" api -X POST repos/acme/demo/issues/10x/sub_issues -F sub_issue_id=5
shape not-api "an issue verb form" issue create --title x
shape not-api "api with --method instead of -X" api --method POST repos/acme/demo/issues -f title=x
shape epic-bind "a PATCH to an issue other than the epic (102, epic is 101)" api -X PATCH repos/acme/demo/issues/102 -F "body=@$SCRATCH/body.txt"
shape_with X=1 epic-bind "a PATCH when no epic is known (EPIC_NUM unset)" api -X PATCH repos/acme/demo/issues/101 -F "body=@$SCRATCH/body.txt"
shape epic-bind "a sub_issues link under another parent (102, epic is 101)" api -X POST repos/acme/demo/issues/102/sub_issues -F sub_issue_id=5
shape_with X=1 epic-bind "a sub_issues link when no epic is known" api -X POST repos/acme/demo/issues/101/sub_issues -F sub_issue_id=5
shape label-name "a label create named bug (not lc:)" api -X POST repos/acme/demo/labels -f name=bug -f color=ededed
shape label-name "an issue create carrying the label bug" api -X POST repos/acme/demo/issues -f title=x -f 'labels[]=bug'
shape field-key "an issue create whose field key holds a space (title body)" api -X POST repos/acme/demo/issues -f 'title body=x'
shape raw-field "a raw -f body= on the epic PATCH (the body must be a file operand)" api -X PATCH repos/acme/demo/issues/101 -f body=text
shape raw-field "a raw -f sub_issue_id= on the link (it must be a typed integer)" api -X POST repos/acme/demo/issues/101/sub_issues -f sub_issue_id=5
shape typed-field "a typed -F body= that is not an @file" api -X PATCH repos/acme/demo/issues/101 -F body=text
shape typed-field "a typed -F title=" api -X POST repos/acme/demo/issues -F title=x
shape sub-issue-id "a typed sub_issue_id that is not an integer" api -X POST repos/acme/demo/issues/101/sub_issues -F sub_issue_id=abc
shape field-form "a field word with no =" api -X POST repos/acme/demo/issues -f title
shape flag-value "a field flag with nothing after it" api -X POST repos/acme/demo/issues -f
shape flag "a flag outside the allowlist (--input)" api -X POST repos/acme/demo/issues --input x
stub_reset acme/demo private; seed 101 open stub-user lc:launch-check,lc:epic ''; calls_reset
probe "$SKILL" - "EPIC_NUM=101" lc_gh_write api -X PATCH repos/acme/demo/issues/101 -F "body=@$SCRATCH/body.txt"
check "G1.7 twin: the same PATCH to the epic itself reaches the stub exactly once" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
calls_reset; probe "$SKILL" - "EPIC_NUM=101" lc_gh_write api -X POST repos/acme/demo/issues/101/sub_issues -F sub_issue_id=5
check "G1.7 twin: a link under the epic itself reaches the stub exactly once (the stub may refuse the unknown id)" test "$(n_writes)" = 1
calls_reset; probe "$SKILL" - "X=1" lc_gh_write api -X POST repos/acme/demo/issues -f title=x -f 'labels[]=lc:launch-check'
check "G1.7 twin: an lc: label on an issue create reaches the stub exactly once" test "$(n_writes)" = 1
# reads: auth takes only status and repo only view (a second word like delete, edit or token is not a read); api is GET only and never graphql
read_refused() { # read_refused <detail> <desc> <args...>
  local det=$1 d=$2; shift 2; stub_reset acme/demo private; calls_reset; probe "$SKILL" - "X=1" lc_gh_read "$@"
  check "G1.8: lc_gh_read $d is refused (write-shape-refused detail=$det, rc 2, zero gh calls)" bash -c 'grep -q "reason=write-shape-refused detail=$4\( \|\$\)" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ]' _ "$SCRATCH/probe.out" "$PRC" "$(n_calls)" "$det" && seen write-shape-refused
}
read_refused read-verb "repo delete" repo delete acme/demo
read_refused read-verb "repo edit" repo edit acme/demo --visibility public
read_refused read-verb "repo with no verb" repo
read_refused read-verb "auth token" auth token
read_refused read-verb "auth login" auth login
read_refused read-verb "auth with no verb" auth
read_refused read-verb "a verb that is not a read (issue)" issue list
read_refused read-not-get "api -X POST" api -X POST repos/acme/demo/labels -f name=x
read_refused read-not-get "api -XPOST (attached)" api -XPOST repos/acme/demo/labels -f name=x
read_refused read-not-get "api --method=POST" api --method=POST repos/acme/demo/labels -f name=x
read_refused read-not-get "api --method PATCH" api --method PATCH repos/acme/demo/issues/101
read_refused read-not-get "api -X with nothing after it" api repos/acme/demo -X
read_refused read-graphql "api graphql" api graphql -f query=x
read_refused read-graphql "api /graphql" api /graphql -f query=x
read_refused read-graphql "api <host path>/graphql" api repos/acme/demo/graphql
calls_reset; probe "$SKILL" - "X=1" lc_gh_read auth status
check "G1.8 twin: lc_gh_read auth status reaches the stub once" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_calls)"
calls_reset; probe "$SKILL" - "X=1" lc_gh_read repo view --json nameWithOwner
check "G1.8 twin: lc_gh_read repo view reaches the stub once" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_calls)"
# every shipped phrase renders through lc__fmt: no stderr (a phrase that starts with -- was read as an option) and not empty
cat > "$SCRATCH/allphr.sh" <<'EOS'
lc_test_all_phrases() {
  local k f n args i out
  for k in $(awk -F= '/^[a-z_0-9-]+=/ {print $1}' "$SKILL_DIR/references/phrases.txt"); do
    f=$(lc_phrase "$k"); n=$(grep -o '%s' <<<"$f" | wc -l | tr -d ' '); args=(); i=0
    while [ "$i" -lt "$n" ]; do args+=("v$i"); i=$((i + 1)); done
    out=$(lc__fmt "$k" ${args[@]+"${args[@]}"} 2>"$WORK/phr.err")
    if [ -s "$WORK/phr.err" ] || [ -z "$out" ]; then echo "BAD-PHRASE $k"; return 1; fi
  done
  echo PHRASES-OK
}
EOS
probe "$SKILL" "$SCRATCH/allphr.sh" "X=1" lc_test_all_phrases
check "every phrases.txt key renders through lc__fmt with no stderr and a non-empty result (a phrase starting with -- is not an option)" bash -c '[ "$1" = 0 ] && grep -q PHRASES-OK "$2" && ! grep -q BAD-PHRASE "$2"' _ "$PRC" "$SCRATCH/probe.out"
check "phrase-render canary: a bare printf of a -- phrase prints to stderr (the helper would see it)" bash -c 'f="--starts-with-dashes %s"; [ -n "$(printf "$f" v 2>&1 >/dev/null)" ]'
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
with GH_HOST=evil.example GH_REPO=other/repo GH_DEBUG=api DEBUG=1 HTTPS_PROXY=http://proxy.invalid:3128 HTTP_PROXY=http://proxy.invalid:3128 ALL_PROXY=http://proxy.invalid:3128 NO_PROXY=x http_proxy=http://proxy.invalid:3128 https_proxy=http://proxy.invalid:3128 all_proxy=http://proxy.invalid:3128 no_proxy=x GH_CONFIG_DIR="$SCRATCH/cfg" GH_ENTERPRISE_TOKEN=tok GITHUB_ENTERPRISE_TOKEN=tok SSL_CERT_FILE=/nonexistent/ca SSL_CERT_DIR=/nonexistent GH_FORCE_TTY=1 GH_PATH=/nonexistent -- prev_create
check "G1.9: the run completed against the stub (anti-vacuous: calls and writes were recorded)" bash -c '[ "$1" -gt 3 ] && [ "$2" -gt 0 ]' _ "$(n_calls)" "$(n_writes)"
check "G1.9: every variable the code unsets (GH_REPO, GH_DEBUG, DEBUG, GH_CONFIG_DIR, GH_PATH, GH_FORCE_TTY, SSL_CERT_*, both enterprise tokens, every proxy spelling) is absent from every recorded call, and GH_HOST is the target host, never the inherited one" bash -c '[ "$1" -gt 0 ] && [ "$2" = 0 ]' _ "$(n_calls)" "$(cj '[.[]|select(.env != {GH_HOST:"github.com"})]|length')"
check "G1.9: no recorded call reads the caller's stdin (it is /dev/null; the check is skipped where /proc is absent)" bash -c '[ ! -r /proc/self/fd/0 ] || [ "$(jq -sr "[.[]|select(.stdin != \"/dev/null\")]|length" "$1")" = 0 ]' _ "$ST/calls.log"
check "G1.9: after the slug is resolved no call runs with the customer repository as its working directory" bash -c '[ -s "$3" ] && [ "$(jq -sr --arg r "$1" "[.[]|select(.class!=\"repo\" and .class!=\"auth\")|select(.cwd|startswith(\$r))]|length" "$3")" = 0 ]' _ "$R" x "$ST/calls.log"
newcase; only_first "$R" 3; prev; [ -d "$PLAN" ] && sed 's/^host=.*/host=ghe.example/' "$PLAN/plan.tsv" > "$PLAN/p.new" && mv "$PLAN/p.new" "$PLAN/plan.tsv"; calls_reset; create
check "G1.9: a plan for a non-github.com host is refused without --host (rc 2, an ABORT marker naming the host, zero writes)" bash -c '[ "$1" = 2 ] && [ "$2" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ABORT" "$3" && grep -qi "host" "$3"' _ "$RC" "$(n_writes)" "$OUT"
gitq "$R" remote set-url origin https://ghe.example/acme/demo.git
calls_reset; with GITHUB_ENTERPRISE_TOKEN=tok -- create --host ghe.example
check "G1.9: --host ghe.example makes the same plan runnable (rc 0, writes recorded)" bash -c '[ "$1" = 0 ] && [ "$2" -gt 0 ]' _ "$RC" "$(n_writes)"
check "G1.9: on a non-github default host EVERY recorded call carries GH_HOST=ghe.example, and the enterprise token that host needs is passed through" bash -c '[ "$(jq -sr "[.[]|select(.env.GH_HOST!=\"ghe.example\")]|length" "$1")" = 0 ] && [ "$(jq -sr "[.[]|select(.env.GITHUB_ENTERPRISE_TOKEN==\"(set)\")]|length>0" "$1")" = true ]' _ "$ST/calls.log"
# the origin remote must be on the target host
newcase; only_first "$R" 3; gitq "$R" remote set-url origin https://gitlab.example/acme/demo.git; prev
check "origin host: a remote on another host than the target aborts repo-unresolved detail=host-differs (the recovery names --host)" bash -c 'grep -q "detail=host-differs" "$1" && grep -q -- "--host" "$1"' _ "$OUT"; check "origin host: ... with the marker and rc 2" abort_is 2 repo-unresolved
prev --repo acme/demo
check "origin host: --repo does not waive the host check" bash -c 'grep -q "detail=host-differs" "$1"' _ "$OUT"
prev --host gitlab.example
check "origin host: naming that host makes the same preview proceed" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES_PLAN" "$2"' _ "$RC" "$OUT"
newcase; only_first "$R" 3; gitq "$R" remote set-url origin git@github.com:acme/demo.git; prev
check "origin host: an scp-style remote on the target host is accepted" bash -c '[ "$1" = 0 ] && grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES_PLAN" "$2"' _ "$RC" "$OUT"
# --repo is an acknowledgement, not a target, and the plan does not record it: a create that omits it meets the same origin check
newcase; stub_reset other/thing private; only_first "$R" 3; prev --repo other/thing; calls_reset
CREPO=other/thing create
check "origin differs (create): a create WITHOUT --repo after a preview that needed it aborts repo-unresolved detail=origin-differs with zero writes" bash -c 'grep -q "detail=origin-differs" "$1" && [ "$2" = 0 ]' _ "$OUT" "$(n_writes)"; check "origin differs (create): ... marker and rc" abort_is 2 repo-unresolved
CREPO=other/thing create --repo other/thing
check "origin differs (create): the same create WITH --repo other/thing (the resolved slug) proceeds (rc 0, writes recorded)" bash -c '[ "$1" = 0 ] && [ "$2" -gt 0 ]' _ "$RC" "$(n_writes)"

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
stub_reset acme/demo private; probe "$M1" - "CI=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=lc:probe -f color=ededed
check "G1 mutation (headless check removed): the CI=1 call now reaches the stub, so the G1.4 row is sensitive" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
M2=$(sbx_edit nodry '/\[ "\${LC_DRY:-0}" = 1 \] && return 0/d')
check "G1 mutation landed (dry-run check removed from lc_gh_write in the sandbox copy)" mut_landed "$M2"
stub_reset acme/demo private; probe "$M2" - "LC_DRY=1" lc_gh_write api -X POST repos/acme/demo/labels -f name=lc:probe -f color=ededed
check "G1 mutation (dry-run check removed): the LC_DRY=1 call now reaches the stub, so the G1.4 dry-run row is sensitive" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
M3=$(sbx_edit nofile 's/lc__file_ok "${val#@}" || lc__refuse file-operand/:/')
check "G1 mutation landed (@file confinement removed from the sandbox copy)" mut_landed "$M3"
stub_reset acme/demo private; seed 101 open stub-user lc:launch-check ''; calls_reset
probe "$M3" - "EPIC_NUM=101" lc_gh_write api -X PATCH repos/acme/demo/issues/101 -F body=@/etc/hostname
check "G1 mutation (@file confinement removed): an operand outside the plan directory now reaches the stub, so the G1.7 row is sensitive" bash -c '[ "$1" = 0 ] && [ "$2" = 1 ]' _ "$PRC" "$(n_writes)"
M4=$(sbx_edit nokeys 's/case "$allowed" in \*" $key "\*) ;; \*) lc__refuse field-key ;; esac/:/')
check "G1 mutation landed (field-key allowlist removed from the sandbox copy)" mut_landed "$M4"
stub_reset acme/demo private; seed 101 open stub-user lc:launch-check ''; calls_reset
probe "$M4" - "EPIC_NUM=101" lc_gh_write api -X PATCH repos/acme/demo/issues/101 -f state=closed
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
banner_bodies() { # every issue body the stub received (the sub-issues and the epic) carries the banner line; at least 2 bodies were sent
  local n=0 seq
  while IFS= read -r seq; do
    grep -qxF -- "$(banner_line)" "$ST/bodies/$seq-body" || return 1; n=$((n + 1))
  done < <(cj '.[]|select(.method=="POST" and (.path|test("/issues$")))|.seq')
  [ "$n" -ge 2 ]
}
check "banner: every created body and the epic body carry the banner line (the report says it is not an attestation; the issues must too)" banner_bodies
check "banner: the banner is the first block after the marker line in every plan body and in the epic" bash -c 'for f in "$1"/issues/*.md "$1"/epic.md; do [ "$(sed -n 1p "$f" | cut -c1-4)" = "<!--" ] && [ -z "$(sed -n 2p "$f")" ] && [ "$(sed -n 3p "$f")" = "$2" ] || exit 1; done' _ "$PLAN" "$(banner_line)"
FACTS="$OFACTS"
# a secret in an item that is NOT the last one in send order is caught: the scanned blob must hold every item, not only the last
hostile_at() { awk -F'\t' -v OFS='\t' -v id="$2" -v ev="$3" '$1 == id { $3 = ev } { print }' "$FACTS" > "$1"; }
newcase; only_first "$R" 3; prev
MI_HID=""; for mi in $(create_ids); do case "$mi" in SEC-0[12]) ;; *) MI_HID=$mi; break ;; esac; done
newcase; only_first "$R" 3; hostile_at "$SCRATCH/multi.tsv" "$MI_HID" "$(planted_secret)"; FACTS="$SCRATCH/multi.tsv"
with LC_TEST_NOGATE=1 -- prev; calls_reset   # FACTS stays hostile: create regenerates the bodies from the facts it is given and compares them with the plan
multi_setup_ok() { # the plan has 3 create rows; the token is in item $MI_HID, which is not the last one
  local pos; [ -n "$MI_HID" ] && [ "$(plan_n)" = 3 ] && grep -qF -- "$(planted_secret)" "$PLAN/issues/$MI_HID.md" || return 1
  pos=$(create_ids | grep -nx "$MI_HID" | cut -d: -f1); [ -n "$pos" ] && [ "$pos" -lt 3 ]
}
check "G2.1 multi-item setup: the plan has 3 create rows and the planted token sits in $MI_HID, which is not the last of them (send order = plan order)" multi_setup_ok
create
check "G2.1 multi-item: a secret in a non-last item writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G2.1 multi-item: ... and aborts redaction-hit with rc 1" abort_is 1 redaction-hit
check "G2.1 multi-item: ... and the token is nowhere in the run's output" lacks "$(planted_secret)"
M5=$(sbx_edit blobtrunc 's#cat "\$ISSUES_PLAN_DIR/issues/\$id.md"; } >> "\$WORK/blob"#cat "$ISSUES_PLAN_DIR/issues/$id.md"; } > "$WORK/blob"#')
check "G2.1 mutation landed (the item loop truncates the blob instead of appending, in the sandbox copy)" mut_landed "$M5"
calls_reset; with LCS="$M5/scripts/launch-check.sh" -- create
check "G2.1 mutation (> instead of >>): only the last item is scanned, so the same plan now reaches the tracker (the multi-item row above is sensitive to the append)" bash -c '[ "$1" = 0 ] && [ "$2" -gt 0 ]' _ "$RC" "$(n_writes)"
FACTS="$OFACTS"
# the preview scans what it is about to put in front of the customer, with the real gate (no bypass seam)
newcase; HIDP=$(hostile_facts "$SCRATCH/hostile-pv.tsv" "$(planted_secret)"); only_ids "$R" "$HIDP"; FACTS="$SCRATCH/hostile-pv.tsv"; calls_reset; prev; FACTS="$OFACTS"
check "G2.1 preview: a hostile fact through the real gate aborts redaction-hit with rc 1 in the preview itself" abort_is 1 redaction-hit
check "G2.1 preview: ... writes no plan (the plan-out directory stays empty), no gh write, and the token is nowhere in the output" bash -c '[ -z "$(ls -A "$1" 2>/dev/null)" ] && [ "$2" = 0 ]' _ "$SCRATCH/po$N" "$(n_writes)"
check "G2.1 preview: ... the token is not echoed" lacks "$(planted_secret)"
M6=$(sbx_edit pvgate '/for id in lc:launch-check lc:epic; do/{n;s/lc_emit_checked "\$WORK\/blob" "" 1/:/;}')
check "G2.1 preview mutation landed (the preview's scan call removed in the sandbox copy)" mut_landed "$M6"
newcase; FACTS="$SCRATCH/hostile-pv.tsv"; only_ids "$R" "$HIDP"; with LCS="$M6/scripts/launch-check.sh" -- prev; FACTS="$OFACTS"
check "G2.1 preview mutation: without the preview's scan the same facts yield a plan that carries the token (so the preview row is sensitive)" bash -c '[ "$1" = 0 ] && [ -n "$2" ] && [ -d "$2" ] && [ -n "$(find "$2" -type f -exec grep -lF -- "$3" {} + 2>/dev/null)" ]' _ "$RC" "$PLAN" "$(planted_secret)"
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
firstid() { awk -F'\t' 'NF == 6 && $1 != "id" && $5 == "create" {print $1; exit}' "$GP/plan.tsv"; }   # a CREATE row: only it has a body file for the byte/note/size/link mutators to reach
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
# a plan that is valid in every vocabulary but no longer what the catalog and facts regenerate
p_rowtitle() { awk -F'\t' -v OFS='\t' 'NF == 6 && $1 != "id" && $5 == "create" && !d { $6 = "A different but valid title"; d = 1 } { print }' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
p_rowsev() { awk -F'\t' -v OFS='\t' 'NF == 6 && $1 != "id" && $5 == "create" && !d { $2 = ($2 == "low") ? "critical" : "low"; d = 1 } { print }' "$1/plan.tsv" > "$1/p.new" && mv "$1/p.new" "$1/plan.tsv"; }
p_epictxt() { printf 'Text added to the epic after the preview.\n' >> "$1/epic.md"; }
p_big() { head -c 70000 /dev/zero | tr '\0' a >> "$1/issues/$(firstid).md"; }
# each mutation of a saved plan is refused for ITS reason: the detail token is part of the assertion
for md in sev:severity nl:row dots:id at:title hash:title ghn:title utf:title long:title link:symlink dirlink:mode byte:body-mismatch note:body-mismatch mode:mode noepic:epic-file big:size rowtitle:row-mismatch rowsev:row-mismatch epictxt:epic-mismatch; do
  m=${md%%:*}; det=${md#*:}
  calls_reset; planmut "$m" "p_$m"
  check "G2.9 plan-invalid ($m): detail=$det, rc 2, plan-invalid marker, zero writes" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ABORT reason=plan-invalid detail=$4\( \|\$\)" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ]' _ "$OUT" "$RC" "$(n_writes)" "$det" && seen plan-invalid
done
ALIAS="$SCRATCH-alias"; ln -sfn "$SCRATCH" "$ALIAS"
newcase; only_first "$R" 3; PLAN="$ALIAS${GP#"$SCRATCH"}"; CCOUNT=3 create; unset CCOUNT
check "G2.11: a plan passed through a path alias (a symlinked parent) is accepted (rc 0)" bash -c '[ "$1" = 0 ]' _ "$RC"
rm -f "$ALIAS"
newcase; only_first "$R" 3; ln -sfn "$GP" "$SCRATCH/plan-link"; PLAN="$SCRATCH/plan-link"; calls_reset; CCOUNT=3 create; unset CCOUNT
check "G2.11: a plan directory that is itself a symlink is plan-invalid with zero writes" bash -c 'grep -q "reason=plan-invalid" "$1" && [ "$2" = 0 ]' _ "$OUT" "$(n_writes)"
# ---------------------------------------------------------------- validators that die are not "valid"
SHIM="$SCRATCH/awkshim"; mkdir -p "$SHIM"
printf '#!/usr/bin/env bash\nif [ -n "${AWK_DIE:-}" ]; then case "$*" in *"$AWK_DIE"*) exit 2 ;; esac; fi\nexec "%s" "$@"\n' "$(command -v awk)" > "$SHIM/awk"; chmod +x "$SHIM/awk"
calls_reset; with PATH="$SHIM:$PATH" AWK_DIE='function fail' -- runi chkdie --check-plan --plan "$SAMPLE"
check "validator death: --check-plan with a plan validator that dies is plan-invalid detail=validator (rc 2), never PLAN_OK" bash -c '! grep -q "PLAN_OK" "$1" && grep -q "reason=plan-invalid detail=validator" "$1" && [ "$2" = 2 ]' _ "$OUT" "$RC"
newcase; only_first "$R" 3; with PATH="$SHIM:$PATH" AWK_DIE='ENVIRON["RE_ID"]' -- prev
check "validator death: a preview whose catalog-title check dies aborts plan-invalid detail=validator and writes no plan" bash -c 'grep -q "reason=plan-invalid detail=validator" "$1" && [ -z "$(ls -A "$2" 2>/dev/null)" ]' _ "$OUT" "$SCRATCH/po$N"
newcase; only_first "$R" 3; with PATH="$SHIM:$PATH" AWK_DIE='lnum[$1]' -- prev
check "validator death: a preview whose partition dies aborts plan-invalid detail=validator (not an empty plan that reads as nothing to file)" bash -c 'grep -q "reason=plan-invalid detail=validator" "$1" && ! grep -q "Nothing to file" "$1"' _ "$OUT"
newcase; only_first "$R" 3; prev; calls_reset; with PATH="$SHIM:$PATH" AWK_DIE='function fail' -- create
check "validator death: create with a plan validator that dies is plan-invalid detail=validator with zero gh calls" bash -c 'grep -q "reason=plan-invalid detail=validator" "$1" && [ "$2" = 0 ]' _ "$OUT" "$(n_calls)"
calls_reset; with PATH="$SHIM:$PATH" AWK_DIE='first[n]' -- create
check "validator death: create whose live-table derivation dies stops issues-incomplete phase=lookup with zero writes (not 'nothing is filed yet')" bash -c 'grep -q "phase=lookup" "$1" && [ "$2" = 0 ]' _ "$OUT" "$(n_writes)"; check "validator death: ... marker and rc" abort_is 2 issues-incomplete
# the record of what a run created must be writable
newcase; only_first "$R" 3; prev; mkdir "$PLAN/created.tsv"; calls_reset; create
check "created.tsv: a record that cannot be appended aborts write-failed (rc 2) with the resume command at once (only the epic was filed), never a silent success" bash -c 'grep -q "detail=created-tsv" "$1" && grep -q -- "--create" "$1" && [ "$2" = 1 ]' _ "$OUT" "$(n_post POST 'repos/acme/demo/issues$')"; check "created.tsv: ... marker and rc" abort_is 2 write-failed
# with the epic already filed, the first record is an item's: that append is checked too
newcase; only_first "$R" 3; seed 531 open stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"; prev; mkdir "$PLAN/created.tsv"; calls_reset; create
check "created.tsv: with the epic already filed, an item's record that cannot be appended aborts write-failed after the first create (rc 2)" bash -c 'grep -q "detail=created-tsv" "$1" && [ "$2" = 1 ]' _ "$OUT" "$(n_post POST 'repos/acme/demo/issues$')"; check "created.tsv: ... item record marker and rc" abort_is 2 write-failed

# ---------------------------------------------------------------- the cap, and rows that carry no body file
bigplan() { # bigplan <n>: the sample plan with n create rows (mode 700), prints its path
  local n=$1 d="$SCRATCH/bp.$1" i id
  cp -R "$SAMPLE" "$d"; chmod 700 "$d" "$d/issues"; sed -n 1,7p "$SAMPLE/plan.tsv" > "$d/plan.tsv"; rm -f "$d/issues/CI-01.md"
  for i in $(seq 1 "$n"); do
    id=$(printf 'CI-%02d' "$i")
    printf '%s\thigh\ttests-ci\treadiness\tcreate\tCI workflow present\n' "$id" >> "$d/plan.tsv"
    sed "s/gap=CI-01/gap=$id/" "$SAMPLE/issues/CI-01.md" > "$d/issues/$id.md"
  done
  printf '%s' "$d"
}
BP30=$(bigplan 30); BP31=$(bigplan 31)
calls_reset; runi cap30 --check-plan --plan "$BP30"
check "cap: --check-plan accepts a plan with exactly 30 create rows" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_PLAN_OK .*create=30" "$1"' _ "$OUT"
runi cap31 --check-plan --plan "$BP31"
check "cap: --check-plan refuses 31 create rows (plan-invalid detail=cap)" bash -c 'grep -q "reason=plan-invalid detail=cap" "$1" && [ "$2" = 2 ]' _ "$OUT" "$RC"
newcase; only_first "$R" 3; calls_reset; PLAN="$BP31" CCOUNT=31 CREPO=acme-fixture/launch-demo create; unset CCOUNT CREPO
check "cap: an actual create with 31 create rows is refused at plan load (plan-invalid detail=cap, zero gh calls)" bash -c 'grep -q "reason=plan-invalid detail=cap" "$1" && [ "$2" = 0 ]' _ "$OUT" "$(n_calls)"
newcase; only_first "$R" 3; calls_reset; PLAN="$BP30" CCOUNT=30 CREPO=acme-fixture/launch-demo create; unset CCOUNT CREPO
check "cap: an actual create with 30 create rows gets past plan load (it stops later, at the repository check)" bash -c 'grep -q "reason=plan-repo-mismatch" "$1"' _ "$OUT"
cap_row() { printf '%s\thigh\tsecurity\treadiness\t%s\tSome title\n' "$2" "$1" >> "$3/plan.tsv"; }
p_capunk() { cap_row capped ZZ-99 "$1"; }
p_exunk() { cap_row exists ZZ-98 "$1"; }
p_exnotgap() { cap_row exists JDG-AUTH "$1"; }
for m in capunk exunk exnotgap; do
  calls_reset; planmut "$m" "p_$m"
  check "plan rows ($m): a capped or exists row naming an id that is not a catalog gap is plan-invalid with zero writes (rc 2)" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ABORT reason=plan-invalid" "$1" && [ "$2" = 2 ] && [ "$3" = 0 ]' _ "$OUT" "$RC" "$(n_writes)"
  SEEN_REASONS="$SEEN_REASONS plan-invalid"
done

# ---------------------------------------------------------------- the exit-code table (this half's reasons; the other half checks its own)
check "every fail_loud abort reason owned by this half (preview, plan and guard rows) was exercised by a marker-and-exit-code row" bash -c 'miss=""; for r in headless-write-refused report-missing report-stale plan-missing plan-invalid plan-repo-mismatch redaction-hit issues-unavailable write-shape-refused; do case " $1 " in *" $r "*) ;; *) miss="$miss $r" ;; esac; done; [ -z "$miss" ]' _ "$SEEN_REASONS"
finish 232
