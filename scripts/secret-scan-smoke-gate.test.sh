#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 1 for #9727 (ADR-276 S1): the secret-scan `smoke-relevance` gate.
#
# WHAT THE GATE IS. `.github/workflows/secret-scan.yml` job `smoke-relevance` lists the PR's
# files through the pulls/files API and writes `smoke=false` only when the list is complete AND
# touches nothing the ten `smoke-tests` cases execute or read. `smoke-tests` runs unless that
# output is the exact string `false`. It is a COST optimisation, not a control: the five required
# scanners still run on every PR, and CODEOWNERS covers this suite.
#
# WHAT THIS SUITE PROVES. Not that the YAML mentions the right words, but that the step body,
# EXTRACTED from the workflow and EXECUTED under the shell GitHub Actions uses
# (`bash --noprofile --norc -eo pipefail`), yields the right verdict for each input class, and
# that the wrapper (job `if:`, `needs:`, outputs, permissions, env) is what the design says.
#
#   * a named subject list, each member as a modification, a rename SOURCE and a rename
#     DESTINATION, plus prefix rows and a non-subject control (must yield `false`);
#   * a structural anchor: every tracked file that is a command-position operand of the live
#     `smoke-tests` job text must match the body's SUBJECT_RE (so a new step running a real file
#     outside the pattern reddens this suite), with a known-positive control;
#   * every fetch failure shape fails OPEN (`smoke=true` with a reason): non-zero exit, page one
#     then failure, empty list, entry count differing from the event's `changed_files` in either
#     direction (including the 3000-entry cap), a matcher error;
#   * seven mutation rows run against mutated COPIES of the body / workflow in mktemp dirs. A
#     mutant is CAUGHT only when this suite's own check returns its "assertion failed" verdict
#     (rc 1) AND the failure text names the expected effect. A mutant that merely crashes
#     (rc 2, 126, 127, a signal) is NOT caught: a crash proves nothing about the assertion.
#
# HARNESS ROWS. H1: stubs that always print one verdict must turn the shared row function red on
# the opposite class (so the suite distinguishes the two verdicts). H2: the assertion floor is in
# the guard-vacuity-floor shape and is itself exercised on a snippet cut out of this file.
#
# THE gh SHIM validates the exact endpoint (`repos/<GH_REPO>/pulls/<PR_NUMBER>/files?per_page=100`),
# whitelists the real flags used (`api`, `--paginate`, `--jq`), exits non-zero when GH_TOKEN is
# unset as real gh does, applies the passed --jq with real jq per page, serves page one only
# without --paginate, flushes page one before failing in page-then-fail mode, and logs every call.
#
# PRE-MERGE LIMIT. The suite cannot prove GitHub's `needs`/status-function skip semantics; the
# `false` arm is exercised by the PR scratch canary and the post-merge canary (plan Phase 6, 7).
#
# This suite writes ONLY under mktemp rooted at ${TMPDIR:-/var/tmp}; never into the repo.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# A DIRECT invocation inherits the bare /tmp (a machine-global tmpfs shared by every worktree);
# the registered runners default to /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this array, which can only be silenced by
# deleting evidence, not by moving a counter.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WF="$REPO_ROOT/.github/workflows/secret-scan.yml"
REQUIRED="$REPO_ROOT/scripts/required-checks.txt"

SANDBOX=$(mktemp -d "$TMPDIR/ss-smoke-gate.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

for _dep in python3 jq git grep sed cut awk; do
  command -v "$_dep" >/dev/null 2>&1 || { printf 'FAIL: %s is required\n' "$_dep" >&2; exit 2; }
done
python3 -c 'import yaml' 2>/dev/null || {
  printf 'FAIL: PyYAML is required to extract the step body (python3 -c "import yaml" failed)\n' >&2
  exit 2; }

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
# pass() and fail() must each move their counters; a neutered helper makes every row below quiet.
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass
fail "instrument self-test (expected, not a real failure)" 2>/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() did not each move their counter by one (%s %s %s)\n' \
    "$passes" "$fails" "${#FAILURES[@]}" >&2
  exit 1
fi
passes=$_p0; fails=$_f0; FAILURES=()

# ── Expected literals (the design's reading of the wrapper) ──────────────────
IF_LITERAL="github.event_name == 'pull_request' && !cancelled() && (needs.smoke-relevance.result != 'success' || needs.smoke-relevance.outputs.smoke != 'false')"
R_SUBJ="subject path changed"
R_NOSUBJ="no subject path changed"
R_FETCH="file list fetch failed"
R_EMPTY="empty file list"
R_MISMATCH="file list does not match the event's changed_files"
R_NAMES="name extraction failed"
R_MATCHER="matcher error rc=2"
# Distinct tracked command-position operands in the smoke-tests job text, re-derived from the live
# workflow on 2026-10-08: lint-fixture-content.mjs, rename-guard.sh, allowlist-diff.sh,
# .gitleaks.toml.
OPERAND_FLOOR=4

# The named subject list: what the ten smoke cases execute or read (and implicit git inputs).
SUBJ=(
  ".github/workflows/secret-scan.yml"
  ".gitleaks.toml"
  ".gitleaksignore"
  "apps/web-platform/scripts/rename-guard.sh"
  "apps/web-platform/scripts/allowlist-diff.sh"
  "apps/web-platform/scripts/lint-fixture-content.mjs"
  "apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"
  ".gitignore"
  ".gitattributes"
  "apps/web-platform/.gitignore"
  "docs/sub/.gitattributes"
  "apps/web-platform/server/smoke/with-secret.ts"
  "smoke/x.txt"
)

# ── Helper programs (written once into the sandbox) ──────────────────────────
mkdir -p "$SANDBOX/mut" "$SANDBOX/live" "$SANDBOX/shim" "$SANDBOX/wf"

cat > "$SANDBOX/extract.py" <<'PY'
import re, sys, yaml
wf, out = sys.argv[1], sys.argv[2]
try:
    text = open(wf).read()
    d = yaml.safe_load(text)
    job = (d.get("jobs") or {}).get("smoke-relevance")
    steps = (job or {}).get("steps") or []
    runs = [s for s in steps if isinstance(s, dict) and "run" in s]
    if len(runs) != 1:
        sys.stderr.write("found %d run steps in job smoke-relevance (0 steps = job absent)\n" % len(runs))
        sys.exit(3)
    env = runs[0].get("env") or {}
    m = re.search(r"(?ms)^  smoke-tests:\n(.*?)(?=^  [A-Za-z0-9_-]+:[ \t]*$|\Z)", text)
    if not m:
        sys.stderr.write("found 0 smoke-tests job text\n")
        sys.exit(3)
    open(out + "/body.sh", "w").write(runs[0]["run"])
    open(out + "/env.tsv", "w").write("".join("%s\t%s\n" % (k, v) for k, v in env.items()))
    open(out + "/smoke_job.txt", "w").write(m.group(1))
except SystemExit:
    raise
except Exception as e:  # a crash must be distinguishable from "found 0"
    sys.stderr.write("extract.py crashed: %r\n" % (e,))
    sys.exit(2)
PY

cat > "$SANDBOX/wrapper.py" <<'PY'
import os, sys, yaml
wf, req = sys.argv[1], sys.argv[2]
try:
    tags = []
    jobs = yaml.safe_load(open(wf)).get("jobs") or {}
    sr, st = jobs.get("smoke-relevance"), jobs.get("smoke-tests")

    def needs(j):
        n = (j or {}).get("needs", [])
        return [n] if isinstance(n, str) else list(n)

    if sr is None:
        tags.append("W-JOB-MISSING")
    if st is None:
        tags.append("W-SMOKE-MISSING")
    if st is not None:
        if st.get("if") != os.environ["EXP_SMOKE_IF"]:
            tags.append("W-IF")
        if needs(st) != ["smoke-relevance"]:
            tags.append("W-NEEDS")
        if st.get("continue-on-error"):
            tags.append("W-COE-SMOKE")
    for n, j in jobs.items():
        if n != "smoke-tests" and ("smoke-relevance" in needs(j) or "smoke-tests" in needs(j)):
            tags.append("W-NEEDS-OTHER:" + n)
    names = set()
    for line in open(req):
        line = line.rstrip("\n")
        if line.strip() and not line.lstrip().startswith("#"):
            names.add(line)
    req_jobs = [n for n, j in jobs.items() if (j or {}).get("name") in names]
    if len(req_jobs) < 5:
        tags.append("W-REQUIRED-COUNT")
    for n in req_jobs:
        if "smoke-relevance" in needs(jobs[n]) or "smoke-tests" in needs(jobs[n]):
            tags.append("W-REQUIRED-EDGE:" + n)
    if sr is not None:
        if sr.get("name") in names:
            tags.append("W-NOTREQ")
        if sr.get("if") != "github.event_name == 'pull_request'":
            tags.append("W-JOBIF")
        if sr.get("outputs") != {"smoke": "${{ steps.relevance.outputs.smoke }}"}:
            tags.append("W-OUTPUTS")
        if sr.get("permissions") != {"contents": "read", "pull-requests": "read"}:
            tags.append("W-PERM")
        if sr.get("continue-on-error"):
            tags.append("W-COE")
        if sr.get("timeout-minutes") != 5:
            tags.append("W-TIMEOUT")
        if sr.get("runs-on") != "ubuntu-24.04":
            tags.append("W-RUNSON")
        steps = sr.get("steps") or []
        runs = [s for s in steps if "run" in s]
        if len(steps) != 1 or len(runs) != 1:
            tags.append("W-STEPS")
        else:
            if runs[0].get("id") != "relevance":
                tags.append("W-ID")
            if runs[0].get("continue-on-error"):
                tags.append("W-COE-STEP")
            if runs[0].get("env") != {
                "GH_TOKEN": "${{ github.token }}",
                "GH_REPO": "${{ github.repository }}",
                "PR_NUMBER": "${{ github.event.pull_request.number }}",
                "CHANGED_FILES": "${{ github.event.pull_request.changed_files }}",
            }:
                tags.append("W-ENV")
    print("\n".join(tags))
except Exception as e:
    sys.stderr.write("wrapper.py crashed: %r\n" % (e,))
    sys.exit(2)
PY

cat > "$SANDBOX/operands.py" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
tracked = set(open(sys.argv[2], "rb").read().decode("utf-8", "replace").split("\0"))
STOP = r"""[^\s'";|&)<>`$]"""
# a command word, then optional flags, then the operand
P1 = re.compile(r"(?:^|(?<=[\s;&|(`]))(?:node|bash|sh|python3?|source|\.|npx|jq[ \t]+-f)[ \t]+(?:-\S+[ \t]+)*['\"]?(" + STOP + "+)", re.M)
P2 = re.compile(r"(?:^|(?<=[\s\"'=(]))(\./" + STOP + "+)", re.M)      # leading ./ and `uses: ./x`
P3 = re.compile(r"(?<![\w./-])(\.gitleaks[\w.-]*)")                   # any .gitleaks* operand
found = set()
for rx in (P1, P2, P3):
    for m in rx.finditer(text):
        tok = m.group(1).rstrip(".,:;")
        if tok.startswith("./"):
            tok = tok[2:]
        if tok in tracked:
            found.add(tok)
if found:
    print("\n".join(sorted(found)))
PY

cat > "$SANDBOX/mutate.py" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
n = s.count(old)
if n != 1:
    sys.stderr.write("replace target matched %d times, expected exactly 1: %r\n" % (n, old[:80]))
    sys.exit(3)
if old == new:
    sys.stderr.write("replacement does not change the text\n")
    sys.exit(3)
open(path, "w").write(s.replace(old, new))
PY

# The gh shim. Validates the exact endpoint, whitelists the real flags, mirrors real gh's exit
# when GH_TOKEN is unset, applies --jq with real jq per page, logs every call.
cat > "$SANDBOX/shim/gh" <<'SHIM'
#!/usr/bin/env bash
set -u
log="${SHIM_LOG:?}"
{ printf 'ARGV:'; printf ' [%s]' "$@"; printf '\n'; } >> "$log"
[ "${1:-}" = api ] || { echo "gh shim: unsupported subcommand '${1:-}'" >&2; exit 64; }
shift
paginate=0; jqexpr=""; have_jq=0; endpoint=""
while [ $# -gt 0 ]; do
  case "$1" in
    --paginate) paginate=1 ;;
    --jq) shift; [ $# -gt 0 ] || { echo "gh shim: --jq needs a value" >&2; exit 64; }; jqexpr="$1"; have_jq=1 ;;
    -*) echo "gh shim: unknown flag '$1' (real gh would not accept an invented flag)" >&2; exit 64 ;;
    *) [ -z "$endpoint" ] || { echo "gh shim: two endpoints" >&2; exit 64; }; endpoint="$1" ;;
  esac
  shift
done
[ -n "${GH_TOKEN:-}" ] || {
  echo "gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable." >&2; exit 4; }
want="repos/${GH_REPO:-?}/pulls/${PR_NUMBER:-?}/files?per_page=100"
[ "$endpoint" = "$want" ] || { echo "gh shim: endpoint '$endpoint' != '$want'" >&2; exit 65; }
[ "$have_jq" = 1 ] || { echo "gh shim: this suite's gate always passes --jq" >&2; exit 66; }
mode="${SHIM_MODE:-ok}"
if [ "$mode" = fail ]; then echo "gh: HTTP 502" >&2; exit 1; fi
shopt -s nullglob
pages=( "${SHIM_PAGES:?}"/page-*.json )
[ "${#pages[@]}" -gt 0 ] || { echo "gh shim: no pages configured" >&2; exit 67; }
if [ "$paginate" = 0 ]; then pages=( "${pages[0]}" ); fi
i=0
for p in "${pages[@]}"; do
  i=$((i + 1))
  jq -r "$jqexpr" "$p" || exit $?
  if [ "$mode" = page-then-fail ] && [ "$i" = 1 ]; then echo "gh: HTTP 502 on page 2" >&2; exit 1; fi
done
exit 0
SHIM
chmod +x "$SANDBOX/shim/gh"
printf '[]\n' > "$SANDBOX/shim-direct-page.json"

git -C "$REPO_ROOT" ls-files -z > "$SANDBOX/tracked.z" || {
  printf 'FAIL: git ls-files failed\n' >&2; exit 2; }

# ── Guard 1 - extraction / dispatch ──────────────────────────────────────────
# A harness that extracts 0 steps cannot tell "the body is clean" from "the body was never
# found", so 0 extracted steps must FAIL (and the run cannot continue without a body).
if ! python3 "$SANDBOX/extract.py" "$WF" "$SANDBOX/live" 2>"$SANDBOX/x.err"; then
  fail "G1.0 extraction: could not extract the smoke-relevance step body / env / smoke-tests text from secret-scan.yml: $(cat "$SANDBOX/x.err")"
  printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" $((passes + fails))
  exit 1
fi
pass
BODY="$SANDBOX/live/body.sh"
ENVFILE="$SANDBOX/live/env.tsv"
JOBTXT="$SANDBOX/live/smoke_job.txt"

if [ -s "$BODY" ] && bash -n "$BODY" 2>"$SANDBOX/n.err"; then pass; else fail "G1.1 the extracted body is empty or does not parse (bash -n): $(cat "$SANDBOX/n.err" 2>/dev/null)"; fi

RE_VAL=$(sed -n "s/^[[:space:]]*SUBJECT_RE='\\(.*\\)'[[:space:]]*\$/\\1/p" "$BODY")
if [ -n "$RE_VAL" ] && [ "$(grep -c '' <<<"$RE_VAL")" -eq 1 ]; then pass; else fail "G1.2 the body must assign SUBJECT_RE on exactly one bare line (got: $RE_VAL)"; fi
RE_ASSIGN="SUBJECT_RE='$RE_VAL'"

# ── Scenario machinery ───────────────────────────────────────────────────────
SCN=""; RC=0; WHY=""; CALLS=0; GOUT_N=0
SC_MODE=ok; SC_CHANGED=0; SC_NOTOKEN=0; SC_SUMMARY=""; SC_EV=""; SC_ER=""
SC_NAMES=(); X_EV=""; X_ER=""

scn_new() {
  SCN=$(mktemp -d "$SANDBOX/scn.XXXXXX") || { printf 'FAIL: mktemp scn\n' >&2; exit 2; }
  mkdir "$SCN/pages"; : > "$SCN/calls.log"
  SC_MODE=ok; SC_CHANGED=0; SC_NOTOKEN=0; SC_SUMMARY=""
}

# pg <page-number> [name | old=>new]...   (writes a pulls/files page; "old=>new" is a rename)
pg() {
  local n
  n=$(printf '%03d' "$1"); shift
  jq -n '$ARGS.positional | map(if contains("=>") then (split("=>")) as $p
         | {filename: $p[1], previous_filename: $p[0], status: "renamed"}
         else {filename: ., status: "modified"} end)' --args "$@" > "$SCN/pages/page-$n.json"
}

# exec_scn <body>: run the body under the Actions default shell with the workflow's own env keys.
exec_scn() {
  local body="$1" k v val
  local -a envargs=()
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] || continue
    case "$v" in
      '${{ github.token }}') val="tok-synthetic" ;;
      '${{ github.repository }}') val="example-org/example-repo" ;;
      '${{ github.event.pull_request.number }}') val="4242" ;;
      '${{ github.event.pull_request.changed_files }}') val="$SC_CHANGED" ;;
      *) val="UNMAPPED-EXPRESSION" ;;
    esac
    if [ "$k" = GH_TOKEN ] && [ "$SC_NOTOKEN" = 1 ]; then continue; fi
    envargs+=("$k=$val")
  done < "$ENVFILE"
  ( cd "$SCN" && env -i PATH="$SANDBOX/shim:$PATH" HOME="$SCN" \
      GITHUB_OUTPUT="$SCN/gh_output" GITHUB_STEP_SUMMARY="${SC_SUMMARY:-$SCN/summary}" \
      SHIM_LOG="$SCN/calls.log" SHIM_PAGES="$SCN/pages" SHIM_MODE="$SC_MODE" \
      "${envargs[@]}" bash --noprofile --norc -eo pipefail "$body" ) >"$SCN/stdout" 2>"$SCN/stderr"
  RC=$?
  CALLS=$(grep -c '^ARGV:' "$SCN/calls.log" || true)
  GOUT_N=0
  if [ -f "$SCN/gh_output" ]; then GOUT_N=$(grep -c '' "$SCN/gh_output" || true); fi
}

# check_scn <expected verdict: true|false|notfalse> <expected reason>
# returns 0 = as expected, 1 = assertion failed (see WHY), 2 = the body CRASHED (never "caught").
check_scn() {
  local ev="$1" er="$2" bad=0 got_v="" got_r="" line colon_n=0 gout
  WHY=""
  if [ "$RC" -eq 2 ] || [ "$RC" -ge 126 ]; then
    WHY="CRASH rc=$RC stderr=$(head -c 200 "$SCN/stderr")"; return 2
  fi
  while IFS= read -r line; do
    case "$line" in
      ::*)
        colon_n=$((colon_n + 1))
        if [[ "$line" =~ ^::notice::smoke-relevance:\ smoke=(true|false)\ \((.*)\)$ ]]; then
          got_v="${BASH_REMATCH[1]}"; got_r="${BASH_REMATCH[2]}"
        fi ;;
    esac
  done < "$SCN/stdout"
  gout=""
  if [ -f "$SCN/gh_output" ]; then gout=$(tr '\n' '|' < "$SCN/gh_output"); fi
  WHY="verdict=$got_v reason='$got_r' out='$gout' outlines=$GOUT_N colonlines=$colon_n rc=$RC calls=$CALLS"
  if [ "$CALLS" -ne 1 ]; then bad=1; WHY="$WHY [CALLS: gh was called $CALLS times, expected exactly 1]"; fi
  if [ "$ev" = notfalse ]; then
    # summary write failed: the output must NOT already carry smoke=false (the matrix must run)
    if [ -f "$SCN/gh_output" ] && grep -qx 'smoke=false' "$SCN/gh_output"; then
      bad=1; WHY="$WHY [NOTFALSE: smoke=false was written although the summary write failed]"
    fi
    return $bad
  fi
  if [ "$RC" -ne 0 ]; then bad=1; WHY="$WHY [RC: body exited $RC]"; fi
  if [ "$GOUT_N" -ne 1 ] || [ "$gout" != "smoke=$ev|" ]; then bad=1; WHY="$WHY [OUTPUT: expected exactly one line smoke=$ev]"; fi
  if [ "$colon_n" -ne 1 ]; then bad=1; WHY="$WHY [STDOUT: expected exactly one :: line]"; fi
  if [ "$got_v" != "$ev" ]; then bad=1; WHY="$WHY [VERDICT: expected $ev]"; fi
  if [ "$got_r" != "$er" ]; then bad=1; WHY="$WHY [REASON: expected '$er']"; fi
  return $bad
}

# ── Scenario functions: each runs the body passed as $1 and sets SC_EV / SC_ER ───
set_names() { X_EV="$1"; X_ER="$2"; shift 2; SC_NAMES=("$@"); }
sc_names() { scn_new; SC_CHANGED=${#SC_NAMES[@]}; pg 1 "${SC_NAMES[@]}"; exec_scn "$1"; SC_EV="$X_EV"; SC_ER="$X_ER"; }
sc_fail() { scn_new; SC_MODE=fail; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_FETCH"; }
sc_notoken() { scn_new; SC_NOTOKEN=1; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_FETCH"; }
# page one has NO subject file and matches CHANGED_FILES; the subject file is only on failed page two
sc_pthf() { scn_new; SC_MODE=page-then-fail; SC_CHANGED=2; pg 1 docs/a.md docs/b.md; pg 2 .gitleaks.toml; exec_scn "$1"; SC_EV=true; SC_ER="$R_FETCH"; }
sc_twopage() { scn_new; SC_CHANGED=3; pg 1 docs/a.md knowledge-base/b.md; pg 2 .gitleaks.toml; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
sc_twopage_clean() { scn_new; SC_CHANGED=2; pg 1 knowledge-base/a.md; pg 2 plugins/b.ts; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
sc_empty() { scn_new; SC_CHANGED=0; pg 1; exec_scn "$1"; SC_EV=true; SC_ER="$R_EMPTY"; }
sc_short() { scn_new; SC_CHANGED=3; pg 1 docs/a.md docs/b.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
sc_long() { scn_new; SC_CHANGED=2; pg 1 docs/a.md docs/b.md docs/c.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
sc_blank() { scn_new; SC_CHANGED=""; pg 1 docs/a.md docs/b.md; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
gen_pages_3000() { local p; for p in $(seq 1 30); do
  jq -n --argjson p "$p" '[range(100) | {filename: ("docs/gen/\($p)/f\(.).md"), status: "added"}]' \
    > "$SCN/pages/page-$(printf '%03d' "$p").json"; done; }
sc_cap() { scn_new; SC_CHANGED=3050; gen_pages_3000; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }
sc_cap_exact() { scn_new; SC_CHANGED=3000; gen_pages_3000; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
sc_rename_out() { scn_new; SC_CHANGED=1; pg 1 ".gitleaks.toml=>docs/x.md"; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
sc_rename_in() { scn_new; SC_CHANGED=1; pg 1 "docs/x.md=>.gitleaks.toml"; exec_scn "$1"; SC_EV=true; SC_ER="$R_SUBJ"; }
sc_rename_clean() { scn_new; SC_CHANGED=1; pg 1 "docs/old.md=>docs/new.md"; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# the summary write fails (GITHUB_STEP_SUMMARY is a directory): the output must not say false
sc_summary_fail() { scn_new; mkdir "$SCN/sumdir"; SC_SUMMARY="$SCN/sumdir"; SC_CHANGED=1; pg 1 docs/a.md; exec_scn "$1"; SC_EV=notfalse; SC_ER=""; }
sc_hostile() { scn_new; SC_CHANGED=2; pg 1 $'docs/a\n::error::x' $'docs/b\nsmoke=false'; exec_scn "$1"; SC_EV=false; SC_ER="$R_NOSUBJ"; }
# a name that forges an extra F<TAB> entry must change the count and fail OPEN
sc_hostile_forge() { scn_new; SC_CHANGED=1; pg 1 $'docs/a\nF\tdocs/forged'; exec_scn "$1"; SC_EV=true; SC_ER="$R_MISMATCH"; }

assert_sc() { # <label> <scenario fn> <body>
  local rc
  "$2" "$3"; check_scn "$SC_EV" "$SC_ER"; rc=$?
  if [ "$rc" -eq 0 ]; then pass; else fail "$1: $WHY"; fi
}

MUT_RUN=0
MUT_CAUGHT=0
# A mutant counts as caught ONLY on the suite's own assertion verdict (check rc 1) whose WHY
# names the expected effect; a crash (rc 2) or a mutant whose effect is not the expected one fails.
mutant_verdict() { # <label> <check rc> <expected WHY substring>
  MUT_RUN=$((MUT_RUN + 1))
  if [ "$2" -eq 1 ] && [[ "$WHY" == *"$3"* ]]; then
    MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else
    fail "MUTANT NOT CAUGHT: $1 (check rc=$2, expected WHY to contain [$3], got: $WHY)"
  fi
}
mutant_sc() { # <label> <scenario fn> <mutant body> <expected WHY substring>
  local rc
  "$2" "$3"; check_scn "$SC_EV" "$SC_ER"; rc=$?
  mutant_verdict "$1" "$rc" "$4"
}

# land <name> <src> <old> <new> [<old> <new>]...: copy src and apply EXACT-ONCE replacements.
LANDED=""
land() {
  local name="$1" src="$2"
  shift 2
  LANDED="$SANDBOX/mut/$name"
  cp "$src" "$LANDED"
  while [ $# -ge 2 ]; do
    if ! python3 "$SANDBOX/mutate.py" "$LANDED" "$1" "$2" 2>"$SANDBOX/mut.err"; then
      fail "mutation landing: $name: $(cat "$SANDBOX/mut.err")"; return 1
    fi
    shift 2
  done
  if cmp -s "$src" "$LANDED"; then fail "mutation landing: $name left the text unchanged"; return 1; fi
  return 0
}

# ── The shared row function (named list, prefix rows, control) ───────────────
ROW_ID=(); ROW_RC=(); ROW_WHY=()
row() { # <id> <ev> <er> <body> <names...>
  local id="$1" ev="$2" er="$3" body="$4" rc
  shift 4
  set_names "$ev" "$er" "$@"
  sc_names "$body"; check_scn "$SC_EV" "$SC_ER"; rc=$?
  ROW_ID+=("$id"); ROW_RC+=("$rc"); ROW_WHY+=("$WHY")
}
run_rows() { # <body> [quick]: quick = modification rows + control only
  local body="$1" s
  ROW_ID=(); ROW_RC=(); ROW_WHY=()
  for s in "${SUBJ[@]}"; do
    row "mod:$s" true "$R_SUBJ" "$body" "$s"
    if [ "${2:-}" != quick ]; then
      row "rename-source:$s" true "$R_SUBJ" "$body" "$s=>docs/moved-away.md"
      row "rename-dest:$s" true "$R_SUBJ" "$body" "docs/was-here.md=>$s"
    fi
  done
  if [ "${2:-}" != quick ]; then
    row "prefix-new-helper" true "$R_SUBJ" "$body" apps/web-platform/scripts/new-helper.mjs
    row "prefix-nested" true "$R_SUBJ" "$body" apps/web-platform/scripts/lib/x.mjs
    row "near-miss:scripts-extra" false "$R_NOSUBJ" "$body" apps/web-platform/scripts-extra/x
    row "near-miss:.gitleaks.toml.bak" false "$R_NOSUBJ" "$body" .gitleaks.toml.bak
    row "near-miss:secret-scan.yml.bak" false "$R_NOSUBJ" "$body" .github/workflows/secret-scan.yml.bak
    row "near-miss:foo.gitignore" false "$R_NOSUBJ" "$body" docs/foo.gitignore
    row "near-miss:.gitignored" false "$R_NOSUBJ" "$body" docs/.gitignored
    row "near-miss:smoke.md" false "$R_NOSUBJ" "$body" docs/smoke.md
    row "near-miss:smokey/" false "$R_NOSUBJ" "$body" smokey/x.ts
  fi
  row "control:non-subject" false "$R_NOSUBJ" "$body" knowledge-base/x.md plugins/y.ts
}
report_rows() { # <label prefix>
  local i
  for i in "${!ROW_ID[@]}"; do
    if [ "${ROW_RC[$i]}" -eq 0 ]; then pass; else fail "$1 ${ROW_ID[$i]}: ${ROW_WHY[$i]}"; fi
  done
}
row_rc_of() { # <id> -> prints the rc recorded for that row id
  local i
  for i in "${!ROW_ID[@]}"; do
    if [ "${ROW_ID[$i]}" = "$1" ]; then printf '%s' "${ROW_RC[$i]}"; return 0; fi
  done
  printf 'missing'
}

# ── Shim self-tests: the shim must reject invented flags, wrong endpoints, a missing token ──
shim_direct() { # <ENV=val...> gh <args...>
  ( env -i PATH="$SANDBOX/shim:$PATH" GH_TOKEN=t GH_REPO=o/r PR_NUMBER=7 \
      SHIM_LOG="$SANDBOX/shim-direct.log" SHIM_PAGES="$SANDBOX/shim-direct-pages" SHIM_MODE=ok "$@" ) >/dev/null 2>&1
}
mkdir -p "$SANDBOX/shim-direct-pages"; cp "$SANDBOX/shim-direct-page.json" "$SANDBOX/shim-direct-pages/page-001.json"
shim_direct gh api --paginate "repos/o/r/pulls/7/files?per_page=100" --jq '.[]'; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "SHIM: the exact endpoint with whitelisted flags must succeed (rc=$_r)"; fi
shim_direct gh api -f a=b "repos/o/r/pulls/7/files?per_page=100" --jq '.[]'; _r=$?
if [ "$_r" -eq 64 ]; then pass; else fail "SHIM: an invented flag (-f) must exit 64 like a rejected real flag (rc=$_r)"; fi
shim_direct gh api "repos/o/r/pulls/7/files" --jq '.[]'; _r=$?
if [ "$_r" -eq 65 ]; then pass; else fail "SHIM: a different endpoint must exit 65 (rc=$_r)"; fi
shim_direct GH_TOKEN= gh api "repos/o/r/pulls/7/files?per_page=100" --jq '.[]'; _r=$?
if [ "$_r" -eq 4 ]; then pass; else fail "SHIM: an unset GH_TOKEN must exit non-zero (4) as real gh does (rc=$_r)"; fi

# ── Env extraction: keys come from the workflow, every expression must be mapped ────
_nenv=$(grep -c '' "$ENVFILE" || true)
if [ "$_nenv" -eq 4 ]; then pass; else fail "G1.3 the step env must declare exactly GH_TOKEN, GH_REPO, PR_NUMBER, CHANGED_FILES (got $_nenv entries)"; fi

# ── Guard 1 rows: named list, prefix rows, control (live body) ───────────────
run_rows "$BODY"
report_rows "G1"
_N_ROWS=${#ROW_ID[@]}

# ── Fetch-failure shapes and list integrity (live body) ──────────────────────
assert_sc "G1 fetch failure fails open" sc_fail "$BODY"
assert_sc "G1 missing GH_TOKEN fails open" sc_notoken "$BODY"
assert_sc "G1 page-then-failure (subject file only on failed page two) fails open" sc_pthf "$BODY"
assert_sc "G1 must-PASS: two-page list, subject on page two" sc_twopage "$BODY"
assert_sc "G1 must-PASS: two-page list with no subject path" sc_twopage_clean "$BODY"
assert_sc "G1 empty list fails open" sc_empty "$BODY"
assert_sc "G1 list shorter than changed_files fails open" sc_short "$BODY"
assert_sc "G1 list longer than changed_files fails open" sc_long "$BODY"
assert_sc "G1 blank CHANGED_FILES fails open" sc_blank "$BODY"
assert_sc "G1 3000-entry cap (list 3000, event 3050) fails open" sc_cap "$BODY"
assert_sc "G1 must-PASS: exactly 3000 entries matching the event, no subject" sc_cap_exact "$BODY"
assert_sc "G1 rename out of a subject path" sc_rename_out "$BODY"
assert_sc "G1 rename into a subject path" sc_rename_in "$BODY"
assert_sc "G1 must-PASS: rename between non-subject paths" sc_rename_clean "$BODY"
assert_sc "G1 summary write failure leaves no smoke=false" sc_summary_fail "$BODY"
assert_sc "G1 hostile names: one smoke= line, no injected :: line" sc_hostile "$BODY"
assert_sc "G1 hostile name forging an F entry changes the count and fails open" sc_hostile_forge "$BODY"

# matcher error: SUBJECT_RE replaced by "(" is an INPUT to the live arm (grep rc 2), not a mutant
BODY_BADRE=""
if land S-badre "$BODY" "$RE_ASSIGN" "SUBJECT_RE='('"; then
  BODY_BADRE="$LANDED"
  set_names true "$R_MATCHER" docs/a.md
  assert_sc "G1 matcher error (SUBJECT_RE replaced by '(') fails open" sc_names "$BODY_BADRE"
fi

# ── Wrapper assertions (equalities on the extracted workflow, not whole-file grep) ──────────
export EXP_SMOKE_IF="$IF_LITERAL"
run_wrapper() { # <workflow file>: sets WHY to the newline-joined tags; returns 0 clean, 1 tags, 2 crash
  local out
  if ! out=$(python3 "$SANDBOX/wrapper.py" "$1" "$REQUIRED" 2>"$SANDBOX/w.err"); then
    WHY="CRASH wrapper.py: $(cat "$SANDBOX/w.err")"; return 2
  fi
  WHY=$(tr '\n' ' ' <<<"$out")
  if [ -n "$out" ]; then return 1; fi
  return 0
}
run_wrapper "$WF"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "W live workflow wrapper: rc=$_r tags: $WHY"; fi

# ── No symlinked subject files (a symlink in the subject set would be read through) ─────────
_links=""
while IFS= read -r _f; do
  [ -n "$_f" ] || continue
  if grep -qE "$RE_VAL" <<<"$_f"; then _links="$_links $_f"; fi
done < <(git -C "$REPO_ROOT" ls-files -s | awk -F'\t' '$1 ~ /^120000 / {print $2}')
if [ -z "$_links" ]; then pass; else fail "G1 a tracked symlink matches SUBJECT_RE (mode 120000):$_links"; fi

# ── Operand anchor ───────────────────────────────────────────────────────────
N_OPS=0
anchor_check() { # <job text file> <subject re>: 0 ok, 1 assertion failed, 2 extractor crash
  local ops op rc=0
  WHY=""
  if ! ops=$(python3 "$SANDBOX/operands.py" "$1" "$SANDBOX/tracked.z" 2>"$SANDBOX/op.err"); then
    WHY="CRASH operands.py: $(cat "$SANDBOX/op.err")"; return 2
  fi
  N_OPS=0
  if [ -n "$ops" ]; then N_OPS=$(grep -c '' <<<"$ops" || true); fi
  if [ "$N_OPS" -lt "$OPERAND_FLOOR" ]; then
    WHY="${WHY}OPERANDS-FLOOR: only $N_OPS distinct tracked operands, measured $OPERAND_FLOOR; "; rc=1
  fi
  while IFS= read -r op; do
    [ -n "$op" ] || continue
    if ! grep -qE "$2" <<<"$op"; then WHY="${WHY}OPERAND-OUTSIDE-PATTERN: $op; "; rc=1; fi
  done <<<"$ops"
  return $rc
}
anchor_check "$JOBTXT" "$RE_VAL"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "ANCHOR live smoke-tests operands: rc=$_r $WHY"; fi
LIVE_OPS=$N_OPS
# known-positive control: the extractor really finds the four expected operands in the live text
_ops_live=$(python3 "$SANDBOX/operands.py" "$JOBTXT" "$SANDBOX/tracked.z" | tr '\n' ' ')
for _must in apps/web-platform/scripts/lint-fixture-content.mjs apps/web-platform/scripts/rename-guard.sh \
             apps/web-platform/scripts/allowlist-diff.sh .gitleaks.toml; do
  if [[ " $_ops_live" == *" $_must "* ]]; then pass; else fail "ANCHOR control: the extractor did not find the known operand $_must in the live text (found: $_ops_live)"; fi
done
# command-shape rows: each shape must yield exactly the tracked operand; non-operands must yield none
_T=scripts/lint-workflows.sh
shape() { # <expected count> <label> <line>
  printf '%s\n' "$3" > "$SANDBOX/shape.txt"
  local got
  got=$(python3 "$SANDBOX/operands.py" "$SANDBOX/shape.txt" "$SANDBOX/tracked.z" | grep -c '' || true)
  if [ "$got" -eq "$1" ]; then pass; else fail "ANCHOR shape '$2': expected $1 operand(s), got $got for: $3"; fi
}
shape 1 "bash" "          bash $_T --x"
shape 1 "sh" "          sh $_T"
shape 1 "node" "          node $_T"
shape 1 "python3" "          python3 $_T"
shape 1 "python" "          python $_T"
shape 1 "source" "          source $_T"
shape 1 "dot" "          . $_T"
shape 1 "jq -f" "          jq -f $_T in.json"
shape 1 "npx" "          npx $_T"
shape 1 "leading ./" "          ./$_T"
shape 1 "uses ./" "        uses: ./$_T"
shape 1 "bash with flag" "          bash -x $_T"
shape 0 "mkdir -p" "          mkdir -p $_T"
shape 0 "git mv" "          git mv $_T docs/moved.sh"
shape 0 "echo text" "          echo \"see $_T for details\""
shape 0 "echo quoted command" "          echo \"bash $_T\""
shape 0 "untracked operand" "          bash scripts/definitely-not-a-tracked-file.sh"
shape 1 ".gitleaks operand" "          git add .gitleaksignore"
shape 0 "variable operand" "          bash \"\$SOME_SCRIPT\""

# Row 2: a second reference, to a REAL tracked file outside the pattern, after compliant ones
cp "$JOBTXT" "$SANDBOX/mut/job-extra.txt"
printf '\n          bash %s\n' "$_T" >> "$SANDBOX/mut/job-extra.txt"
anchor_check "$SANDBOX/mut/job-extra.txt" "$RE_VAL"; _r=$?
mutant_verdict "M2 smoke-tests job text gains 'bash $_T' (a real tracked file outside the pattern)" "$_r" "OPERAND-OUTSIDE-PATTERN: $_T"
# an untracked reference proves nothing and must not trip the anchor (the control for the above)
cp "$JOBTXT" "$SANDBOX/mut/job-untracked.txt"
printf '\n          bash scripts/definitely-not-a-tracked-file.sh\n' >> "$SANDBOX/mut/job-untracked.txt"
anchor_check "$SANDBOX/mut/job-untracked.txt" "$RE_VAL"; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "ANCHOR an untracked operand must not trip the anchor: $WHY"; fi

# Row 3: fewer than the measured operands, or 0 extracted steps, must FAIL
if land M3-fewer-ops "$JOBTXT" 'bash apps/web-platform/scripts/allowlist-diff.sh >"$SMOKE_OUT"' 'echo noop >"$SMOKE_OUT"'; then
  anchor_check "$LANDED" "$RE_VAL"; _r=$?
  mutant_verdict "M3 one operand removed from the job text (fewer than the measured $OPERAND_FLOOR)" "$_r" "OPERANDS-FLOOR"
fi
if land M3-job-renamed "$WF" $'\n  smoke-relevance:\n' $'\n  smoke-relevancex:\n'; then
  _x="$SANDBOX/mut/m3x"; mkdir -p "$_x"
  python3 "$SANDBOX/extract.py" "$LANDED" "$_x" 2>"$SANDBOX/x.err"; _r=$?
  MUT_RUN=$((MUT_RUN + 1))
  if [ "$_r" -eq 3 ] && grep -q 'found 0 run steps' "$SANDBOX/x.err"; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass
  else fail "MUTANT NOT CAUGHT: M3 job renamed so 0 steps are extracted (extract rc=$_r: $(cat "$SANDBOX/x.err"))"; fi
fi

# ── Row 1: SUBJECT_RE mutants (each against the row naming the member it must keep) ─────────
subj_mut() { # <name> <expected got-reason> <path> <old> <new>
  local name="$1" got="$2" path="$3"
  shift 3
  if land "M1-$name" "$BODY" "$@"; then
    set_names true "$R_SUBJ" "$path"
    mutant_sc "M1 $name: $path must stay subject" sc_names "$LANDED" "reason='$got'"
  fi
}
subj_mut never-match "$R_NOSUBJ" .gitleaks.toml "$RE_ASSIGN" "SUBJECT_RE='^\$'"
subj_mut drop-workflow-alt "$R_NOSUBJ" .github/workflows/secret-scan.yml '\.github/workflows/secret-scan\.yml|' ''
subj_mut drop-toml-alt "$R_NOSUBJ" .gitleaks.toml '\.gitleaks\.toml|' ''
subj_mut drop-ignore-alt "$R_NOSUBJ" .gitleaksignore '|\.gitleaksignore' ''
subj_mut drop-prefix-alt "$R_NOSUBJ" apps/web-platform/scripts/rename-guard.sh '|^apps/web-platform/scripts/' ''
subj_mut drop-gitattributes-alt "$R_NOSUBJ" .gitattributes '|(^|/)\.git(attributes|ignore)$' ''
subj_mut drop-smoke-alt "$R_NOSUBJ" apps/web-platform/server/smoke/with-secret.ts '|(^|/)smoke/' ''
subj_mut narrow-prefix "$R_NOSUBJ" apps/web-platform/scripts/new-helper.mjs '|^apps/web-platform/scripts/' \
  '|^apps/web-platform/scripts/(rename-guard\.sh|allowlist-diff\.sh|lint-fixture-content\.mjs|parse-gitleaks-allowlists\.mjs)$'

# ── Row 4: the fetch ─────────────────────────────────────────────────────────
FETCH_END="end)'); then"
if land M4-or-true "$BODY" "$FETCH_END" "end)' || true); then"; then
  mutant_sc "M4 lines=\$(gh api ... || true): a failed fetch must be 'file list fetch failed'" sc_fail "$LANDED" "reason='$R_EMPTY'"
  mutant_sc "M4 lines=\$(gh api ... || true): page one then failure must not yield smoke=false" sc_pthf "$LANDED" "verdict=false"
fi
if land M4-no-paginate "$BODY" 'gh api --paginate "repos' 'gh api "repos'; then
  mutant_sc "M4 --paginate dropped: a subject file on page two must still be found" sc_twopage "$LANDED" "reason='$R_MISMATCH'"
fi

# ── Row 5: guards inside the body ────────────────────────────────────────────
if land M5-no-empty-guard "$BODY" 'if [ -z "$lines" ]; then emit true "empty file list"; exit 0; fi' ':'; then
  mutant_sc "M5 empty-list guard removed" sc_empty "$LANDED" "reason='$R_NAMES'"
fi
COUNT_TEST='[ "$(grep -c "^F$T" <<<"$lines")" != "$CHANGED_FILES" ]'
if land M5-no-count-check "$BODY" "$COUNT_TEST" 'false'; then
  mutant_sc "M5 CHANGED_FILES comparison removed (list shorter than the event)" sc_short "$LANDED" "reason='$R_NOSUBJ'"
  mutant_sc "M5 CHANGED_FILES comparison removed (list longer than the event)" sc_long "$LANDED" "reason='$R_NOSUBJ'"
  mutant_sc "M5 CHANGED_FILES comparison removed (3000-entry cap)" sc_cap "$LANDED" "reason='$R_NOSUBJ'"
fi
if [ -n "$BODY_BADRE" ] && land M5-rc2-nomatch "$BODY_BADRE" '*) emit true "matcher error rc=$rc";;' '*) emit false "matcher error rc=$rc";;'; then
  set_names true "$R_MATCHER" docs/a.md
  mutant_sc "M5 grep rc 2 treated as no-match" sc_names "$LANDED" "verdict=false"
fi
if land M5-no-previous-filename "$BODY" '(if .previous_filename then "P\t" + .previous_filename else empty end)' 'empty'; then
  mutant_sc "M5 previous_filename branch removed (rename OUT of a subject path)" sc_rename_out "$LANDED" "reason='$R_NOSUBJ'"
fi

# ── Row 6: output order and cardinality ──────────────────────────────────────
OUT_LINE='echo "smoke=$1" >> "$GITHUB_OUTPUT"'
NOTICE_LINE='echo "::notice::smoke-relevance: smoke=$1 ($2)"'
if land M6-output-first "$BODY" "$OUT_LINE" ':' "$NOTICE_LINE" "$OUT_LINE; $NOTICE_LINE"; then
  mutant_sc "M6 GITHUB_OUTPUT written before the (failing) summary write" sc_summary_fail "$LANDED" "NOTFALSE"
fi
if land M6-twice "$BODY" "$OUT_LINE" "$OUT_LINE; $OUT_LINE"; then
  set_names true "$R_SUBJ" .gitleaks.toml
  mutant_sc "M6 the step writes smoke= twice" sc_names "$LANDED" "outlines=2"
fi

# ── Row 7: wrapper mutants on workflow copies ────────────────────────────────
wf_mut() { # <name> <expected tag> <old> <new>...
  local name="$1" tag="$2" r
  shift 2
  if land "M7-$name.yml" "$WF" "$@"; then
    run_wrapper "$LANDED"; r=$?
    mutant_verdict "M7 $name" "$r" "$tag"
  fi
}
wf_mut if-drop-result-arm "W-IF" "(needs.smoke-relevance.result != 'success' || needs.smoke-relevance.outputs.smoke != 'false')" \
  "(needs.smoke-relevance.outputs.smoke != 'false')"
wf_mut if-flip-to-eq-true "W-IF" "outputs.smoke != 'false'" "outputs.smoke == 'true'"
wf_mut if-drop-cancelled "W-IF" " && !cancelled()" ""
wf_mut if-drop-event-conjunct "W-IF" "if: github.event_name == 'pull_request' && !cancelled() && (" "if: (!cancelled()) && ("
wf_mut needs-extra "W-NEEDS" $'    needs: smoke-relevance\n' $'    needs: [smoke-relevance, scan]\n'
wf_mut needs-added-to-required-job "W-REQUIRED-EDGE" $'  lint-fixture-content:\n    name: lint fixture content\n' \
  $'  lint-fixture-content:\n    name: lint fixture content\n    needs: smoke-relevance\n'
wf_mut step-continue-on-error "W-COE-STEP" $'        id: relevance\n' $'        id: relevance\n        continue-on-error: true\n'
wf_mut job-continue-on-error "W-COE" $'    timeout-minutes: 5\n' $'    timeout-minutes: 5\n    continue-on-error: true\n'
wf_mut permissions-widened "W-PERM" $'      pull-requests: read\n    outputs:' $'      pull-requests: write\n    outputs:'
wf_mut job-if-dropped "W-JOBIF" $'    timeout-minutes: 5\n    if: github.event_name == \'pull_request\'\n' $'    timeout-minutes: 5\n'
wf_mut output-expression "W-OUTPUTS" 'smoke: ${{ steps.relevance.outputs.smoke }}' "smoke: 'true'"
wf_mut step-id-renamed "W-ID" $'        id: relevance\n' $'        id: relevancex\n'
wf_mut env-value-changed "W-ENV" '          CHANGED_FILES: ${{ github.event.pull_request.changed_files }}' \
  '          CHANGED_FILES: ${{ github.event.pull_request.number }}'

# ── H1: stubs that always print one verdict must be told apart ───────────────
make_stub() { # <name> <verdict> <reason>
  local f="$SANDBOX/mut/stub-$1.sh"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'gh api --paginate "repos/$GH_REPO/pulls/$PR_NUMBER/files?per_page=100" --jq ".[].filename" >/dev/null || true\n'
    printf 'echo "::notice::smoke-relevance: smoke=%s (%s)"\n' "$2" "$3"
    printf 'echo "smoke=%s" >> "$GITHUB_OUTPUT"\n' "$2"
  } > "$f"
  printf '%s' "$f"
}
count_failed_rows() { printf '%s\n' "${ROW_RC[@]}" | grep -vc '^0$' || true; }
# an always-false stub: every named-list row must fail, the non-subject control must pass
run_rows "$(make_stub false false "$R_NOSUBJ")" quick
_failed=$(count_failed_rows)
if [ "$_failed" -eq "${#SUBJ[@]}" ] && [ "$(row_rc_of 'mod:.gitleaks.toml')" -eq 1 ]; then pass
else fail "H1 a stub that always writes smoke=false must fail exactly the named-list rows (failed $_failed of ${#ROW_ID[@]})"; fi
if [ "$(row_rc_of 'control:non-subject')" -eq 0 ]; then pass
else fail "H1 the always-false stub must PASS the non-subject control (the two verdicts must be distinguishable)"; fi
# an always-true stub: the non-subject control must fail, the named-list rows must pass
run_rows "$(make_stub true true "$R_SUBJ")" quick
_failed=$(count_failed_rows)
if [ "$_failed" -eq 1 ] && [ "$(row_rc_of 'control:non-subject')" -eq 1 ]; then pass
else fail "H1 a stub that always writes smoke=true must fail exactly the non-subject control (failed $_failed)"; fi

# ── H2: the assertion floor shape, exercised on a snippet cut out of this file ─────────────
# The snippet runs with the counter below, at and above the floor.
_snippet="$SANDBOX/floor-snippet.sh"
awk '/^_total=\$\(\(passes \+ fails\)\)$/ {on=1} on {print} on && /^fi$/ {exit}' "${BASH_SOURCE[0]}" > "$_snippet"
_shape_ok=0
_l1=$(sed -n '1p' "$_snippet"); _l2=$(sed -n '2p' "$_snippet"); _l3=$(sed -n '3p' "$_snippet")
if [ "$_l1" = '_total=$((passes + fails))' ] && [[ "$_l2" =~ ^_FLOOR=[0-9]+$ ]] && [[ "$_l3" == 'if [ "$_total" -lt "$_FLOOR" ]; then' ]]; then _shape_ok=1; fi
if [ "$_shape_ok" -eq 1 ]; then pass; else fail "H2 the floor must be _total=, _FLOOR=<literal> (contiguous) then 'if [ \"\$_total\" -lt \"\$_FLOOR\" ]' (got: $_l1 / $_l2 / $_l3)"; fi
_flr=${_l2#_FLOOR=}
# shellcheck disable=SC1090  # the snippet is cut out of this very file at run time
( passes=$((_flr - 1)); fails=0; FAILURES=(); . "$_snippet"; exit 0 ) >/dev/null 2>&1; _r=$?
if [ "$_r" -eq 1 ]; then pass; else fail "H2 a run with fewer assertions than the floor must exit 1 (rc=$_r)"; fi
# shellcheck disable=SC1090
( passes=$_flr; fails=0; FAILURES=(); . "$_snippet"; exit 0 ) >/dev/null 2>&1; _r=$?
if [ "$_r" -eq 0 ]; then pass; else fail "H2 a run at the floor must not trip it (rc=$_r)"; fi

# ── Mutant accounting and measured counts ────────────────────────────────────
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ] && [ "$MUT_RUN" -eq 35 ]; then pass
else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; the measured count is 35)"; fi
if [ "$_N_ROWS" -eq 49 ]; then pass; else fail "ROWS: $_N_ROWS named-list/prefix/control rows ran, the measured count is 49"; fi
if [ "$LIVE_OPS" -ge "$OPERAND_FLOOR" ]; then pass; else fail "ANCHOR the live text yielded $LIVE_OPS operands, measured $OPERAND_FLOOR"; fi

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): a floor that increments the counter it guards shares a
# lifetime with the thing it is checking. This compares against a literal and exits directly.
# Set to the FULL measured count, not a slack figure.
#
# KEEP THESE TWO ASSIGNMENTS CONTIGUOUS (no comment between them or before the `if`):
# scripts/guard-vacuity-floor.test.sh binds a floor's variables by walking BACKWARD from the `if`.
_total=$((passes + fails))
_FLOOR=146
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'secret-scan-smoke-gate: %d passed, %d failed (%d assertions; %d mutants caught; %d operands)\n' \
  "$passes" "$fails" "$_total" "$MUT_CAUGHT" "$LIVE_OPS"
exit $(( ${#FAILURES[@]} > 0 ))
