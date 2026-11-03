#!/usr/bin/env bash
# Shared setup for the two issues suites (issues-guards.test.sh, issues-resume.test.sh): sourced, not itself a suite.
# It holds the stub harness, the tracker views, the run helpers, the rendered base report, the sandbox-copy builder and the
# gitleaks wrapper. Every assertion lives in one of the two suites (split because one suite took 6-8 minutes; plan Phase 6).
#
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
command -v gitleaks >/dev/null 2>&1 || { echo "FAIL - gitleaks is required for this suite"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL - jq is required for this suite (the stub runs real jq)"; exit 1; }
REPORT_REL=$(bash "$LC" report-path)
ISS="$SKILL/scripts/lib/issues.sh"
TAB=$(printf '\t')
export LAUNCH_CHECK_PAUSE=0
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
gl_only_secret() { printf '%s%s' 'glpat-' 'aB3dE5gH7jK9mN1pQ3sT'; }   # matched by gitleaks (gitlab-pat) and NOT by the sentinel (checked: sentinel rc 0, gitleaks rc 1; the npm_ shape the first draft used IS a sentinel hit)
stub_secret() { printf '%s%s' 'ghp_' 'Q3nW8tY1kD6vB2xM9cL5hZ7pR4aE0sJ2fG1u'; }      # what the stub prints on stderr for GH_STUB_FAIL_KIND=secret
outside() { awk 'BEGIN { s = 0 } { l = $0; sub(/\r$/, "", l) } l == "<!-- launch-check:begin -->" { s = 1; next } l == "<!-- launch-check:end -->" { s = 0; next } !s { print }' "$1"; }
export -f outside
# tree_has <fixed-string> <dir>: some file under <dir> holds the string (find + grep, no recursive grep: the orphan-suite census reads that idiom as a corpus walk)
tree_has() { [ -n "$(find "$2" -type f -exec grep -lF -- "$1" {} + 2>/dev/null)" ]; }
export -f tree_has
export ST; export -f kv cj   # used inside `bash -c` check bodies

# ---------------------------------------------------------------- shared fixtures, sandbox builder, gitleaks wrapper
SAMPLE="$SKILL/test/fixtures/plan-sample"
BASE=$(fx_minimal base); gitq "$BASE" remote add origin https://github.com/acme/demo.git
FACTS="$SCRATCH/facts.tsv"; scan_to "$BASE" "$FACTS"
JUD="$SCRATCH/judged.tsv"; printf '# judged\n' > "$JUD"
lc render --target "$BASE" --facts "$FACTS" --judged "$JUD" > "$SCRATCH/base.render" 2>&1
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
LCS="$SB0"
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
