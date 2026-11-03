#!/usr/bin/env bash
# issues: the only part of launch-check that writes to a customer's tracker. Four guards (plan "Guard Contract"):
#   1 saved-plan-only writes · 2 authored bytes are scanned bytes · 3 idempotency and resume · 4 epic edits confined to the marked section.
# Every case runs against test/gh-stub.sh (a stateful fake gh on PATH); no real gh, no network. The independent witnesses are the
# stub's append-only call log and the fake tracker's contents, never the script's own counters.
#
# INTERFACE ASSUMED BY THIS SUITE (written before issues.sh existed; Phase 2-4 either implement it or amend the line here):
#   launch-check.sh issues --preview      --target R --facts F --judged J [--plan-out D] [--exclude-domain X] [--exclude-class X] [--host H] [--repo S]
#       stdout: SOLEUR_LAUNCH_CHECK_ISSUES_PLAN repo=<o/n> visibility=<V> create=<n> exists=<n> closed=<n> accepted=<n> excluded=<n> capped=<n> plan=<dir>
#       (the plan directory is created inside D; report-only: SOLEUR_LAUNCH_CHECK_ISSUES mode=report-only reason=<cause>, exit 0, no plan)
#   launch-check.sh issues --create       --target R --facts F --judged J --plan P --confirm-repo S --confirm-count N [--confirm-public] [--repo S] [--host H] [--dry-run]
#       stdout: SOLEUR_LAUNCH_CHECK_ISSUES created= linked= skipped= failed=<ids> fallback= epic=#N epic-section= plan=<dir> phase=<..>
#   launch-check.sh issues --check-plan   --plan P            stdout: SOLEUR_LAUNCH_CHECK_PLAN_OK
#   plan.tsv: key=value header lines (repo host visibility catalog_hash report_hash created), then a header row and one row per item:
#       id<TAB>severity<TAB>domain<TAB>class<TAB>action<TAB>title      (see test/fixtures/plan-sample)
#   Sourced-library names: lc_gh_write, lc_gh_read, lc__gh_exec, lc_issues_live (writes $WORK/live.tsv), lc_epic_splice <old-body-file> <new-section-file>
#   (new body on stdout), lc_emit_checked; globals ISSUES_REPO (plan-bound slug) and ISSUES_PLAN_DIR; env LC_DRY=1; seam LAUNCH_CHECK_PAUSE=0.
# Rows tagged UNVERIFIED-STUB-ONLY depend on a stub shape nobody has checked against GitHub yet (live check: follow-up #11956).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "instrument self-test" selftest
command -v gitleaks >/dev/null 2>&1 || { echo "FAIL - gitleaks is required for this suite"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL - jq is required for this suite (the stub runs real jq)"; exit 1; }
REPORT_REL=$(bash "$LC" report-path)
ISS="$SKILL/scripts/lib/issues.sh"
TAB=$(printf '\t')
export LAUNCH_CHECK_PAUSE=0
check "the 1 s pause between writes is forced to 0 for the suite" test "$LAUNCH_CHECK_PAUSE" = 0

# ---------------------------------------------------------------- harness: stub, tracker views, run helpers
BIN="$SCRATCH/bin"; mkdir -p "$BIN"; cp "$SKILL/test/gh-stub.sh" "$BIN/gh"; chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"
ST="$SCRATCH/st"
stub_reset() { # stub_reset <slug> [visibility] [fork true|false]
  rm -rf "${ST:?}"; mkdir -p "$ST"
  jq -n --arg s "$1" --arg v "${2:-private}" --argjson f "${3:-false}" \
    '{full_name:$s,name:($s|split("/")[1]),owner:{login:($s|split("/")[0])},visibility:$v,archived:false,has_issues:true,fork:$f,permissions:{push:true}}' > "$ST/repo.json"
  printf '[]\n' > "$ST/labels.json"; printf '[]\n' > "$ST/issues.json"
  export GH_STUB_STATE="$ST"
}
calls_reset() { rm -f "$ST/calls.log" "$ST/pages.log" "$ST/violations.log" "$ST/refused.log"; }
cj() { local f=$1; if [ -s "$ST/calls.log" ]; then jq -sr "$f" "$ST/calls.log"; else printf '[]' | jq -r "$f"; fi; }
n_calls() { cj 'length'; }
n_writes() { cj '[.[]|select(.class=="write")]|length'; }
n_post() { cj "[.[]|select(.method==\"$1\" and (.path|test(\"$2\")))]|length"; }
tr_q() { jq -r "$1" "$ST/issues.json"; }
EPICSEL='select(.labels|map(.name)|index("lc:epic"))'
items_n() { tr_q "[.[]|select(.labels|map(.name)|index(\"lc:epic\")|not)]|length"; }
epics_n() { tr_q "[.[]|$EPICSEL]|length"; }
epic_body_to() { jq -j "[.[]|$EPICSEL][0].body" "$ST/issues.json" > "$1"; }
marker_n() { tr_q "[.[]|select((.body // \"\")|contains(\"<!-- launch-check:gap=$1 -->\"))]|length"; }
max_dup() { tr_q '[.[]|(.body // "")|scan("<!-- launch-check:gap=[A-Z]+-[A-Za-z0-9-]+ -->")]|group_by(.)|map(length)|max // 0'; }
linked_n() { tr_q '[.[]|select(.parent != null)]|length'; }
seed() { # seed <number> <state> <login> <labels-csv> <body-text|NULL>
  local lj
  lj=$(printf '%s' "$4" | jq -R 'split(",")|map(select(.!=""))|map({name:.})')
  jq -c --argjson n "$1" --arg st "$2" --arg login "$3" --argjson l "$lj" --arg b "$5" \
    '. + [{number:$n,id:(4000000000+$n*13),state:$st,title:"seeded",body:(if $b=="NULL" then null else $b end),labels:$l,user:{login:$login},parent:null}]' "$ST/issues.json" > "$ST/i.new" && mv "$ST/i.new" "$ST/issues.json"
}
seed_label() { jq -c --arg n "$1" --arg c "$2" '. + [{name:$n,color:$c,description:"seeded"}]' "$ST/labels.json" > "$ST/l.new" && mv "$ST/l.new" "$ST/labels.json"; }
tracker_edit() { jq -c "$1" "$ST/issues.json" > "$ST/i.new" && mv "$ST/i.new" "$ST/issues.json"; }
kv() { awk -v m="$2" -v k="$3" '$1==m { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } }' "$1"; }
lcs() { # like lc(), but against the script in LCS (a sandbox copy for the mutation battery)
  env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR -u GIT_NAMESPACE \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
    bash "${LCS:-$LC}" "$@"
}
# with NAME=value... -- command...: run a function in THIS shell with variables exported, then restore them (a subshell would lose RC and OUT)
with() {
  local -a names=() olds=() was=(); local n i
  while [ "$1" != "--" ]; do
    n=${1%%=*}; names+=("$n")
    if [ -n "${!n+x}" ]; then was+=(1); olds+=("${!n}"); else was+=(0); olds+=(""); fi
    export "$1"; shift
  done
  shift; "$@"
  local rc=$?
  for i in "${!names[@]}"; do if [ "${was[$i]}" = 1 ]; then export "${names[$i]}=${olds[$i]}"; else unset "${names[$i]}"; fi; done
  return $rc
}
RC=0; OUT=""; SEEN_REASONS=""; N=0; CRN=0
runi() { local name=$1; shift; OUT="$SCRATCH/$name.out"; lcs issues "$@" > "$OUT" 2>&1; RC=$?; }
abort_is() { # abort_is <rc> <reason> [file]: exit code AND marker, both (the report-only exit 0 path can never pass as an abort)
  local f=${3:-$OUT}; SEEN_REASONS="$SEEN_REASONS $2"
  [ "$RC" = "$1" ] && grep -q "^SOLEUR_LAUNCH_CHECK_ABORT reason=$2\( \|\$\)" "$f"
}
lacks() { ! grep -qF -- "$1" "$OUT"; }
# autolink shapes outside code spans: a user mention, owner/repo#N, an issue URL, a bare #N, GH-N, a 7-40 hex run. (Same lint in wording.test.sh.)
autolink_hits() { sed -e 's/`[^`]*`//g' "$@" | grep -nE '(^|[^A-Za-z0-9_./-])@[A-Za-z0-9_-]|[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+|https?://[^ ]*/(issues|pull)/[0-9]+|(^|[^A-Za-z0-9&])#[0-9]+|GH-[0-9]+|(^|[^A-Za-z0-9_-])[0-9a-f]{7,40}($|[^A-Za-z0-9_-])'; }
autolink_clean() { ! autolink_hits "$@" >/dev/null; }
file_and_clean() { [ -f "$1" ] && autolink_clean "$1"; }
gl_only_secret() { printf '%s%s' 'npm_' 'aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bD1fH3jK5'; }   # matched by gitleaks and NOT by the sentinel
stub_secret() { printf '%s%s' 'ghp_' 'Q3nW8tY1kD6vB2xM9cL5hZ7pR4aE0sJ2fG1u'; }      # what the stub prints on stderr for GH_STUB_FAIL_KIND=secret
outside() { awk 'BEGIN { s = 0 } { l = $0; sub(/\r$/, "", l) } l == "<!-- launch-check:begin -->" { s = 1; next } l == "<!-- launch-check:end -->" { s = 0; next } !s { print }' "$1"; }
export -f outside
export ST; export -f kv cj   # used inside `bash -c` check bodies

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
verbs=$(grep -rnE 'gh[[:space:]]+(issue|label|pr)([[:space:]]|$)' "$SKILL/scripts" "$SKILL/references" "$SKILL/SKILL.md" 2>/dev/null || true)
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
SAMPLE="$SKILL/test/fixtures/plan-sample"
check "the sample plan's issue body passes the autolink lint" file_and_clean "$SAMPLE/issues/CI-01.md"
check "the sample epic.md carries the epic, begin and end markers exactly once each" bash -c '[ "$(grep -c "launch-check:epic" "$1")" = 1 ] && [ "$(grep -c "launch-check:begin" "$1")" = 1 ] && [ "$(grep -c "launch-check:end" "$1")" = 1 ]' _ "$SAMPLE/epic.md"

# ---------------------------------------------------------------- 2. fixtures: one rendered report, copied per case
BASE=$(fx_minimal base); gitq "$BASE" remote add origin https://github.com/acme/demo.git
FACTS="$SCRATCH/facts.tsv"; scan_to "$BASE" "$FACTS"
JUD="$SCRATCH/judged.tsv"; printf '# judged\n' > "$JUD"
lc render --target "$BASE" --facts "$FACTS" --judged "$JUD" > "$SCRATCH/base.render" 2>&1
check "fixture: the base report is written and verifies" bash -c 'x=$(bash "$1" verify-report --file "$2"); grep -q REPORT_OK <<<"$x"' _ "$LC" "$BASE/$REPORT_REL"
newcase() { N=$((N + 1)); R="$SCRATCH/case$N"; cp -R "$BASE" "$R"; stub_reset acme/demo private; PLAN=""; }
only_first() { # only_first <repo> <K>: accept every open finding after the first K, so exactly K remain to file
  local rep="$1/$REPORT_REL"
  awk -v k="$2" '/^```launch-check-state$/ {f=1} /^```$/ && f {f=0} f && /^finding [A-Z]+-[A-Za-z0-9-]+ open$/ { if (++n > k) { print $1 " " $2 " accepted 2026-11-03 fixture-accept"; next } } {print}' "$rep" > "$rep.new" && mv "$rep.new" "$rep"
}
only_ids() { # only_ids <repo> <ID...>: accept every open finding except the named ones
  local rep="$1/$REPORT_REL" keep; shift; keep=" $* "
  awk -v keep="$keep" '/^```launch-check-state$/ {f=1} /^```$/ && f {f=0} f && /^finding [A-Z]+-[A-Za-z0-9-]+ open$/ { if (index(keep, " " $2 " ") == 0) { print $1 " " $2 " accepted 2026-11-03 fixture-accept"; next } } {print}' "$rep" > "$rep.new" && mv "$rep.new" "$rep"
}
prev() { runi "pv$N" --preview --target "$R" --facts "$FACTS" --judged "$JUD" --plan-out "$SCRATCH/po$N" "$@"; PLAN=$(kv "$OUT" SOLEUR_LAUNCH_CHECK_ISSUES_PLAN plan); }
plan_n() { awk -F'\t' 'NF == 6 && $1 != "id" && $5 == "create"' "$PLAN/plan.tsv" 2>/dev/null | wc -l | tr -d ' '; }
create_ids() { awk -F'\t' 'NF == 6 && $1 != "id" && $5 == "create" {print $1}' "$PLAN/plan.tsv" 2>/dev/null; }
create() { CRN=$((CRN + 1)); runi "cr$N.$CRN" --create --target "$R" --facts "$FACTS" --judged "$JUD" --plan "$PLAN" --confirm-repo "${CREPO:-acme/demo}" --confirm-count "${CCOUNT:-$(plan_n)}" "$@"; }
mode700() { [ "$(ls -ld "$1" 2>/dev/null | cut -c1-10)" = "drwx------" ]; }
table_rows_present() { # every create row of the plan appears in the preview output as "ID | severity | title"
  local out=$1 plan=$2 n=0 id sev dom cls act title
  while IFS="$TAB" read -r id sev dom cls act title; do
    grep -qF -- "$id | $sev | $title" "$out" || return 1; n=$((n + 1))
  done < <(awk -F'\t' 'NF == 6 && $1 != "id" && $5 == "create"' "$plan")
  [ "$n" -ge 1 ]
}
bodies_clean() { local f n=0; for f in "$1"/issues/*.md; do [ -f "$f" ] || return 1; autolink_clean "$f" || return 1; n=$((n + 1)); done; [ "$n" -ge 1 ]; }
sent_bodies_match() { # every body the stub received on an issue create is byte-identical to a file of the plan that was scanned
  local n=0 seq b ok f
  while IFS= read -r seq; do
    b="$ST/bodies/$seq-body"; ok=0
    for f in "$PLAN"/issues/*.md "$PLAN/epic.md"; do cmp -s "$b" "$f" && { ok=1; break; }; done
    [ "$ok" = 1 ] || return 1; n=$((n + 1))
  done < <(cj '.[]|select(.method=="POST" and (.path|test("/issues$")))|.seq')
  [ "$n" -ge 1 ]
}

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
expect_capped=$(awk -F' [|] ' '/^\| [A-Z]+-[A-Za-z0-9-]+ [|] (critical|high|medium|low) [|]/ { id = substr($1, 3); s = $2; r = (s=="critical")?1:(s=="high")?2:(s=="medium")?3:4; print r "\t" id }' "$R/$REPORT_REL" | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 | tail -n 5 | cut -f2 | LC_ALL=C sort | tr '\n' ' ')
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
# Sandbox copy of the skill for the mutation battery, with seams injected before main: a gate bypass and a live-lookup bypass, both inert unless set.
mk_sbx() { # mk_sbx <name> -> prints the sandbox launch-check.sh
  local d="$SCRATCH/sbx-$1/plugins/soleur" s
  mkdir -p "$d/skills/launch-check"; ln -s "$PLUGIN/.claude-plugin" "$d/.claude-plugin"
  for s in incident verification-scaffold; do ln -s "$PLUGIN/skills/$s" "$d/skills/$s"; done
  cp -R "$SKILL/scripts" "$SKILL/references" "$d/skills/launch-check/"
  printf '%s' "$d/skills/launch-check/scripts/launch-check.sh"
}
inject() { awk -v f="$2" '/^main "\$@"$/ { while ((getline l < f) > 0) print l } { print }' "$1" > "$1.new" && mv "$1.new" "$1"; }
cat > "$SCRATCH/seams.sh" <<'EOF'
# test seams, inert unless their variable is set
if declare -F lc_emit_checked >/dev/null; then
  eval "$(declare -f lc_emit_checked | sed '1s/^lc_emit_checked/lc__real_emit_checked/')"
  lc_emit_checked() { if [ -n "${LC_TEST_NOGATE:-}" ]; then return 0; fi; lc__real_emit_checked "$@"; }
fi
if declare -F lc_issues_live >/dev/null; then
  eval "$(declare -f lc_issues_live | sed '1s/^lc_issues_live/lc__real_issues_live/')"
  lc_issues_live() { if [ -n "${LC_TEST_NOLIVE:-}" ]; then : > "$WORK/live.tsv"; return 0; fi; lc__real_issues_live "$@"; }
fi
EOF
SB0=$(mk_sbx pristine); inject "$SB0" "$SCRATCH/seams.sh"
check "sandbox: the pristine copy parses and has the seams injected" bash -c 'bash -n "$1" && grep -q LC_TEST_NOGATE "$1"' _ "$SB0"
LCS="$SB0"
hostile_facts() { # hostile_facts <out> <evidence>: the first non-count-only gap gets the evidence; prints its id
  local id; id=$(awk -F'\t' '$2 == "gap" && $1 !~ /^SEC-0[12]$/ {print $1; exit}' "$FACTS")
  awk -F'\t' -v OFS='\t' -v id="$id" -v ev="$2" '$1 == id { $3 = ev } { print }' "$FACTS" > "$1"; printf '%s' "$id"
}
OFACTS="$FACTS"
newcase; HID=$(hostile_facts "$SCRATCH/hostile.tsv" "$(planted_secret)"); only_ids "$R" "$HID"
FACTS="$SCRATCH/hostile.tsv"; with LC_TEST_NOGATE=1 -- prev; calls_reset
check "G2 setup: with the gate bypassed in preview the plan really carries the planted token (a suite with no plant asserts nothing)" bash -c '[ -n "$2" ] && grep -rqF -- "$1" "$2"' _ "$(planted_secret)" "$PLAN"
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
# a pattern only gitleaks matches, with a gitleaks wrapper that passes everything until the real one is switched on
cat > "$SCRATCH/gl-toggle.sh" <<'EOF'
#!/usr/bin/env bash
# passes everything until $GL_ON exists, then delegates to the real gitleaks; records its working directory and argv
printf '%s\t%s\n' "$PWD" "$*" >> "${GL_LOG:-/dev/null}"
if [ -e "${GL_ON:-/nonexistent}" ]; then exec "$GL_REAL" "$@"; fi
case "${1:-}" in version) echo 8.24.2; exit 0 ;; esac
exit 0
EOF
chmod +x "$SCRATCH/gl-toggle.sh"
export GL_REAL; GL_REAL=$(command -v gitleaks); export GL_LOG="$SCRATCH/gl.calls" GL_ON="$SCRATCH/gl-on"
rm -f "$GL_ON" "$GL_LOG"
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
check "G2.6: the hostile facts path and the token appear in no plan file, recorded argv, stored body or output" bash -c '! grep -rq "config\.js" "$1" && ! grep -rq "ghp_" "$1" && ! grep -rq "config\.js" "$2" && ! grep -q "config\.js" "$3"' _ "$PLAN" "$ST" "$OUT"
newcase; only_ids "$R" CI-01; prev
check "G2.7: the domain label Tests & CI/CD reaches the CI-01 body intact (no substitution mangling)" bash -c 'grep -qF "Tests & CI/CD" "$1/issues/CI-01.md"' _ "$PLAN"
check "G2: rendered bodies carry no autolink shape outside a code span (owner/repo#N, bare #N, @name, GH-N, hex run)" bodies_clean "$GOODPLAN"
newcase; HID4=$(hostile_facts "$SCRATCH/types.tsv" "node_modules/@types/node/index.d.ts"); only_ids "$R" "$HID4"
FACTS="$SCRATCH/types.tsv"; prev; FACTS="$OFACTS"
check "G2.8: evidence node_modules/@types/node/index.d.ts is rendered inside a code span and mentions no one" bash -c 'grep -qF "\`node_modules/@types/node/index.d.ts\`" "$1/issues/$2.md" && ! sed -e "s/\`[^\`]*\`//g" "$1/issues/$2.md" | grep -q "@"' _ "$PLAN" "$HID4"

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

# ---------------------------------------------------------------- 7. Guard 3: idempotency and resume
full_case() { newcase; only_first "$R" "$1"; prev; }
full_case 7; calls_reset
with GH_STUB_FAIL_AFTER=3 -- create; FIRST_OUT="$OUT"
check "G3.1: the 4th item create fails -> created=3 and the failed ids are named" bash -c '[ "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES created)" = 3 ] && [ -n "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES failed)" ] && [ "$(kv "$1" SOLEUR_LAUNCH_CHECK_ISSUES failed)" != "-" ]' _ "$FIRST_OUT"
check "G3.1: ... and the run aborts issues-incomplete (rc 2)" abort_is 2 issues-incomplete "$FIRST_OUT"
check "G3.1: the fake tracker holds 3 items and one epic after the failure (state read from the tracker)" bash -c '[ "$1" = 3 ] && [ "$2" = 1 ]' _ "$(items_n)" "$(epics_n)"
check "G3.1: the abort and the summary carry plan=<dir> and phase=, and the exact resume command" bash -c 'grep -q "plan=" "$1" && grep -q "phase=" "$1" && grep -q -- "--create" "$1" && grep -q -- "--plan" "$1"' _ "$FIRST_OUT"
calls_reset; create
check "G3.1: re-running the same plan completes (rc 0)" test "$RC" = 0
check "G3.1: the tracker holds 7 items and exactly one epic, each id once, all linked" bash -c '[ "$1" = 7 ] && [ "$2" = 1 ] && [ "$3" = 1 ] && [ "$4" = 7 ]' _ "$(items_n)" "$(epics_n)" "$(max_dup)" "$(linked_n)"
check "G3.1: the re-run created only the 4 missing issues (issue POSTs == 4)" test "$(n_post POST 'repos/acme/demo/issues$')" = 4
check "G3.1: created.tsv in the plan directory lists what the runs created and the plan directory survives (mode 700)" bash -c '[ -s "$1/created.tsv" ] && [ "$(ls -ld "$1" | cut -c1-10)" = drwx------ ]' _ "$PLAN"
calls_reset; create; calls_reset; create
check "G3 must-PASS: a re-run of an already complete plan records zero writes (no PATCH for a byte-identical section)" bash -c '[ "$1" = 0 ] && [ "$2" = 7 ]' _ "$(n_writes)" "$(items_n)"
full_case 7; calls_reset
with GH_STUB_TRANSPORT_ERROR_AFTER_CREATE=2 -- create
check "G3.2: a transport error right after a create (unknown outcome) ends the run non-zero with the created issues in the tracker" bash -c '[ "$1" != 0 ] && [ "$2" -ge 2 ]' _ "$RC" "$(items_n)"
before_items=$(items_n); calls_reset; create
check "G3.2: the re-run creates no duplicate and links the orphan: 7 items, 7 links, each marker once, at least 2 items existed before" bash -c '[ "$1" = 7 ] && [ "$2" = 7 ] && [ "$3" = 1 ] && [ "$4" -ge 2 ]' _ "$(items_n)" "$(linked_n)" "$(max_dup)" "$before_items"
check "G3.2: no child was linked by more than one POST in the re-run" bash -c '[ "$1" -le 1 ] && [ "$2" = 7 ]' _ "$(cj '[.[]|select(.method=="POST" and (.path|test("sub_issues$")))|.fields[]|select(.k=="sub_issue_id")|.v]|group_by(.)|map(length)|max // 0')" "$(linked_n)"
full_case 7; CLOSED_ID=$(create_ids | sed -n 1p); ORPH_ID=$(create_ids | sed -n 2p)
stub_reset acme/demo private; seed_label lc:launch-check ededed
seed 301 closed stub-user lc:launch-check "<!-- launch-check:gap=$CLOSED_ID -->"; seed 302 open stub-user lc:launch-check "<!-- launch-check:gap=$ORPH_ID -->"
prev
check "G3.3: the preview reports the closed issue by number" grep -q "#301" "$OUT"
calls_reset; create
orph_db=$(tr_q '[.[]|select(.number==302)|.id]|first'); orph_links=$(cj "[.[]|select(.method==\"POST\" and (.path|test(\"sub_issues\$\")))|.fields[]|select(.k==\"sub_issue_id\" and .v==\"$orph_db\")]|length")
check "G3.3: a closed marked issue is not recreated (one carrier of its marker, still closed)" bash -c '[ "$1" = 1 ] && [ "$2" = closed ]' _ "$(marker_n "$CLOSED_ID")" "$(tr_q '[.[]|select(.number==301)|.state]|first')"
check "G3.4: an open marked issue with no parent is not recreated and is linked exactly once" bash -c '[ "$1" = 1 ] && [ "$2" = 1 ] && [ "$3" = 302 ]' _ "$(marker_n "$ORPH_ID")" "$orph_links" "$(tr_q '[.[]|select(.parent != null and .number==302)|.number]|first')"
full_case 7; stub_reset acme/demo private; seed_label lc:severity-high 123456; prev; calls_reset; create
check "G3.6: a pre-existing lc:severity-high label is untouched: no label write names it and its colour is unchanged" bash -c '[ "$(cj "[.[]|select(.method==\"POST\" and (.path|test(\"/labels\$\")) and (.fields[]|select(.k==\"name\" and .v==\"lc:severity-high\")))]|length")" = 0 ] && [ "$(jq -r "[.[]|select(.name==\"lc:severity-high\")|.color]|first" "$1/labels.json")" = 123456 ]' _ "$ST"
check "G3.6 control: absent labels were created (lc:launch-check and lc:epic exist now)" bash -c 'jq -e "map(.name)|index(\"lc:launch-check\") != null and index(\"lc:epic\") != null" "$1/labels.json" >/dev/null' _ "$ST"
full_case 7; D_ID=$(create_ids | sed -n 1p); A_ID=$(create_ids | sed -n 2p); B_ID=$(create_ids | sed -n 3p)
stub_reset acme/demo private; seed 401 open stub-user lc:launch-check "<!-- launch-check:gap=$D_ID -->"; seed 402 open stub-user lc:launch-check "<!-- launch-check:gap=$D_ID -->"
seed 403 open stub-user lc:launch-check "<!-- launch-check:gap=$A_ID --> <!-- launch-check:gap=$B_ID -->"
prev; calls_reset; create
check "G3.7: duplicates of one id resolve to the lowest number (no create for it) and a two-marker body is ignored: 6 item creates + the epic" test "$(n_post POST 'repos/acme/demo/issues$')" = 7
full_case 3; stub_reset acme/demo private; seed 501 closed stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"
prev
check "G3.8: preview prints a plain warning for a closed epic" bash -c 'grep -qi "closed" "$1" && grep -qi "epic" "$1"' _ "$OUT"
calls_reset; create
check "G3.8: create writes nothing and says how to recover (reopen it or remove the lc:epic label)" bash -c '[ "$1" = 0 ] && grep -qi "reopen" "$2"' _ "$(n_writes)" "$OUT"
check "G3.8: create aborts epic-closed (rc 2)" abort_is 2 epic-closed
full_case 3; stub_reset acme/demo private; seed 511 open stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"; seed 512 open stub-user lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"
prev; calls_reset; create
check "G3.8: two labelled epic candidates write nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G3.8: ... and abort epic-ambiguous (rc 2)" abort_is 2 epic-ambiguous
full_case 3; stub_reset acme/demo private; seed 521 open someone-else lc:launch-check,lc:epic "$(cat "$SAMPLE/epic.md")"
prev; calls_reset; create
check "G3.12: an epic authored by another login writes nothing and names epic-author" bash -c '[ "$1" = 0 ] && grep -q "epic-author" "$2"' _ "$(n_writes)" "$OUT"
check "G3.12: ... and aborts plan-invalid (rc 2)" abort_is 2 plan-invalid
for st in 404 422; do
  full_case 4; calls_reset; with GH_STUB_SUBISSUE=$st -- create
  check "G3.9 (UNVERIFIED-STUB-ONLY $st): the first failed link latches the run to the task list: one link call, rc 0, fallback=task-list" bash -c '[ "$1" = 1 ] && [ "$2" = 0 ] && [ "$(kv "$3" SOLEUR_LAUNCH_CHECK_ISSUES fallback)" = task-list ]' _ "$(n_post POST 'sub_issues$')" "$RC" "$OUT"
  epic_body_to "$SCRATCH/epic.fb"
  check "G3.9 ($st): the epic section lists every created item as an unchecked task line" bash -c '[ "$(grep -c "^- \[ \] #[0-9]" "$1")" = 4 ]' _ "$SCRATCH/epic.fb"
done
full_case 3; one=$(create_ids | sed -n 1p); sed "s/^finding $one open\$/finding $one accepted 2026-11-03 accepted after the preview/" "$R/$REPORT_REL" > "$R/r.new" && mv "$R/r.new" "$R/$REPORT_REL"
calls_reset; create
check "G3.10: accepting a finding after the preview makes create write nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G3.10: ... and abort report-stale (rc 2)" abort_is 2 report-stale
full_case 3; jq '.visibility="public"' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; calls_reset; create
check "G3: a plan recorded PRIVATE against a LIVE PUBLIC repo writes nothing" bash -c '[ "$1" = 0 ]' _ "$(n_writes)"
check "G3: ... and aborts confirm-public-required (rc 2)" abort_is 2 confirm-public-required
create --confirm-public
check "G3: --confirm-public makes the same run proceed" bash -c '[ "$1" = 0 ] && [ "$2" -gt 0 ]' _ "$RC" "$(n_writes)"
full_case 3; jq '.visibility="internal"' "$ST/repo.json" > "$ST/r.new" && mv "$ST/r.new" "$ST/repo.json"; calls_reset; create
check "G3: an internal repository is gated like a public one (confirm-public-required)" abort_is 2 confirm-public-required
full_case 3; calls_reset; create
check "G1 must-PASS: a PRIVATE repository runs without --confirm-public" bash -c '[ "$1" = 0 ]' _ "$RC"
full_case 3; calls_reset; with GH_STUB_LIST=fail -- create
check "G3.11: a failed listing writes nothing and says phase=lookup (never read as none found)" bash -c '[ "$1" = 0 ] && grep -q "phase=lookup" "$2"' _ "$(n_writes)" "$OUT"
check "G3.11: ... and aborts issues-incomplete (rc 2)" abort_is 2 issues-incomplete
calls_reset; with GH_STUB_LIST=malformed -- create
check "G3.11 (UNVERIFIED-STUB-ONLY): malformed listing output writes nothing and says phase=lookup" bash -c '[ "$1" = 0 ] && grep -q "phase=lookup" "$2"' _ "$(n_writes)" "$OUT"
stub_reset acme/demo private; seed 601 open stub-user lc:launch-check NULL; seed 602 open stub-user lc:launch-check ''; seed 603 open stub-user lc:launch-check 'no marker here'
calls_reset; create
check "G3.11 (UNVERIFIED-STUB-ONLY, gojq null handling): null, empty and marker-less bodies are ignored cleanly and the run completes" bash -c '[ "$1" = 0 ] && [ "$2" = 3 ]' _ "$RC" "$(tr_q '[.[]|select(.number>=100 and .number<600)|select(.labels|map(.name)|index("lc:epic")|not)]|length')"
full_case 3; ID3=$(create_ids | sed -n 3p); stub_reset acme/demo private
for i in 1 2 3 4 5; do seed $((700 + i)) closed stub-user lc:launch-check "<!-- launch-check:gap=ZZ-0$i -->"; done; seed 706 closed stub-user lc:launch-check "<!-- launch-check:gap=$ID3 -->"
calls_reset; with GH_STUB_PER_PAGE=2 -- create
maxpages=$(awk -F'\t' '{ if ($2 + 0 > m) m = $2 + 0 } END { print m + 0 }' "$ST/pages.log" 2>/dev/null)
check "G3: a listing forced onto at least 3 pages is read completely (the id on the last page is not recreated)" bash -c '[ "$1" -ge 3 ] && [ "$2" = 1 ]' _ "$maxpages" "$(marker_n "$ID3")"
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; calls_reset; with LC_TEST_NOLIVE=1 -- create
check "G3.5 mutation: with the live lookup removed from the re-run, duplicates appear (so the resume rows are sensitive)" bash -c '[ "$1" -ge 2 ] || [ "$2" -gt 7 ]' _ "$(max_dup)" "$(items_n)"
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=2 GH_STUB_FAIL_KIND=ratelimit -- create
check "G3: a rate-limit failure names the rate limit and the re-run line" bash -c 'grep -qi "rate" "$1" && grep -q -- "--create" "$1"' _ "$OUT"
check "G3: ... and stops the run issues-incomplete (rc 2)" abort_is 2 issues-incomplete
calls_reset; create
check "G3: the re-run after a rate limit completes with 7 items" bash -c '[ "$1" = 0 ] && [ "$2" = 7 ]' _ "$RC" "$(items_n)"
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=1 GH_STUB_FAIL_KIND=secret -- create
check "G2.12: a secret-shaped string on the stub's stderr never reaches stdout or stderr of the run, nor the raw HTTP line" bash -c '! grep -qF -- "$1" "$2" && ! grep -qF "token=" "$2" && ! grep -q "HTTP 502" "$2"' _ "$(stub_secret)" "$OUT"
check "G2.12: a failed write still yields the closed-token summary line" grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES " "$OUT"
check "G2: every printed line of a failed create passes lc_scrub (no tab or carriage return)" bash -c 'grep -q "^SOLEUR_LAUNCH_CHECK_ISSUES " "$1" && ! grep -q "$(printf "\t")" "$1" && ! grep -q "$(printf "\r")" "$1"' _ "$OUT"
full_case 3; TMPD="$SCRATCH/tmpd"; mkdir -p "$TMPD"; with TMPDIR="$TMPD" -- create
check "no lc-work or lc-gate temp file is left behind after a create (only the plan directory survives)" bash -c '[ "$1" = 0 ] && [ -z "$(ls -A "$2")" ]' _ "$RC" "$TMPD"

# ---------------------------------------------------------------- 8. Guard 4: epic edits are confined to the marked section
custom_epic() { # customer text before and after the markers, using the words begin and end without the marker syntax
  tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= ("CUSTOMER-TOP begin and end are just words here\n" + . + "\nCUSTOMER-BOTTOM\n")'
}
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic; epic_body_to "$SCRATCH/e.before"; calls_reset; create; epic_body_to "$SCRATCH/e.after"
check "G4.1: customer text before and after the markers is byte-identical after a re-run that rewrote the section" bash -c 'outside "$1" > "$3"; outside "$2" > "$4"; cmp -s "$3" "$4" && grep -q CUSTOMER-TOP "$4" && grep -q CUSTOMER-BOTTOM "$4"' _ "$SCRATCH/e.before" "$SCRATCH/e.after" "$SCRATCH/o1" "$SCRATCH/o2"
check "G4.1 harness row: the re-run really rewrote the section (a PATCH was recorded and the body changed)" bash -c '[ "$1" -ge 1 ] && ! cmp -s "$2" "$3"' _ "$(n_post PATCH 'issues/[0-9]+$')" "$SCRATCH/e.before" "$SCRATCH/e.after"
check "G4 must-PASS: customer text containing the words begin and end (without marker syntax) survives" grep -q "CUSTOMER-TOP begin and end are just words here" "$SCRATCH/e.after"
order=$(cj '[.[]|select(.path|test("issues/[0-9]+$"))|.method]|join(",")')
check "G4: the call order on the epic is GET then PATCH (the body is read just before the splice)" bash -c 'case "$1" in *GET*PATCH*) exit 0 ;; esac; exit 1' _ "$order"
for mode in get write; do
  full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic; calls_reset; with GH_STUB_EDIT_EPIC_BETWEEN=$mode -- create; epic_body_to "$SCRATCH/e.mid"
  check "G4.2: a customer edit made mid-run ($mode) survives the splice (the epic body is re-read just before it)" bash -c 'grep -q CUSTOMER-EDIT-MIDRUN "$1" && [ -s "$2/events.log" ]' _ "$SCRATCH/e.mid" "$ST"
done
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= sub("<!-- launch-check:end -->"; "")'
calls_reset; create
check "G4.3: a deleted end marker -> no PATCH is recorded and the summary says epic-section=markers-damaged" bash -c '[ "$1" = 0 ] && [ "$(kv "$2" SOLEUR_LAUNCH_CHECK_ISSUES created)" != "" ] && [ "$(kv "$2" SOLEUR_LAUNCH_CHECK_ISSUES epic-section)" = markers-damaged ]' _ "$(n_post PATCH 'issues/[0-9]+$')" "$OUT"
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= (. + "\n<!-- launch-check:begin -->\n")'
calls_reset; create
check "G4.4: a duplicated begin marker -> no PATCH is recorded (the run itself created the items)" bash -c '[ "$1" = 0 ] && [ "$2" = 7 ]' _ "$(n_post PATCH 'issues/[0-9]+$')" "$(items_n)"
full_case 7; calls_reset; with GH_STUB_FAIL_AFTER=3 GH_STUB_CRLF=1 -- create; custom_epic
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= gsub("\r?\n"; "\r\n")'
epic_body_to "$SCRATCH/c.before"; create; epic_body_to "$SCRATCH/c.after"
check "G4.5: an epic stored with CRLF: the section is rewritten and the CRLF bytes outside it are preserved" bash -c 'outside "$1" > "$3"; outside "$2" > "$4"; cmp -s "$3" "$4" && grep -q "$(printf "\r")" "$4" && ! cmp -s "$1" "$2"' _ "$SCRATCH/c.before" "$SCRATCH/c.after" "$SCRATCH/o3" "$SCRATCH/o4"
full_case 4; with GH_STUB_SUBISSUE=404 -- create
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= sub("- \\[ \\] #"; "- [x] #")'
calls_reset; with GH_STUB_SUBISSUE=404 -- create; epic_body_to "$SCRATCH/t.after"
check "G4.9: a task line the customer ticked stays ticked after a re-run" bash -c '[ "$(grep -c "^- \[x\] #" "$1")" -ge 1 ]' _ "$SCRATCH/t.after"
check "G4: the marked section carries the last run's counts (the record that outlives the terminal)" bash -c 'awk "/<!-- launch-check:begin -->/{f=1;next} /<!-- launch-check:end -->/{f=0} f" "$1" | grep -qiE "created|skipped|failed"' _ "$SCRATCH/t.after"
full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic
tracker_edit '(.[] | select(.labels|map(.name)|index("lc:epic")) | .body) |= (. + "\ncustomer pasted '"$(gl_only_secret)"'\n")'
calls_reset; : > "$GL_ON"; with LAUNCH_CHECK_GITLEAKS="$SCRATCH/gl-toggle.sh" -- create; rm -f "$GL_ON"
check "G4 carve-out: customer-owned bytes outside the markers are carried unchanged and not re-judged (rc 0, the text is still in the epic)" bash -c '[ "$1" = 0 ] && jq -r "[.[]|select(.labels|map(.name)|index(\"lc:epic\"))][0].body" "$2" | grep -qF "customer pasted"' _ "$RC" "$ST/issues.json"
cat > "$SCRATCH/splice-mut.sh" <<'EOF'
lc_epic_splice() { cat "$2"; }
EOF
SB1=$(mk_sbx splice); inject "$SB1" "$SCRATCH/seams.sh"; inject "$SB1" "$SCRATCH/splice-mut.sh"
check "G4.6 mutation landed (the sandbox differs from the pristine copy and still parses)" bash -c 'bash -n "$1" && ! cmp -s "$1" "$2"' _ "$SB1" "$SB0"
splice_scn() { # splice_scn <lc script>: customer text outside the markers survives a rewrite (return 0 = the property holds)
  LCS="$1"; full_case 7; with GH_STUB_FAIL_AFTER=3 -- create; custom_epic; create; epic_body_to "$SCRATCH/s.after"; grep -q CUSTOMER-BOTTOM "$SCRATCH/s.after"
}
splice_scn "$SB0"; rc=$?
check "G4.6 control: the pristine copy keeps the customer text" test "$rc" = 0
splice_scn "$SB1"; rc=$?
check "G4.6 mutation: a splice that replaces the whole body loses the customer text (caught)" test "$rc" != 0
LCS="$SB0"

# ---------------------------------------------------------------- 9. the exit-code table: every fail_loud reason was exercised by a row above
check "every fail_loud abort reason was exercised by a marker-and-exit-code row" bash -c 'miss=""; for r in headless-write-refused report-missing report-stale plan-missing plan-invalid plan-repo-mismatch confirm-public-required redaction-hit epic-closed epic-ambiguous issues-unavailable write-shape-refused issues-incomplete; do case " $1 " in *" $r "*) ;; *) miss="$miss $r" ;; esac; done; [ -z "$miss" ]' _ "$SEEN_REASONS"
finish 218
