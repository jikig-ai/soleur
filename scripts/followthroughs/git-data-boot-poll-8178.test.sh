#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/git-data-boot-poll-8178.sh.
#
# Registered EXPLICITLY in scripts/test-all.sh: scripts/followthroughs/ matches no
# SUITE_GLOBS entry, so an unregistered .test.sh is an orphan that never gates (#5417,
# and the #7942 shape the plan's QG4 names).
#
# WHAT THIS PINS. The probe closes #8178, so the load-bearing property is that it can
# reach 0 ONLY on a post-merge dispatch whose poll answered — never on a row, never on a
# run at or before the merge, never on an echoed script line, never on a log it could not
# read. Every arm drives the REAL probe against a PATH-shimmed `gh` that answers from
# per-id fixture files and EXITS 64 on any argv it was not written for, so a probe that
# queries the wrong thing fails here rather than reading an empty answer as "nothing yet"
# (the #7081 stub-argv-fidelity class). `jq` is the real binary.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/git-data-boot-poll-8178.sh"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }

fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Instrument self-test: both counters must move before any verdict is trusted.
_p0=$total; pass "instrument" >/dev/null; _f0=$fails
fail "instrument" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK="$(mktemp -d -t gdbp-8178.XXXXXXXX)"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

MERGED="2026-09-19T12:00:00Z"
RUNS_PATH_PREFIX="repos/jikig-ai/soleur/actions/workflows/apply-web-platform-infra.yml/runs?event=workflow_dispatch&branch=main&created=%3E%3D"

# --- the `gh` shim ----------------------------------------------------------------------
# Answers from $FX (one fixture dir per arm). Every accepted argv shape is spelled out; any
# other exits 64 and is logged, which the arms assert never happens.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/calls"
[[ -n "${GH_TOKEN:-}" ]] || { echo "shim: GH_TOKEN absent" >&2; exit 65; }
answer() { [[ -f "$FX/$1.fail" ]] && { cat "$FX/$1.fail" >&2; exit 1; }; [[ -f "$FX/$1" ]] || exit 1; cat "$FX/$1"; exit 0; }
if [[ "$#" -eq 2 && "$1" == api && "$2" == "repos/jikig-ai/soleur/pulls/8262" ]]; then
  answer pr.json
fi
if [[ "$#" -eq 3 && "$1" == api && "$2" == --paginate ]]; then
  case "$3" in
    "${RUNS_PATH_PREFIX}"*"&per_page=100")
      m="${3#"${RUNS_PATH_PREFIX}"}"; m="${m%&per_page=100}"
      [[ "$m" == "$(jq -r '.merged_at' "$FX/pr.json")" ]] || { echo "shim: created= anchor '$m' is not the PR's merged_at" >&2; printf 'BADARGV %s\n' "$*" >> "$FX/calls"; exit 64; }
      answer runs.json ;;
    repos/jikig-ai/soleur/actions/runs/*/jobs\?per_page=100)
      id="${3#repos/jikig-ai/soleur/actions/runs/}"; id="${id%/jobs?per_page=100}"
      answer "jobs-$id.json" ;;
  esac
fi
if [[ "$#" -eq 7 && "$1" == run && "$2" == view && "$3" == --job && "$5" == --repo && "$6" == jikig-ai/soleur && "$7" == --log ]]; then
  answer "log-$4.txt"
fi
printf 'BADARGV %s\n' "$*" >> "$FX/calls"
exit 64
SHIM
chmod +x "$WORK/bin/gh"

# --- fixture builders -------------------------------------------------------------------
# new_fx <name> — a fresh fixture dir for one arm, with the PR merged at $MERGED.
new_fx() {
  local d="$WORK/fx-$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  : > "$d/calls"
  jq -n --arg m "$MERGED" '{state:"closed", merged_at:$m}' > "$d/pr.json"
  printf '%s' '{"total_count":0,"workflow_runs":[]}' > "$d/runs.json"
}
# add_run <fx> <run_id> <created_at> [event] [branch]
add_run() {
  local d="$1"; assert_fixture_dir "$d"
  jq --argjson id "$2" --arg c "$3" --arg e "${4:-workflow_dispatch}" --arg b "${5:-main}" \
    '.workflow_runs += [{id:$id, created_at:$c, event:$e, head_branch:$b}]' "$d/runs.json" > "$d/runs.tmp" \
    && mv "$d/runs.tmp" "$d/runs.json"
}
# add_job <fx> <run_id> <job_id> <name> <status> <conclusion|null> <started_at> [poll-conclusion]
# The job carries a poll step (the jobs API's steps[]) whose window is POLL_START..POLL_END.
# poll-conclusion defaults to `success`; `absent` omits the step entirely.
POLL_START="2026-09-20T09:59:00Z"; POLL_END="2026-09-20T10:05:00Z"
add_job() {
  local d="$1"; assert_fixture_dir "$d"
  [[ -f "$d/jobs-$2.json" ]] || printf '%s' '{"jobs":[]}' > "$d/jobs-$2.json"
  jq --argjson id "$3" --arg n "$4" --arg s "$5" --arg c "$6" --arg st "$7" --arg pc "${8:-success}" \
     --arg ps "$POLL_START" --arg pe "$POLL_END" \
    '.jobs += [{id:$id, name:$n, status:$s, conclusion:(if $c == "null" then null else $c end), started_at:$st,
                steps:(if $pc == "absent" then [] else
                  [{name:"Terraform apply", conclusion:"success", started_at:"2026-09-20T09:58:00Z", completed_at:$ps},
                   {name:("Poll for the git-data boot-completion signal" + (if $n == "git_data_host_replace" then " (replace)" else "" end)),
                    conclusion:$pc, started_at:$ps, completed_at:$pe}] end)}]' \
    "$d/jobs-$2.json" > "$d/jobs.tmp" && mv "$d/jobs.tmp" "$d/jobs-$2.json"
}
# GH_LOG_BOM — the UTF-8 byte-order mark `gh run view --log` writes at the start of EVERY
# step's log section. NOT decoration and NOT a captured artifact: these are three literal
# bytes (EF BB BF), synthesized here per cq-test-fixtures-synthesized-only.
#
# WHY THE FIXTURE CARRIES IT NOW. It did not, and that omission is why this suite went 86/86
# green against a probe that could not read a single real log. Measured on job 106093730126
# (run 35516692240): the job log carries 15 `##[group]Run` headers and 14 of them begin with
# the BOM — only the job's FIRST section ("Set up job") lacks one, because gh strips the mark
# from the head of the concatenated stream and not from each section it appends. The poll step
# is never the first section, so on a REAL log its header always carries the BOM. A fixture
# that omits it tests a shape gh never emits, and the probe's region extractor — anchored on
# `^[0-9]` after the tab fields are stripped — matched the fixture while failing on every real
# log, returning CANNOT ESTABLISH against the exact evidence it exists to read.
GH_LOG_BOM=$'\357\273\277'
# log_lines_at <fx> <job_id> <job_name> <ts> <line>... — one `<job>\t<step>\t<ts> <line>` per
# arg, the shape `gh run view --job --log` emits (measured on run 34836141887). The `<ts>` is
# prefixed by ${LOG_BOM:-}, so a caller opening a step section sets LOG_BOM="$GH_LOG_BOM".
log_lines_at() {
  local d="$1" jid="$2" jn="$3" ts="$4"; shift 4; assert_fixture_dir "$d"
  local l
  for l in "$@"; do printf '%s\tUNKNOWN STEP\t%s%s %s\n' "$jn" "${LOG_BOM:-}" "$ts" "$l"; done >> "$d/log-$jid.txt"
}
# log_poll_header — the runner's `##[group]Run` header that opens the poll step's output,
# stamped in the step's start second, PRECEDED (when the job has no log yet) by a faithful
# model of the sections gh emits ahead of it.
#
# WHY THE PRELUDE. A faithful LINE shape is not a faithful DOCUMENT shape, and two regressions
# walk through the gap between them. Before this, every fixture log began with the poll step's
# own header, so:
#   * the probe's timestamp gate (`ts >= ps`, the rule that makes it skip an EARLIER step's
#     section and take the poll's) was unpinned — no fixture had an earlier header to skip, so
#     deleting the gate outright left the suite fully green; and
#   * a single-replacement BOM strip (`${log/…/}` instead of `${log//…/}`) was indistinguishable
#     from the correct global one — with a lone BOM in the file, stripping "the first" and
#     stripping "every" are the same operation. On a real 15-section log they are not: the
#     single form clears section 2's mark and leaves the poll header's intact, i.e. it fails
#     exactly as the unfixed probe did.
# Both are dead now: the bare `Set up job` section reproduces gh's real asymmetry (it strips the
# mark from the head of the concatenated stream, so ONLY the first section is bare), and the
# BOM'd intermediate section stamped before POLL_START gives the timestamp gate something it
# must actually skip AND puts a second mark in the file.
log_poll_header() {
  local d="$1" jid="$2" jn="$3"
  if ! grep -q '##\[group\]Run' "$d/log-$jid.txt" 2>/dev/null; then
    # Section 1 — BARE, because gh strips the BOM from the head of the stream, not per section.
    log_lines_at "$d" "$jid" "$jn" "2026-09-20T09:57:00.1000000Z" "##[group]Run Set up job"
    # Section 2 — BOM'd header, bare body. Stamped BEFORE the poll step's start second, so the
    # probe must decline it on the timestamp rule rather than on its content.
    LOG_BOM="$GH_LOG_BOM" log_lines_at "$d" "$jid" "$jn" "2026-09-20T09:58:00.1000000Z" "##[group]Run terraform apply"
    log_lines_at "$d" "$jid" "$jn" "2026-09-20T09:58:01.1000000Z" "Apply complete! Resources: 1 added, 0 changed, 1 destroyed."
  fi
  LOG_BOM="$GH_LOG_BOM" log_lines_at "$d" "$jid" "$jn" "2026-09-20T09:59:00.1000000Z" "##[group]Run set -uo pipefail"
}
# log_lines — the poll step's OWN output. Writes the header first if the job has none yet.
# A summary line `answered=N/M …` is preceded by the N `poll k/M: answered` lines the real
# loop prints, so a fixture summary is consistent unless NOEXPAND=1 says otherwise.
log_lines() {
  local d="$1" jid="$2" jn="$3" l k; shift 3
  grep -q '##\[group\]Run' "$d/log-$jid.txt" 2>/dev/null || log_poll_header "$d" "$jid" "$jn"
  for l in "$@"; do
    if [[ "${NOEXPAND:-0}" != 1 && "$l" =~ ^answered=([0-9]+)/([0-9]+)\  ]]; then
      for (( k = 1; k <= BASH_REMATCH[1]; k++ )); do
        log_lines_at "$d" "$jid" "$jn" "2026-09-20T10:00:00.1234567Z" "poll ${k}/${BASH_REMATCH[2]}: answered, no boot_complete row yet"
      done
    fi
    log_lines_at "$d" "$jid" "$jn" "2026-09-20T10:00:00.1234567Z" "$l"
  done
}
# log_next_step <fx> <job_id> <job_name> <ts> <line>... — the NEXT step's header and output.
log_next_step() {
  local d="$1" jid="$2" jn="$3" ts="$4"; shift 4
  # The mark opens the SECTION, so it rides the header line only — the body lines after it are
  # bare, exactly as in the poll step's own output above.
  LOG_BOM="$GH_LOG_BOM" log_lines_at "$d" "$jid" "$jn" "$ts" "##[group]Run {"
  if [[ $# -gt 0 ]]; then log_lines_at "$d" "$jid" "$jn" "$ts" "$@"; fi
}

# run_arm <fx> [extra env...] — runs the REAL probe with the shim first on PATH; prints rc.
run_arm() {
  local d="$1"; shift
  assert_fixture_dir "$d"
  env -i PATH="$WORK/bin:/usr/local/bin:/usr/bin:/bin" HOME="$WORK" FX="$d" \
    RUNS_PATH_PREFIX="$RUNS_PATH_PREFIX" "$@" bash "$SUT" > "$d/out" 2>&1
  echo $?
}
TOKEN="GH_TOKEN=synthetic-not-a-token"

expect() { # expect <arm> <want-rc> <got-rc> <fx>
  if [[ "$3" == "$2" ]]; then pass "$1 (rc=$3)"; else fail "$1 (expected rc=$2, got $3): $(tr '\n' ' ' < "$4/out" | cut -c1-300)"; fi
  if grep -q '^BADARGV' "$4/calls"; then fail "$1: probe sent an argv the shim does not accept: $(grep '^BADARGV' "$4/calls" | head -1)"; fi
}
expect_out() { # expect_out <arm> <fx> <fixed-string>
  if grep -qF -- "$3" "$2/out"; then pass "$1 names: $3"; else fail "$1 output lacks '$3': $(tr '\n' ' ' < "$2/out" | cut -c1-300)"; fi
}

# HELPER CANARIES: expect() and expect_out() own their verdicts, so the pass()/fail()
# self-test above cannot see them go silent. Each is driven once where it must fail.
_cfx="$WORK/fx-canary"; mkdir -p "$_cfx"; : > "$_cfx/calls"; printf 'canary-out\n' > "$_cfx/out"
for _c in "expect canary 0 1 $_cfx" "expect_out canary $_cfx __absent__"; do
  _f0=$fails; _t0=$total
  # shellcheck disable=SC2086
  $_c >/dev/null 2>&1
  if (( fails != _f0 + 1 )); then printf 'FATAL: helper canary "%s" recorded no failure\n' "${_c%% *}" >&2; exit 1; fi
  fails=$_f0; total=$_t0
done

ANS3="answered=3/30 last_class=none"
REC="VERDICT=received"

echo "== credentials and anchor"
fx="$WORK/fx-notoken"; new_fx notoken
expect "no GH_TOKEN -> CANNOT ESTABLISH" 3 "$(run_arm "$fx")" "$fx"
if [[ ! -s "$fx/calls" ]]; then pass "no GH_TOKEN: gh never called"; else fail "no GH_TOKEN: gh was called"; fi

fx="$WORK/fx-xtrace"; new_fx xtrace
rc=$(env -i PATH="$WORK/bin:/usr/local/bin:/usr/bin:/bin" HOME="$WORK" FX="$fx" GH_TOKEN=synthetic-not-a-token bash -x "$SUT" > "$fx/out" 2>&1; echo $?)
expect "xtrace with GH_TOKEN -> 78" 78 "$rc" "$fx"
if ! grep -q 'synthetic-not-a-token' "$fx/out"; then pass "xtrace refusal leaks no token"; else fail "xtrace output carries the token"; fi

fx="$WORK/fx-unmerged"; new_fx unmerged
jq -n '{state:"open", merged_at:null}' > "$fx/pr.json"
expect "PR not merged -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "PR not merged" "$fx" "NOT YET: PR #8262 is not merged"

fx="$WORK/fx-prfail"; new_fx prfail; : > "$fx/pr.json.fail"
expect "PR read fails -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-prshape"; new_fx prshape
jq -n '{state:"closed", merged_at:"2026-09-19 12:00:00"}' > "$fx/pr.json"
expect "malformed merged_at -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

echo "== which runs count"
fx="$WORK/fx-noruns"; new_fx noruns
expect "merged, zero dispatches -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
if grep -qxF -- "api --paginate ${RUNS_PATH_PREFIX}${MERGED}&per_page=100" "$fx/calls"; then
  pass "runs query is anchored on the PR's merged_at"
else fail "runs query not anchored on merged_at: $(cat "$fx/calls")"; fi

fx="$WORK/fx-runsfail"; new_fx runsfail; : > "$fx/runs.json.fail"
expect "run list fails -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-runsjunk"; new_fx runsjunk; printf 'not json' > "$fx/runs.json"
expect "run list not JSON -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

# A run created AT the merge second, and one before it, both carry an answered poll. The
# API filter is inclusive and this shim ignores it entirely, so only the probe's own strict
# comparison keeps them out. Either leaking through reads as a PASS on possibly-pre-fix code.
fx="$WORK/fx-atmerge"; new_fx atmerge
add_run "$fx" 100 "$MERGED"; add_run "$fx" 99 "2026-09-18T09:00:00Z"
for r in 100 99; do
  add_job "$fx" "$r" "$((r * 10))" git_data_host_create completed success "$MERGED"
  log_lines "$fx" "$((r * 10))" git_data_host_create "$ANS3" "$REC"
done
expect "run AT/before the merge second is not evidence -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-wrongref"; new_fx wrongref
add_run "$fx" 101 "2026-09-20T09:00:00Z" workflow_dispatch feat-x; add_run "$fx" 102 "2026-09-20T09:00:00Z" push main
for r in 101 102; do
  add_job "$fx" "$r" "$((r * 10))" git_data_host_create completed success "2026-09-20T09:01:00Z"
  log_lines "$fx" "$((r * 10))" git_data_host_create "$ANS3" "$REC"
done
expect "non-main branch / non-dispatch event is not evidence -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-skipped"; new_fx skipped
add_run "$fx" 103 "2026-09-20T09:00:00Z"
add_job "$fx" 103 1030 git_data_host_create completed skipped "2026-09-20T09:01:00Z"
add_job "$fx" 103 1031 git_data_host_replace completed skipped "2026-09-20T09:01:00Z"
add_job "$fx" 103 1032 inngest_host_replace completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1032 inngest_host_replace "$ANS3" "$REC"
expect "only skipped git-data jobs (another job answered) -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
if ! grep -q 'run view --job' "$fx/calls"; then pass "skipped/unrelated jobs: no log fetched"; else fail "skipped/unrelated jobs: a log was fetched"; fi

fx="$WORK/fx-jobsfail"; new_fx jobsfail
add_run "$fx" 104 "2026-09-20T09:00:00Z"
expect "jobs list fails -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

echo "== reading the poll out of the log"
fx="$WORK/fx-received"; new_fx received
add_run "$fx" 110 "2026-09-20T09:00:00Z"
add_job "$fx" 110 1100 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1100 git_data_host_create "$ANS3" "$REC"
expect "create job, VERDICT=received -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "received" "$fx" "3/30 reads answered, VERDICT=received"

fx="$WORK/fx-replace"; new_fx replace
add_run "$fx" 111 "2026-09-20T09:00:00Z"
add_job "$fx" 111 1110 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1110 git_data_host_replace "answered=30/30 last_class=none" "VERDICT=silent"
expect "replace job, VERDICT=silent (read answered, host did not report) -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "silent" "$fx" "git_data_host_replace (job 1110"

fx="$WORK/fx-unreadable"; new_fx unreadable
add_run "$fx" 112 "2026-09-20T09:00:00Z"
add_job "$fx" 112 1120 git_data_host_create completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1120 git_data_host_create "poll 1/30: read FAILED rc=22 class=credentials-rejected body_bytes=0 stderr: x" \
  "answered=0/30 last_class=credentials-rejected" "VERDICT=unreadable"
expect "VERDICT=unreadable, answered=0 -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "unreadable" "$fx" "never got an answer (answered=0/30, VERDICT=unreadable)"

# A LATE failure after reads answered: the read path works, which is #8178's property.
fx="$WORK/fx-lateunread"; new_fx lateunread
add_run "$fx" 119 "2026-09-20T09:00:00Z"
add_job "$fx" 119 1190 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1190 git_data_host_replace "answered=5/20 last_class=transport" "VERDICT=unreadable"
expect "VERDICT=unreadable after 5 answered reads -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "lateunread" "$fx" "5/20 reads answered, VERDICT=unreadable"

# A class token carrying a DIGIT (reader-exit-1) must still parse as a summary.
fx="$WORK/fx-digitclass"; new_fx digitclass
add_run "$fx" 111 "2026-09-20T09:00:00Z"
add_job "$fx" 111 1115 git_data_host_create completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1115 git_data_host_create "answered=0/20 last_class=reader-exit-1" "VERDICT=unreadable"
expect "last_class=reader-exit-1 parses -> FAIL, not CANNOT ESTABLISH" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-noanchor"; new_fx noanchor
add_run "$fx" 113 "2026-09-20T09:00:00Z"
add_job "$fx" 113 1130 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1130 git_data_host_replace "VERDICT=refused-no-anchor"
expect "VERDICT=refused-no-anchor (wiring fault) -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "noanchor" "$fx" "REFUSED to run"

# A poll step that RAN but left no VERDICT in its window (the pre-fix line shape, verbatim
# from run 34836141887, stands in for "failed before polling" and for gh format drift): the
# probe could not look, which is not the same as "nothing yet".
fx="$WORK/fx-oldshape"; new_fx oldshape
add_run "$fx" 114 "2026-09-20T09:00:00Z"
add_job "$fx" 114 1140 git_data_host_create completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1140 git_data_host_create "poll 1/20: rc=22, no boot_complete row yet" "poll 20/20: rc=22, no boot_complete row yet"
expect "poll step ran, no VERDICT in its window -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "oldshape" "$fx" "its output carries no VERDICT line"

# The runner echoes each step's script in ANSI colour; a VERDICT/answered literal there is
# SOURCE, not a result. Also a mid-line mention. Neither may count.
fx="$WORK/fx-echoed"; new_fx echoed
add_run "$fx" 115 "2026-09-20T09:00:00Z"
add_job "$fx" 115 1150 git_data_host_create completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1150 git_data_host_create $'\e[36;1manswered=3/30 last_class=none\e[0m' $'\e[36;1mVERDICT=received\e[0m' \
  "echo VERDICT=received" "x answered=3/30 last_class=none"
expect "echoed script / mid-line VERDICT is not a result -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "echoed" "$fx" "carries no VERDICT line"

echo "== a verdict must come from the POLL STEP's own output"
# The operator's `reason` input is echoed by the NEXT step's env block. Forged lines there,
# before the poll step, in a skipped poll step, or tab-embedded, must never close #8178.
FORGED=("answered=3/20 last_class=none" "VERDICT=received")
fx="$WORK/fx-forgeskip"; new_fx forgeskip
add_run "$fx" 140 "2026-09-20T09:00:00Z"
add_job "$fx" 140 1400 git_data_host_replace completed cancelled "2026-09-20T09:01:00Z" skipped
log_lines_at "$fx" 1400 git_data_host_replace "2026-09-20T10:10:00.0000000Z" "${FORGED[@]}"
expect "forged lines, poll step skipped -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
if ! grep -q 'run view --job' "$fx/calls"; then pass "skipped poll step: no log fetched"; else fail "skipped poll step: log fetched"; fi

# X2: the real poll never answered; the next step's env echo carries a forged pair IN THE
# SAME SECOND the poll step completed. A clock window would admit it; the header bound does not.
fx="$WORK/fx-forgeout"; new_fx forgeout
add_run "$fx" 141 "2026-09-20T09:00:00Z"
add_job "$fx" 141 1410 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1410 git_data_host_replace "answered=0/20 last_class=credentials-rejected" "VERDICT=unreadable"
log_next_step "$fx" 1410 git_data_host_replace "2026-09-20T10:05:00.4959690Z" "  REASON: x" "${FORGED[@]}"
expect "same-second forgery in the NEXT step is ignored -> FAIL on the real verdict" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"

# X1: the poll step failed BEFORE polling (no verdict of its own) and forged lines sit in
# the previous step's last second, which is also the poll step's start second.
fx="$WORK/fx-forgebefore"; new_fx forgebefore
add_run "$fx" 142 "2026-09-20T09:00:00Z"
add_job "$fx" 142 1420 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines_at "$fx" 1420 git_data_host_replace "2026-09-20T09:59:00.0500000Z" "${FORGED[@]}"
log_poll_header "$fx" 1420 git_data_host_replace
log_lines_at "$fx" 1420 git_data_host_replace "2026-09-20T09:59:00.9000000Z" "::error::DOPPLER_TOKEN is not present — refusing"
expect "same-second forgery BEFORE the poll header, no verdict inside -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "forgebefore" "$fx" "carries no VERDICT line"

# A tab inside echoed text cannot place `<ts> VERDICT=` at the start of the third field.
fx="$WORK/fx-forgetab"; new_fx forgetab
add_run "$fx" 143 "2026-09-20T09:00:00Z"
add_job "$fx" 143 1430 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1430 git_data_host_replace "answered=0/20 last_class=transport" "VERDICT=unreadable" \
  $'x\t2026-09-20T10:00:00.0000000Z VERDICT=received' $'x\t2026-09-20T10:00:00.0000000Z answered=3/20 last_class=none'
expect "tab-embedded forgery inside the step is ignored -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"

# A summary that disagrees with the per-poll lines is not accepted, whichever way it errs.
fx="$WORK/fx-sumlie"; new_fx sumlie
add_run "$fx" 144 "2026-09-20T09:00:00Z"
add_job "$fx" 144 1440 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
NOEXPAND=1 log_lines "$fx" 1440 git_data_host_replace "answered=3/20 last_class=none" "VERDICT=unreadable"
expect "summary answered=3 with no answered poll lines -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "sumlie" "$fx" "has 0 answered poll line(s)"

fx="$WORK/fx-twosum"; new_fx twosum
add_run "$fx" 145 "2026-09-20T09:00:00Z"
add_job "$fx" 145 1450 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1450 git_data_host_replace "answered=0/20 last_class=transport" "VERDICT=unreadable"
NOEXPAND=1 log_lines "$fx" 1450 git_data_host_replace "answered=3/20 last_class=none"
expect "two summaries in the step -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "twosum" "$fx" "answered= summaries alongside"

fx="$WORK/fx-noheader"; new_fx noheader
add_run "$fx" 146 "2026-09-20T09:00:00Z"
add_job "$fx" 146 1460 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines_at "$fx" 1460 git_data_host_replace "2026-09-20T10:00:00.0000000Z" "answered=3/20 last_class=none" "VERDICT=received"
expect "no step header at all -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "noheader" "$fx" "could not locate the poll step's output"

fx="$WORK/fx-crlf"; new_fx crlf
add_run "$fx" 116 "2026-09-20T09:00:00Z"
add_job "$fx" 116 1160 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1160 git_data_host_create $'answered=2/30 last_class=none\r' $'VERDICT=received\r'
expect "CRLF log lines still parse -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-logfail"; new_fx logfail
add_run "$fx" 117 "2026-09-20T09:00:00Z"
add_job "$fx" 117 1170 git_data_host_create completed success "2026-09-20T09:01:00Z"
printf 'HTTP 410: the log has expired\n' > "$fx/log-1170.txt.fail"
expect "log unreadable -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "logfail" "$fx" "HTTP 410: the log has expired"

fx="$WORK/fx-logempty"; new_fx logempty
add_run "$fx" 118 "2026-09-20T09:00:00Z"
add_job "$fx" 118 1180 git_data_host_create completed success "2026-09-20T09:01:00Z"
: > "$fx/log-1180.txt"
expect "log empty -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"

echo "== the log must agree with the library's contract"
fx="$WORK/fx-contra"; new_fx contra
add_run "$fx" 120 "2026-09-20T09:00:00Z"
add_job "$fx" 120 1200 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1200 git_data_host_create "answered=0/30 last_class=transport" "$REC"
expect "VERDICT=received with answered=0 -> CANNOT ESTABLISH, never PASS" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "contra" "$fx" "the log contradicts the library's contract"

fx="$WORK/fx-twov"; new_fx twov
add_run "$fx" 121 "2026-09-20T09:00:00Z"
add_job "$fx" 121 1210 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1210 git_data_host_create "$ANS3" "VERDICT=unreadable" "$REC"
expect "two VERDICT lines -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "twov" "$fx" "VERDICT lines in its poll step's output"

fx="$WORK/fx-vocab"; new_fx vocab
add_run "$fx" 122 "2026-09-20T09:00:00Z"
add_job "$fx" 122 1220 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1220 git_data_host_create "$ANS3" "VERDICT=ok"
expect "VERDICT outside the vocabulary -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "vocab" "$fx" "outside the library's vocabulary"

fx="$WORK/fx-nosum"; new_fx nosum
add_run "$fx" 123 "2026-09-20T09:00:00Z"
add_job "$fx" 123 1230 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1230 git_data_host_create "$REC"
expect "VERDICT=received without an answered= summary -> CANNOT ESTABLISH" 3 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "nosum" "$fx" "answered= summaries alongside"

echo "== ordering: the newest poll decides"
fx="$WORK/fx-newfail"; new_fx newfail
add_run "$fx" 130 "2026-09-20T09:00:00Z"; add_run "$fx" 131 "2026-09-21T09:00:00Z"
add_job "$fx" 130 1300 git_data_host_replace completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1300 git_data_host_replace "$ANS3" "$REC"
add_job "$fx" 131 1310 git_data_host_replace completed failure "2026-09-21T09:01:00Z"
log_lines "$fx" 1310 git_data_host_replace "answered=0/30 last_class=transport" "VERDICT=unreadable"
expect "newer unanswered poll outranks an older answered one -> FAIL" 1 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-newpass"; new_fx newpass
add_run "$fx" 132 "2026-09-20T09:00:00Z"; add_run "$fx" 133 "2026-09-21T09:00:00Z"
add_job "$fx" 132 1320 git_data_host_replace completed failure "2026-09-20T09:01:00Z"
log_lines "$fx" 1320 git_data_host_replace "answered=0/30 last_class=transport" "VERDICT=unreadable"
add_job "$fx" 133 1330 git_data_host_replace completed success "2026-09-21T09:01:00Z"
log_lines "$fx" 1330 git_data_host_replace "$ANS3" "$REC"
expect "newer answered poll outranks an older unanswered one -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"
expect_out "newpass" "$fx" "job 1330"

fx="$WORK/fx-walkpast"; new_fx walkpast
add_run "$fx" 134 "2026-09-20T09:00:00Z"; add_run "$fx" 135 "2026-09-21T09:00:00Z"
add_job "$fx" 134 1340 git_data_host_create completed success "2026-09-20T09:01:00Z"
log_lines "$fx" 1340 git_data_host_create "$ANS3" "$REC"
add_job "$fx" 135 1350 git_data_host_replace completed failure "2026-09-21T09:01:00Z" skipped
log_lines "$fx" 1350 git_data_host_replace "terraform apply failed before the poll"
expect "newest job never reached its poll; the older answered one decides -> PASS" 0 "$(run_arm "$fx" "$TOKEN")" "$fx"

fx="$WORK/fx-pending"; new_fx pending
add_run "$fx" 136 "2026-09-21T09:00:00Z"
add_job "$fx" 136 1360 git_data_host_create in_progress null "2026-09-21T09:01:00Z"
expect "only an in-progress git-data job -> NOT YET" 2 "$(run_arm "$fx" "$TOKEN")" "$fx"
if ! grep -q 'run view --job' "$fx/calls"; then pass "in-progress job: no log fetched"; else fail "in-progress job: log fetched before completion"; fi

echo "== invariant: no arm that could not look or found nothing may reach the close verb"
# Re-derived from the arms above rather than restated: every fixture whose expected rc was
# not 0 is re-run and must still not be 0.
for d in notoken unmerged prfail prshape noruns runsfail runsjunk atmerge wrongref skipped jobsfail \
         unreadable digitclass noanchor oldshape echoed forgeskip forgeout forgebefore forgetab sumlie twosum \
         noheader logfail logempty \
         contra twov vocab nosum newfail pending; do
  rc=$(run_arm "$WORK/fx-$d" "$TOKEN")
  if [[ "$rc" != 0 ]]; then pass "never-0: $d (rc=$rc)"; else fail "never-0: $d reached PASS"; fi
done

# Assertion count, EXACT, reported with printf + exit, never through fail() (ADR-193).
EXACT=93
if (( total != EXACT )); then
  printf 'FATAL: %d assertions ran, expected exactly %d -- coverage changed; update EXACT deliberately\n' "$total" "$EXACT" >&2
  exit 1
fi
printf '\n%d assertions, %d failed\n' "$total" "$fails"
[[ "$fails" -eq 0 ]]
