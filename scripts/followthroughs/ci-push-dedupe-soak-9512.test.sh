#!/usr/bin/env bash
# ci-push-dedupe-soak-9512.test.sh — Guard 2 for #9512 (ADR-276 S2): drives the soak probe through a fake `gh`
# and pins its exit-code contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 78 xtrace refusal), with
# mutation rows against mutated COPIES of the probe. An exit-code contract nothing drives is a comment.
#
# The clock is injected (SOAK_NOW_EPOCH), the ADR file and test-all.sh are fixture copies (SOAK_ADR_FILE,
# SOAK_TEST_ALL), so no row sleeps and none depends on the wall clock or the live repo.
# Fixtures are synthesized (shas are `sha###`, the tracker is #4242); nothing is written outside a mktemp dir.
# FIXTURE KEYS KEEP THE HISTORICAL NAMES (`untrustedact`, `marker=untrusted|collab|contrib`, the decoy association column): trust is the
# fake permission table (perms.tsv), never the association.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/ci-push-dedupe-soak-9512.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/pds-soak.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

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
passes=0; fails=0; asserted=0
FAILURES=()
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }

# instrument self-test: both helpers must move their counters
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass "self-test" >/dev/null; fail "self-test" >/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  echo "[FATAL] instrument self-test: pass()/fail() did not each record"; exit 1
fi
passes=0; fails=0; asserted=0; FAILURES=()

NOW_ISO="2026-11-01T00:00:00Z"
NOW_EPOCH="$(date -u -d "$NOW_ISO" +%s)"
MERGED_ISO="2026-10-10T00:00:00Z"

# --- the fake gh: answers the endpoints the probe reads from $FX/*.json, applying --jq with real jq ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
# every refusal is LOGGED before exit 64: the lib sends `gh issue view` stderr to /dev/null and maps any failure to rc 2,
# so without the log a refused argv would surface as CANNOT ESTABLISH and an rc-3 row would pass for the wrong reason
refuse() { printf 'REFUSED %s\n' "$*" >> "$FX/refused.log"; exit 64; }
if [ "$1" = "issue" ]; then   # issue view <N> --repo <r> --json comments [--jq <expr>]  (argv-strict)
  [ "$2" = "view" ] && [ "$4" = "--repo" ] && [ "$6" = "--json" ] && [ "$7" = "comments" ] || refuse "$@"
  if [ $# -eq 9 ]; then [ "$8" = "--jq" ] || refuse "$@"; jqx="$9"; elif [ $# -eq 7 ]; then jqx=""; else refuse "$@"; fi
  printf 'issue view %s --repo %s --json comments\n' "$3" "$5" >> "$FX/requests.log"
  [ -f "$FX/fail-comments" ] && { echo "gh: HTTP 403 Resource not accessible" >&2; exit 1; }
  f="$FX/gql-comments-$3.json"; [ -f "$f" ] || exit 1
  if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
  exit 0
fi
[ "$1" = "api" ] || refuse "$@"
shift
paginate=0; jqx=""; ep=""
while (( $# )); do
  case "$1" in
    --paginate) paginate=1 ;;
    --jq) jqx="$2"; shift ;;
    -*) refuse "api $*" ;;
    *) ep="$1" ;;
  esac
  shift
done
printf '%s\n' "$ep" >> "$FX/requests.log"
case "$ep" in
  repos/*/pulls/9808) f="$FX/pr.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=push*) [ -f "$FX/fail-push" ] && { echo "gh: HTTP 500" >&2; exit 1; }; f="$FX/push.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=merge_group*)
    [ -f "$FX/fail-mg" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    (( paginate )) || refuse "$ep"
    cat "$FX"/mg-*.json; exit 0 ;;
  repos/*/actions/runs/*/jobs\?per_page=100\&filter=latest) [ -f "$FX/fail-jobs" ] && { echo "gh: HTTP 500" >&2; exit 1; }; r="${ep#*runs/}"; f="$FX/jobs-${r%%/*}.json" ;;
  repos/*/issues\?labels=follow-through\&state=open\&per_page=100) f="$FX/issues.json" ;;
  repos/*/collaborators/*/permission)   # the permission endpoint: perms.tsv is `login<TAB>perm|403|404`; stderr texts mirror the real gh
    [ -n "$jqx" ] || refuse "$ep (no --jq)"
    l="${ep#*collaborators/}"; l="${l%%/*}"
    p="$(awk -F'\t' -v l="$l" '$1 == l { print $2; exit }' "$FX/perms.tsv")"
    case "$p" in
      "")  refuse "$ep (login not in perms.tsv)" ;;
      404) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
      403) echo 'gh: Resource not accessible by integration (HTTP 403)' >&2; exit 1 ;;
      *)   printf '{"permission":"%s"}\n' "$p" | jq -r "$jqx"; exit 0 ;;
    esac ;;
  *) refuse "$ep" ;;
esac
[ -f "$f" ] || exit 1
if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
FAKE
chmod +x "$TMP/bin/gh"

# build_fx <dir> <n_elided> <n_full> <elided_run_seconds> <full_run_seconds> [key=value ...]
#   actdays=D    S2-ACTIVATED comment D days before the injected now (default 12), by an OWNER; noact: none
#   untrustedact: the activation comment is by a login with NO repository permission (the fake endpoint answers 404)   deact: a LATER S2-DEACTIVATED (owner-op)
#   unmatched=K  the K oldest elided runs have no merge_group voucher   early=K  K extra elided runs BEFORE the activation
#   marker=yes|none|mid|untrusted|nonurl|placeholder   the S2-EXIT-CENSUS comment (default yes; `untrusted` = a login with no permission)
#   adr=<status>  ADR-276 status line (default adopting)   noreg: test-all.sh lacks the proof suite
#   extra=<kind>  one more NON-elided run (mixed|nots|pdred): a shape a loose elision predicate would call elided
#   pdred: one full run's push-dedupe is red   unmerged / noissue / failX: the X read fails (jobs|push|mg|comments)
#   pdbad=K  the K newest full runs have a red push-dedupe   prefull=K  K non-elided runs BEFORE the activation, 20000 s each
#   reactivate: a DEACTIVATED marker EARLIER than the activation   twoact: an older ACTIVATED too   twodeact: an older
#   DEACTIVATED before a newer one that follows the activation   marker=collab|contrib: the census comment's author holds `write` | `read`
#   crlf: markers end in CRLF (a line follows each marker: the lib turns a LONE trailing CR into a line ending, a CR before an LF survives to the caller)   badts: ACTIVATED without the Z   midact: ACTIVATED only mid-line or with trailing text
#   marker=lookalike|foreign   a census URL on a lookalike or foreign host   latebatch: the DEACTIVATED marker is staged in a SECOND
#   fixture batch (the fixture merges both into one list; gh's own paging is measured, not modelled)
#   merged=<ISO>  the S2 PR merge time (default MERGED_ISO)
#   EVERY comment carries an `authorAssociation` DECOY and a stable author login that maps to a row of perms.tsv (the fake
#   permission endpoint): owner-op admin, member-op write, collab-op write, contrib-op read, none-op 404. The DEFAULT activation
#   comment is by `priv-op`, whose association reads CONTRIBUTOR (a private org member under the sweeper's token) but whose
#   repository permission is admin, so an association-consulting probe fails ~40 rows, not two.
#   privact: names that default (the row r_privmember pins it)   assocowner: the activation comment's association is OWNER but its
#   author's permission is `read` (the decoy must be ignored)   permfail: `priv-op`'s permission read is a 403
#   collabact: the activation is by collab-op (decoy association COLLABORATOR) holding `write`   noneact: by maint-op (decoy association NONE) holding `maintain`
#   regcomment: test-all.sh names the suite only in a comment/echo   nostatus: the ADR has no status line
#   nocreated: no comment carries a createdAt (the BODIES view must not need it; the comments view would be rc 2)
build_fx() {
  local fx="$1" ne="$2" nf="$3" es="$4" fs="$5"; shift 5
  assert_fixture_dir "$fx"; rm -rf "$fx"; mkdir -p "$fx"
  local actdays=12 noact=0 untrustedact=0 deact=0 unmatched=0 early=0 marker=yes pdred=0 unmerged=0 noissue=0 adr=adopting noreg=0 extra="" kv
  local privact=0 assocowner=0 permfail=0 collabact=0 noneact=0 merged="$MERGED_ISO" pdbad=0 prefull=0 reactivate=0 twoact=0 twodeact=0 crlf=0 badts=0 midact=0 latebatch=0 regcomment=0 nostatus=0 nocreated=0 cr=
  for kv in "$@"; do
    case "$kv" in
      actdays=*) actdays="${kv#*=}" ;; noact) noact=1 ;; untrustedact) untrustedact=1 ;; deact) deact=1 ;;
      unmatched=*) unmatched="${kv#*=}" ;; early=*) early="${kv#*=}" ;; marker=*) marker="${kv#*=}" ;;
      merged=*) merged="${kv#*=}" ;; pdbad=*) pdbad="${kv#*=}" ;; prefull=*) prefull="${kv#*=}" ;; reactivate) reactivate=1 ;; twoact) twoact=1 ;; twodeact) twodeact=1 ;;
      crlf) crlf=1 ;; badts) badts=1 ;; midact) midact=1 ;; latebatch) latebatch=1 ;; regcomment) regcomment=1 ;; nostatus) nostatus=1 ;; nocreated) nocreated=1 ;;
      pdred) pdred=1 ;; unmerged) unmerged=1 ;; noissue) noissue=1 ;; adr=*) adr="${kv#*=}" ;; noreg) noreg=1 ;; extra=*) extra="${kv#*=}" ;;
      privact) privact=1 ;; assocowner) assocowner=1 ;; permfail) permfail=1 ;; collabact) collabact=1 ;; noneact) noneact=1 ;;
      fail*) : > "$fx/fail-${kv#fail}" ;;
    esac
  done
  local act_epoch=$((NOW_EPOCH - actdays * 86400)) act_iso
  act_iso="$(date -u -d "@$act_epoch" +%Y-%m-%dT%H:%M:%SZ)"
  if (( unmerged )); then printf '{"merged_at":null}\n' > "$fx/pr.json"; else printf '{"merged_at":"%s"}\n' "$merged" > "$fx/pr.json"; fi
  (( crlf )) && cr='\r'
  if (( nostatus )); then printf -- '---\ntitle: x\n---\n# ADR-276 fixture\n' > "$fx/ADR-276-fixture.md"
  else printf -- '---\nstatus: %s\n---\n# ADR-276 fixture\n' "$adr" > "$fx/ADR-276-fixture.md"; fi
  if (( noreg )); then printf 'run_suite "other" bash other.test.sh\n' > "$fx/test-all.sh"
  elif (( regcomment )); then printf '# run_suite "scripts/ci-push-dedupe" bash scripts/ci-push-dedupe.test.sh\necho "scripts/ci-push-dedupe.test.sh"\n' > "$fx/test-all.sh"
  else printf 'run_suite "scripts/ci-push-dedupe" bash scripts/ci-push-dedupe.test.sh\n' > "$fx/test-all.sh"; fi
  local i total=$((prefull + early + ne + nf)) runs="" id sha created secs elided mg1="" mg2="" k=0 kind first_elided_sha=""
  for ((i = 1; i <= total + (${#extra} > 0 ? 1 : 0); i++)); do
    id=$((1000 + i)); sha="sha$(printf '%03d' "$i")"; kind=""
    if (( i <= prefull )); then
      created=$((act_epoch - 3600 * (prefull - i + 2) - 86400)); elided=0; secs=20000
    elif (( i <= prefull + early )); then
      created=$((act_epoch - 3600 * (prefull + early - i + 1))); elided=1; secs="$es"
    elif (( i <= prefull + early + nf )); then
      created=$((act_epoch + 3600 * i)); elided=0; secs="$fs"
    elif (( i <= total )); then
      created=$((act_epoch + 3600 * i)); elided=1; secs="$es"
    else
      created=$((act_epoch + 3600 * i)); elided=0; secs="$es"; kind="$extra"
    fi
    runs="{\"id\":$id,\"head_sha\":\"$sha\",\"created_at\":\"$(date -u -d "@$created" +%Y-%m-%dT%H:%M:%SZ)\"},$runs"   # newest first
    # cost-accounting decoys on EVERY run: none of these may count (skipped+runner, runner-less+running time, negative duration)
    local decoys='{name:"skipped-with-runner",conclusion:"skipped",runner_id:5,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-21T10:00:00Z"},
      {name:"runnerless-timed",conclusion:"cancelled",runner_id:null,started_at:"2026-10-20T10:00:00Z",completed_at:"2026-10-21T10:00:00Z"},
      {name:"negative-duration",conclusion:"success",runner_id:6,started_at:"2026-10-20T10:10:00Z",completed_at:"2026-10-20T10:00:00Z"}'
    if (( elided )); then
      # the first elided run keeps a SUCCESSFUL test-scripts-heavy: a different job, it must not decide the elision
      local heavy=skipped; (( k == 0 )) && heavy=success
      [ -z "$first_elided_sha" ] && first_elided_sha="$sha"
      jq -n --argjson s "$secs" "{jobs:[
        {name:\"push-dedupe\",conclusion:\"success\",runner_id:9,started_at:\"2026-10-20T10:00:00Z\",completed_at:\"2026-10-20T10:00:00Z\",steps:[{name:\"Proof holds for this SHA\",conclusion:\"success\"}]},
        {name:\"test-scripts (1/8)\",conclusion:\"skipped\",runner_id:null,started_at:null,completed_at:null},
        {name:\"test-scripts (2/8)\",conclusion:\"skipped\",runner_id:null,started_at:null,completed_at:null},
        {name:\"test-scripts-heavy\",conclusion:\"$heavy\",runner_id:null,started_at:null,completed_at:null},
        {name:\"lint\",conclusion:\"success\",runner_id:7,started_at:\"2026-10-20T10:00:00Z\",completed_at:(\"2026-10-20T10:00:00Z\"|fromdateiso8601 + \$s | todate)},
        $decoys]}" > "$fx/jobs-$id.json"
    else
      local pd=success
      { (( pdred && i == total )) || [ "$kind" = pdred ] || (( pdbad > 0 && i > prefull + early + nf - pdbad && i <= prefull + early + nf )); } && pd=failure
      local tsjobs='{name:"test-scripts (1/8)",conclusion:"success",runner_id:7,started_at:"2026-10-20T10:00:00Z",completed_at:("2026-10-20T10:00:00Z"|fromdateiso8601 + $s | todate)}'
      case "$kind" in
        mixed) tsjobs="$tsjobs"',{name:"test-scripts (2/8)",conclusion:"skipped",runner_id:null,started_at:null,completed_at:null}' ;;
        nots)  tsjobs='{name:"test-webplat (1/2)",conclusion:"success",runner_id:7,started_at:"2026-10-20T10:00:00Z",completed_at:("2026-10-20T10:00:00Z"|fromdateiso8601 + $s | todate)}' ;;
        pdred) tsjobs='{name:"test-scripts (1/8)",conclusion:"skipped",runner_id:null,started_at:null,completed_at:null}' ;;
      esac
      jq -n --argjson s "$secs" --arg pd "$pd" "{jobs:[
        {name:\"push-dedupe\",conclusion:\$pd,runner_id:9,started_at:\"2026-10-20T10:00:00Z\",completed_at:\"2026-10-20T10:00:00Z\"},
        $tsjobs, $decoys]}" > "$fx/jobs-$id.json"
    fi
    if (( elided )) && (( k >= unmatched )); then
      if (( k % 2 )); then mg1="$mg1{\"event\":\"merge_group\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"$sha\"},"
      else mg2="$mg2{\"event\":\"merge_group\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"$sha\"},"; fi
    fi
    (( elided )) && k=$((k + 1))
  done
  # noise a correct voucher check must ignore, on the SHA that unmatched=K leaves unvouched: a failed merge_group run and
# a pull_request run (the in-progress run is equivalent to absent: the success filter already refuses it)
  mg1="$mg1{\"event\":\"merge_group\",\"status\":\"completed\",\"conclusion\":\"failure\",\"head_sha\":\"$first_elided_sha\"},{\"event\":\"pull_request\",\"status\":\"completed\",\"conclusion\":\"success\",\"head_sha\":\"$first_elided_sha\"},{\"event\":\"merge_group\",\"status\":\"in_progress\",\"conclusion\":null,\"head_sha\":\"$first_elided_sha\"}"
  printf '{"workflow_runs":[%s]}\n' "${runs%,}" > "$fx/push.json"
  printf '{"workflow_runs":[%s]}\n' "${mg1%,}" > "$fx/mg-1.json"
  printf '{"workflow_runs":[%s{"event":"merge_group","status":"in_progress","conclusion":null,"head_sha":"shaZZZ"}]}\n' "$mg2" > "$fx/mg-2.json"
  if (( noissue )); then printf '[]\n' > "$fx/issues.json"
  else printf '[{"number":4242,"body":"<!-- soleur:followthrough script=scripts/followthroughs/ci-push-dedupe-soak-9512.sh earliest=2026-10-10T00:00:00Z secrets=GH_TOKEN -->"},{"number":4243,"body":"unrelated"}]\n' > "$fx/issues.json"; fi
  # the tracker's comments (staging shape: [{body, author_association (a DECOY the probe must ignore), login?}]; converted to the issue-view shape below)
  local cm='[{"body":"noted","author_association":"OWNER"}' cm2='['
  iso_at() { date -u -d "@$((act_epoch + $1))" +%Y-%m-%dT%H:%M:%SZ; }
  if (( ! noact )); then
    local assoc=CONTRIBUTOR actl=',"login":"priv-op"'
    (( untrustedact )) && { assoc=NONE; actl=""; }
    (( assocowner )) && { assoc=OWNER; actl=',"login":"ownread-op"'; }
    (( collabact )) && { assoc=COLLABORATOR; actl=',"login":"collab-op"'; }
    (( noneact )) && { assoc=NONE; actl=',"login":"maint-op"'; }
    if (( badts )); then cm="$cm,{\"body\":\"S2-ACTIVATED: ${act_iso%Z}\",\"author_association\":\"OWNER\"}"
    elif (( midact )); then cm="$cm,{\"body\":\"see S2-ACTIVATED: $act_iso\\nS2-ACTIVATED: $act_iso and then some\",\"author_association\":\"OWNER\"}"
    else cm="$cm,{\"body\":\"activated${cr}\\nS2-ACTIVATED: $act_iso${cr}${cr:+\\nthanks}\",\"author_association\":\"$assoc\"$actl}"; fi
    (( twoact )) && cm="$cm,{\"body\":\"S2-ACTIVATED: $(iso_at -$((8 * 86400)))\",\"author_association\":\"OWNER\"}"
    (( reactivate )) && cm="$cm,{\"body\":\"S2-DEACTIVATED: $(iso_at -86400)\",\"author_association\":\"OWNER\"}"
    (( twodeact )) && cm="$cm,{\"body\":\"S2-DEACTIVATED: $(iso_at -86400)\",\"author_association\":\"OWNER\"}"
  fi
  if (( deact || twodeact )); then
    if (( latebatch )); then cm2="$cm2{\"body\":\"S2-DEACTIVATED: $(iso_at 3600)\",\"author_association\":\"OWNER\"}"
    else cm="$cm,{\"body\":\"S2-DEACTIVATED: $(iso_at 3600)\",\"author_association\":\"OWNER\"}"; fi
  fi
  case "$marker" in
    yes)         cm="$cm,{\"body\":\"exit census${cr}\\nS2-EXIT-CENSUS: https://github.com/jikig-ai/soleur/issues/4242#issuecomment-1${cr}${cr:+\\nthanks}\",\"author_association\":\"MEMBER\"}" ;;
    lookalike)   cm="$cm,{\"body\":\"S2-EXIT-CENSUS: https://githubXcom/x/y\",\"author_association\":\"OWNER\"}" ;;
    foreign)     cm="$cm,{\"body\":\"S2-EXIT-CENSUS: https://example.com/x/y\",\"author_association\":\"OWNER\"}" ;;
    contrib)     cm="$cm,{\"body\":\"S2-EXIT-CENSUS: https://github.com/x/y\",\"author_association\":\"CONTRIBUTOR\"}" ;;
    collab)      cm="$cm,{\"body\":\"S2-EXIT-CENSUS: https://github.com/x/y\",\"author_association\":\"COLLABORATOR\"}" ;;
    mid)         cm="$cm,{\"body\":\"we will post an S2-EXIT-CENSUS: https://github.com/x later\",\"author_association\":\"OWNER\"}" ;;
    untrusted)   cm="$cm,{\"body\":\"S2-EXIT-CENSUS: https://github.com/x/y\",\"author_association\":\"NONE\"}" ;;
    nonurl)      cm="$cm,{\"body\":\"S2-EXIT-CENSUS: see-my-notes\",\"author_association\":\"OWNER\"}" ;;
    placeholder) cm="$cm,{\"body\":\"S2-EXIT-CENSUS: <url>\",\"author_association\":\"OWNER\"}" ;;
  esac
  assert_fixture_dir "$fx"
  printf '%s]\n' "$cm" > "$fx/stage-4242.json"
  (( latebatch )) && printf '%s]\n' "$cm2" > "$fx/stage-4242-2.json"
  # the `gh issue view --json comments` shape (what the trusted-author lib reads): every comment gets a stable login that
  # maps to a permission row, while its association stays on the comment as a DECOY the probe must ignore
  jq -n --argjson a "$(cat "$fx/stage-4242.json")" --argjson b "$( [ -f "$fx/stage-4242-2.json" ] && cat "$fx/stage-4242-2.json" || echo '[]')" --argjson t0 "$((act_epoch - 90000))" '
    {OWNER:"owner-op",MEMBER:"member-op",COLLABORATOR:"collab-op",CONTRIBUTOR:"contrib-op",NONE:"none-op"} as $m
    | {comments: ($a + $b | to_entries | map({author:{login:(.value.login // $m[.value.author_association])},
        authorAssociation:.value.author_association, createdAt:($t0 + .key * 60 | todate), body:.value.body}))}' > "$fx/gql-comments-4242.json"
  if (( nocreated )); then assert_fixture_dir "$fx"; jq 'del(.comments[].createdAt)' "$fx/gql-comments-4242.json" > "$fx/nc.json" && mv "$fx/nc.json" "$fx/gql-comments-4242.json"; fi
  local pp=admin; (( permfail )) && pp=403
  printf 'owner-op\tadmin\nmember-op\twrite\ncollab-op\twrite\ncontrib-op\tread\nnone-op\t404\npriv-op\t%s\nownread-op\tread\nmaint-op\tmaintain\n' "$pp" > "$fx/perms.tsv"
}

# expect <label> <want-rc> <want-text> <fx> [env...]  — runs $PROBE_UNDER (default the live probe)
PROBE_UNDER="$PROBE"
CRASH_RE='syntax error|command not found|unbound variable|bad substitution|unexpected EOF'
note_crash() { if grep -qE "$CRASH_RE" <<<"$1"; then : > "$TMP/crashed"; fi; }
expect() {
  local label="$1" want="$2" text="$3" fx="$4"; shift 4
  local out rc
  out="$(env FX="$fx" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$fx/ADR-276-fixture.md" SOAK_TEST_ALL="$fx/test-all.sh" "$@" bash "$PROBE_UNDER" 2>&1)"; rc=$?
  note_crash "$out"
  if [ -s "$fx/refused.log" ]; then fail "$label: the fake gh REFUSED an argv (the row would pass or fail for the wrong reason): $(head -2 "$fx/refused.log" | tr '\n' '|')"; return; fi
  if [[ "$rc" == "$want" && "$out" == *"$text"* ]]; then pass "$label (rc=$rc)"; else fail "$label: want rc=$want containing '$text', got rc=$rc: $(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}

# mk_tree <name> [probe source] [nolink|nofn|srcfail|onlybodies|onlycomments] -> prints the path of a copy of the probe inside a MIRRORED tree: the probe
# sources the trust lib by a relative path, so a lone copy in $TMP would resolve no lib, the source guard would exit 3 on EVERY row, every mutant
# would be "caught" by that alone and the verdict would prove nothing. scripts/lib is a symlink to the real lib (probe-only mutants; lib
# mutants live in the lib suite); `nolink` leaves it out (a control), `nofn` puts a lib that sources cleanly but defines no view, `srcfail` one that
# defines both views and then returns non-zero, `onlybodies` | `onlycomments` one that defines only that view (an empty-answering stub).
mk_tree() {
  local d="$TMP/tree-$1"; rm -rf "$d"; mkdir -p "$d/scripts/followthroughs"
  cp "${2:-$PROBE}" "$d/scripts/followthroughs/ci-push-dedupe-soak-9512.sh"
  case "${3:-}" in
    nolink) : ;;
    nofn) mkdir -p "$d/scripts/lib"; printf '# a lib that defines nothing\n' > "$d/scripts/lib/trusted-verdict.sh" ;;
    srcfail) mkdir -p "$d/scripts/lib"; printf 'trusted_verdict_bodies() { return 0; }\ntrusted_verdict_comments() { return 0; }\nreturn 3\n' > "$d/scripts/lib/trusted-verdict.sh" ;;
    onlybodies) mkdir -p "$d/scripts/lib"; printf 'trusted_verdict_bodies() { return 0; }\n' > "$d/scripts/lib/trusted-verdict.sh" ;;
    onlycomments) mkdir -p "$d/scripts/lib"; printf 'trusted_verdict_comments() { return 0; }\n' > "$d/scripts/lib/trusted-verdict.sh" ;;
    *) ln -s "$REPO_ROOT/scripts/lib" "$d/scripts/lib" ;;
  esac
  printf '%s\n' "$d/scripts/followthroughs/ci-push-dedupe-soak-9512.sh"
}

# 25 runs: 10 elided at 510 s + 15 full at 2568 s => total 43620 s => exactly 29.08 min/run (the limit, a must-PASS)
r_pass()      { build_fx "$TMP/c1" 10 15 510 2568;                  expect "PASS: 10 elided, 12 days, mean exactly 29.08, marker present, decoy jobs ignored" 0 "PASS" "$TMP/c1"; }
r_zero()      { build_fx "$TMP/c2" 0 25 510 2568;                   expect "NOT YET: zero elided runs is never a pass" 2 "NOT YET: 0 elided" "$TMP/c2"; }
r_unmatched1(){ build_fx "$TMP/c3" 10 15 510 2568 unmatched=1;      expect "FAIL: an elided run with no merge_group voucher" 1 "no completed success merge_group run" "$TMP/c3"; }
r_unmatched3(){ build_fx "$TMP/c4" 10 15 510 2568 unmatched=3;      expect "FAIL: a second and third unvouched run after a compliant first" 1 "3 elided push run" "$TMP/c4"; }
r_over()      { build_fx "$TMP/c5" 10 15 510 2569;                  expect "FAIL: mean 29.0801 over ALL runs (one second over the limit)" 1 "mean" "$TMP/c5"; }
r_allmean()   { build_fx "$TMP/c6" 10 20 510 4200;                  expect "FAIL: the mean is over ALL runs; the elided-only mean (8.5) would pass" 1 "over 29.08" "$TMP/c6"; }
r_nomarker()  { build_fx "$TMP/c7" 10 15 510 2568 marker=none;      expect "NOT YET: no S2-EXIT-CENSUS marker (the sweeper closes on exit 0)" 2 "S2-EXIT-CENSUS" "$TMP/c7"; }
r_nine()      { build_fx "$TMP/c8" 9 16 510 2568;                   expect "NOT YET: 9 elided runs" 2 "9 elided" "$TMP/c8"; }
r_six()       { build_fx "$TMP/c9" 10 15 510 2568 actdays=6;        expect "NOT YET: 6 days since activation" 2 "6 day" "$TMP/c9"; }
r_seven()     { build_fx "$TMP/c10" 10 15 510 2568 actdays=7;       expect "boundary: exactly 7 days PASSES" 0 "PASS" "$TMP/c10"; }
r_precedence(){ build_fx "$TMP/c11" 3 20 510 2568 unmatched=1 actdays=2 marker=none; expect "FAIL takes precedence over NOT YET (wrong elision with too few runs, days, no marker)" 1 "FAIL" "$TMP/c11"; }
r_jobsfail()  { build_fx "$TMP/c12" 10 15 510 2568 failjobs;        expect "CANNOT ESTABLISH: a jobs read fails" 3 "CANNOT ESTABLISH" "$TMP/c12"; }
r_decoy_mixed(){ build_fx "$TMP/c13" 10 15 510 2568 extra=mixed;    expect "PASS: a run with mixed skipped/success test-scripts legs is NOT elided" 0 "elided=10 " "$TMP/c13"; }
r_decoy_nots() { build_fx "$TMP/c14" 10 15 510 2568 extra=nots;     expect "PASS: a run with no test-scripts job at all is NOT elided" 0 "elided=10 " "$TMP/c14"; }
r_decoy_pdred(){ build_fx "$TMP/c15" 10 15 510 2568 extra=pdred;    expect "PASS: skipped test-scripts with a RED push-dedupe is NOT elided" 0 "elided=10 " "$TMP/c15"; }
r_noperm_act(){ build_fx "$TMP/d4" 0 25 510 2568 untrustedact;   expect "NOT YET: an activation comment by a login with no repository permission (404) is ignored" 2 "not activated" "$TMP/d4"; }
r_noperm_act_elided(){ build_fx "$TMP/d5" 5 20 510 2568 untrustedact; expect "FAIL: elided runs while the only activation is by a login with no repository permission" 1 "no activation on record" "$TMP/d5"; }
r_noperm_marker(){ build_fx "$TMP/d6" 10 15 510 2568 marker=untrusted; expect "NOT YET: an exit-census marker by a login with no repository permission does not count" 2 "S2-EXIT-CENSUS" "$TMP/d6"; }
r_nonurl_marker(){ build_fx "$TMP/d6b" 10 15 510 2568 marker=nonurl; expect "NOT YET: an exit-census marker without an https github URL does not count" 2 "S2-EXIT-CENSUS" "$TMP/d6b"; }
r_adr_proposed(){ build_fx "$TMP/d12" 10 15 510 2568 adr=proposed;  expect "FAIL: elided runs while ADR-276 still reads proposed" 1 "'proposed'" "$TMP/d12"; }
r_unregistered(){ build_fx "$TMP/d13" 10 15 510 2568 noreg;         expect "FAIL: the proof suite is no longer registered in test-all.sh" 1 "no longer registered" "$TMP/d13"; }
r_stuck29()   { build_fx "$TMP/d14" 4 21 510 2568 actdays=29 merged=2026-09-20T00:00:00Z; expect "NOT YET: 29 days active with 4 elided runs (the deadline is 30)" 2 "4 elided" "$TMP/d14"; }
r_stuck30()   { build_fx "$TMP/d15" 4 21 510 2568 actdays=30 merged=2026-09-20T00:00:00Z; expect "FAIL: 30 days active and the proof is not eliding" 1 "proof is not eliding" "$TMP/d15"; }
r_privmember(){ build_fx "$TMP/g1" 10 15 510 2568 privact;          expect "PASS: an activation by a private-org-member admin (decoy association CONTRIBUTOR) counts: trust is the permission lookup" 0 "PASS" "$TMP/g1"; }
r_assoc_decoy(){ build_fx "$TMP/g2" 0 25 510 2568 assocowner;        expect "NOT YET: an activation by an OWNER-association author whose permission is read is ignored (the association is a decoy)" 2 "not activated" "$TMP/g2"; }
r_permfail()  { build_fx "$TMP/g3" 10 15 510 2568 permfail;          expect "CANNOT ESTABLISH: a 403 on the activation author's permission read is never a pass and never 'untrusted'" 3 "comment or permission read failed" "$TMP/g3"; }
r_nolib()     { build_fx "$TMP/g4" 10 15 510 2568
  local keep="$PROBE_UNDER" t; t="$(mk_tree nolib "$PROBE_UNDER" nolink)"; PROBE_UNDER="$t"
  expect "CANNOT ESTABLISH: a missing trust lib is its own message, never 'GitHub API read failed'" 3 "CANNOT ESTABLISH: trusted-verdict lib unavailable" "$TMP/g4"
  PROBE_UNDER="$keep"; }
r_nofn()      { build_fx "$TMP/g4b" 10 15 510 2568
  local keep="$PROBE_UNDER" t; t="$(mk_tree nofn "$PROBE_UNDER" nofn)"; PROBE_UNDER="$t"
  expect "CANNOT ESTABLISH: a lib that sources but defines no view is the same message" 3 "CANNOT ESTABLISH: trusted-verdict lib unavailable" "$TMP/g4b"
  PROBE_UNDER="$keep"; }
r_srcfail()   { build_fx "$TMP/g4c" 10 15 510 2568
  local keep="$PROBE_UNDER" t; t="$(mk_tree srcfail "$PROBE_UNDER" srcfail)"; PROBE_UNDER="$t"
  expect "CANNOT ESTABLISH: a lib whose source returns non-zero is the same message even when both views are defined" 3 "CANNOT ESTABLISH: trusted-verdict lib unavailable" "$TMP/g4c"
  PROBE_UNDER="$keep"; }
r_nobodies()  { build_fx "$TMP/g4d" 10 15 510 2568
  local keep="$PROBE_UNDER" t; t="$(mk_tree nobodies "$PROBE_UNDER" onlycomments)"; PROBE_UNDER="$t"
  expect "CANNOT ESTABLISH: a lib lacking ONLY the bodies view (the view this probe calls) is the lib-unavailable message" 3 "CANNOT ESTABLISH: trusted-verdict lib unavailable" "$TMP/g4d"
  PROBE_UNDER="$keep"; }
r_onlybodies(){ build_fx "$TMP/g4e" 0 25 510 2568 noact
  local keep="$PROBE_UNDER" t; t="$(mk_tree onlybodies "$PROBE_UNDER" onlybodies)"; PROBE_UNDER="$t"
  expect "NOT YET: a lib lacking ONLY the comments view (a view this probe never calls) still runs the probe" 2 "not activated" "$TMP/g4e"
  PROBE_UNDER="$keep"; }
r_bodies_nocreated() { build_fx "$TMP/g4f" 10 15 510 2568 nocreated; expect "PASS: trusted comments with NO createdAt still activate and census: this probe reads the BODIES view, which ignores t (the comments view would be exit 3)" 0 "PASS" "$TMP/g4f"; }
r_trfail()    { build_fx "$TMP/g4g" 10 15 510 2568
  assert_fixture_dir "$TMP"; mkdir -p "$TMP/bin-trfail"; printf '#!/usr/bin/env bash\nexit 5\n' > "$TMP/bin-trfail/tr"; chmod +x "$TMP/bin-trfail/tr"
  expect "CANNOT ESTABLISH: a failing CR strip (tr) is never read as 'no marker', and the label says the LOCAL projection failed (not a comment or permission read)" 3 "comment projection failed (local tool) (tracker 4242 comments (CR strip))" "$TMP/g4g" PATH="$TMP/bin-trfail:$TMP/bin:$PATH"; }
NEED_NEW=(grep sed tr tail head date rm dirname)   # the tools the probe or the lib runs by name that the need list did not name before the review
r_needtools() { build_fx "$TMP/g4h" 10 15 510 2568
  local t b ok=1 d out rc; assert_fixture_dir "$TMP"
  for t in "${NEED_NEW[@]}"; do
    d="$TMP/bin-no-$t"; rm -rf "$d"; mkdir -p "$d"; cp "$TMP/bin/gh" "$d/gh"
    for b in bash env cat dirname rm mkdir mktemp basename wc cut uniq sort grep sed tr tail head date awk jq base64 timeout; do
      [ "$b" = "$t" ] && continue
      command -v "$b" >/dev/null 2>&1 && ln -s "$(command -v "$b")" "$d/$b"
    done
    out="$(env FX="$TMP/g4h" PATH="$d" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$TMP/g4h/ADR-276-fixture.md" SOAK_TEST_ALL="$TMP/g4h/test-all.sh" bash "$PROBE_UNDER" 2>&1)"; rc=$?
    if [[ "$rc" != 3 || "$out" != *"CANNOT ESTABLISH: $t is not installed"* ]]; then ok=0; fail "need tools: without $t want rc 3 'CANNOT ESTABLISH: $t is not installed', got rc=$rc: $(printf '%s' "$out" | head -2 | tr '\n' '|')"; fi
  done
  (( ok )) && pass "CANNOT ESTABLISH: each of ${NEED_NEW[*]} missing from PATH is exit 3 naming it, never a silent 'no marker'"; }
# mkshim <dir> <tool> <glob over the joined argv> <nth matching call> <err|silent>: a dir with the fake gh and ONE tool that, on its nth call whose
# argv matches the glob, exits 2 (err) or exits 0 printing nothing (silent), and runs the real tool on every other call
mkshim() {
  local d="$1" t="$2" pat="$3" nth="$4" mode="$5" act real; real="$(command -v "$t")"
  case "$mode" in err) act='exit 2' ;; silent) act='exit 0' ;; esac
  assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d"; cp "$TMP/bin/gh" "$d/gh"
  printf '#!/usr/bin/env bash\ncase "$*" in %s) n=$(( $(cat %q 2>/dev/null || echo 0) + 1 )); echo "$n" > %q; if [ "$n" = %s ]; then %s; fi ;; esac\nexec %q "$@"\n' \
    "$pat" "$d/cnt" "$d/cnt" "$nth" "$act" "$real" > "$d/$t"
  chmod +x "$d/gh" "$d/$t"
}
# the marker chains: each (chain, tool) failure injected on ITS chain only is exit 3 naming the read, never "no marker". The DEACTIVATED chain runs against a fixture whose
# HEALTHY verdict is FAIL (a dropped DEACTIVATED marker used to read as an active soak and PASS at rc 0).
r_markers() {
  local spec label tool pat nth mode kind d fx n=0
  local -a specs=(
    "S2-ACTIVATED|grep|*S2-ACTIVATED*|1|err|pass"   "S2-ACTIVATED|sed|*S2-ACTIVATED*|1|err|pass"   "S2-ACTIVATED|sort|*|1|err|pass"   "S2-ACTIVATED|tail|*|1|err|pass"
    "S2-DEACTIVATED|grep|*S2-DEACTIVATED*|1|err|deact" "S2-DEACTIVATED|sed|*S2-DEACTIVATED*|1|err|deact" "S2-DEACTIVATED|sort|*|2|err|deact" "S2-DEACTIVATED|tail|*|2|err|deact"
    "S2-EXIT-CENSUS|grep|*S2-EXIT-CENSUS*|1|err|pass" "S2-EXIT-CENSUS|grep|*S2-EXIT-CENSUS*|1|silent|pass")
  for spec in "${specs[@]}"; do
    IFS='|' read -r label tool pat nth mode kind <<<"$spec"; n=$((n + 1)); fx="$TMP/mk$n"; d="$TMP/bin-mk$n"
    if [ "$kind" = deact ]; then build_fx "$fx" 10 15 510 2568 deact; else build_fx "$fx" 10 15 510 2568; fi
    mkshim "$d" "$tool" "$pat" "$nth" "$mode"
    expect "CANNOT ESTABLISH: $tool ($mode) failing on the $label chain only is exit 3 naming that read, never 'no marker'" 3 "CANNOT ESTABLISH: marker read failed ($label)" "$fx" PATH="$d:$TMP/bin:$PATH"
  done
}
r_deact_healthy() { build_fx "$TMP/mkh" 10 15 510 2568 deact; expect "FAIL: the healthy verdict of the DEACTIVATED fixture (elided runs after a recorded deactivation) is FAIL, so a dropped DEACTIVATED marker would have been a PASS" 1 "no activation on record" "$TMP/mkh"; }
r_needcomplete() { build_fx "$TMP/g4i" 10 15 510 2568
  local d="$TMP/bin-exact" t line out rc; assert_fixture_dir "$TMP"; rm -rf "$d"; mkdir -p "$d"; cp "$TMP/bin/gh" "$d/gh"
  line="$(grep -m1 '^for need in ' "$PROBE_UNDER")"; line="${line#for need in }"; line="${line%%; do*}"
  for t in $line bash env cat; do if [ ! -e "$d/$t" ] && command -v "$t" >/dev/null 2>&1; then ln -s "$(command -v "$t")" "$d/$t"; fi; done
  out="$(env FX="$TMP/g4i" PATH="$d" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$TMP/g4i/ADR-276-fixture.md" SOAK_TEST_ALL="$TMP/g4i/test-all.sh" bash "$PROBE_UNDER" 2>&1)"; rc=$?
  if [[ "$rc" == 0 && "$out" == *"PASS"* && "$out" != *"not found"* ]]; then pass "PASS on a PATH holding exactly the need list (+ bash env cat): the list names every external command the probe and the lib run"
  else fail "need list incomplete: rc=$rc out=$(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi; }
r_write_act() { build_fx "$TMP/g5" 10 15 510 2568 collabact;         expect "PASS: an activation by an author holding write counts, whatever the decoy association" 0 "PASS" "$TMP/g5"; }
r_maint_act(){ build_fx "$TMP/g6" 10 15 510 2568 noneact;        expect "PASS: an activation by an author holding maintain counts, whatever the decoy association" 0 "PASS" "$TMP/g6"; }
r_nonactive_deadline(){ build_fx "$TMP/d7" 0 25 510 2568 noact;     expect "FAIL: 30 days after the merge and nothing activated: activate, or revert" 1 "activate, or revert" "$TMP/d7" SOAK_NOW_EPOCH=$((NOW_EPOCH + 31 * 86400)); }
r_deact()     { build_fx "$TMP/d16" 0 25 510 2568 deact;            expect "NOT YET: a later S2-DEACTIVATED ends the activation" 2 "not activated" "$TMP/d16"; }
r_commentsfail(){ build_fx "$TMP/e-c" 10 15 510 2568 failcomments;  expect "CANNOT ESTABLISH: the tracker comments read fails (403)" 3 "comment or permission read failed" "$TMP/e-c"; }
r_adr_idle()  { build_fx "$TMP/f1" 0 25 510 2568 noact adr=proposed; expect "NOT YET: ADR-276 reading proposed with NOTHING elided is not a failure" 2 "not activated" "$TMP/f1"; }
r_adr_quoted(){ build_fx "$TMP/f2" 10 15 510 2568 'adr="proposed"';  expect "FAIL: a quoted \"proposed\" status still counts" 1 "'proposed'" "$TMP/f2"; }
r_adr_case()  { build_fx "$TMP/f3" 10 15 510 2568 adr=Proposed;      expect "FAIL: a capitalised Proposed status still counts" 1 "'proposed'" "$TMP/f3"; }
r_adr_note()  { build_fx "$TMP/f4" 10 15 510 2568 "adr='proposed'  # pending the CTO"; expect "FAIL: single quotes and a trailing # note still read as proposed" 1 "'proposed'" "$TMP/f4"; }
r_adr_nostatus(){ build_fx "$TMP/f5" 10 15 510 2568 nostatus;        expect "CANNOT ESTABLISH: an ADR with no status line is never read as adopting" 3 "status line" "$TMP/f5"; }
r_adr_missing(){ build_fx "$TMP/f6" 10 15 510 2568;                  expect "CANNOT ESTABLISH: the ADR file is missing" 3 "ADR-276 file" "$TMP/f6" SOAK_ADR_FILE="$TMP/f6/none.md"; }
r_testall_missing(){ build_fx "$TMP/f7" 10 15 510 2568;              expect "CANNOT ESTABLISH: scripts/test-all.sh is unreadable" 3 "test-all.sh" "$TMP/f7" SOAK_TEST_ALL="$TMP/f7/none.sh"; }
r_regcomment(){ build_fx "$TMP/f8" 10 15 510 2568 regcomment;        expect "FAIL: a comment or echo naming the suite is not a registration" 1 "no longer registered" "$TMP/f8"; }
r_prefull()   { build_fx "$TMP/f9" 10 15 510 2568 prefull=3;         expect "PASS: expensive NON-elided runs before the activation stay out of the mean" 0 "elided=10 " "$TMP/f9"; }
r_reactivate(){ build_fx "$TMP/f10" 10 15 510 2568 reactivate;       expect "PASS: a DEACTIVATED marker EARLIER than the activation does not end it" 0 "PASS" "$TMP/f10"; }
r_twoact()    { build_fx "$TMP/f11" 10 15 510 2568 twoact;           expect "the LATEST of two ACTIVATED markers sets the age" 0 "age_days=12 " "$TMP/f11"; }
r_twodeact()  { build_fx "$TMP/f12" 0 25 510 2568 twodeact;          expect "NOT YET: the LATEST of two DEACTIVATED markers ends the activation" 2 "not activated" "$TMP/f12"; }
r_latebatch() { build_fx "$TMP/f13" 0 25 510 2568 deact latebatch;   expect "NOT YET: a DEACTIVATED marker staged in a second fixture batch is read (the probe does not slice the comment list; gh's own paging is measured 220/220 on #9777, not modelled here)" 2 "not activated" "$TMP/f13"; }
r_idle_cap()  { build_fx "$TMP/f14" 0 12 510 2568 noact early=1;     expect "NOT YET: while idle only the newest 10 runs are sampled (an elided run at position 13 is outside)" 2 "not activated" "$TMP/f14"; }
r_max_cap()   { build_fx "$TMP/f15" 10 60 510 2000;                  expect "FAIL: all 70 runs (the cap is 100) set the mean; the newest 30 alone would pass" 1 "over 29.08" "$TMP/f15"; }
r_would()     { build_fx "$TMP/f16" 10 15 510 2568;                  expect "the 'Proof holds for this SHA' step conclusions are counted" 0 "would_elide_runs=10 " "$TMP/f16"; }
r_marker_write()    { build_fx "$TMP/f17" 10 15 510 2568 marker=collab;    expect "PASS: an exit-census comment by an author holding write counts" 0 "PASS" "$TMP/f17"; }
r_marker_read()   { build_fx "$TMP/f18" 10 15 510 2568 marker=contrib;   expect "NOT YET: an exit-census comment by an author holding only read does not count" 2 "S2-EXIT-CENSUS" "$TMP/f18"; }
r_crlf()      { build_fx "$TMP/f19" 10 15 510 2568 crlf;             expect "PASS: CRLF comment lines (browser-posted) still parse" 0 "PASS" "$TMP/f19"; }
r_badts()     { build_fx "$TMP/f20" 0 25 510 2568 badts;             expect "NOT YET: an ACTIVATED timestamp without the Z is not a marker" 2 "not activated" "$TMP/f20"; }
r_midact()    { build_fx "$TMP/f21" 0 25 510 2568 midact;            expect "NOT YET: ACTIVATED mid-line or with trailing text is not a marker" 2 "not activated" "$TMP/f21"; }
r_lookalike() { build_fx "$TMP/f22" 10 15 510 2568 marker=lookalike; expect "NOT YET: a lookalike host (githubXcom) is not a census URL" 2 "S2-EXIT-CENSUS" "$TMP/f22"; }
r_foreign()   { build_fx "$TMP/f23" 10 15 510 2568 marker=foreign;   expect "NOT YET: a non-github URL is not a census URL" 2 "S2-EXIT-CENSUS" "$TMP/f23"; }
r_pdbad6()    { build_fx "$TMP/f24" 10 15 510 2568 pdbad=6;          expect "FAIL: push-dedupe red in 6 of 25 sampled runs (over 20%)" 1 "push-dedupe job failed in 6 of 25" "$TMP/f24"; }
r_pdbad5()    { build_fx "$TMP/f25" 10 15 510 2568 pdbad=5;          expect "PASS: push-dedupe red in exactly 20% of the sampled runs" 0 "push_dedupe_failed=5/25" "$TMP/f25"; }
r_pdbad_dark(){ build_fx "$TMP/f26" 0 25 510 2568 noact pdbad=6;     expect "FAIL: a failing push-dedupe is reported while still dark" 1 "push-dedupe job failed in 6 of 10" "$TMP/f26"; }
r_pdbad_few() { build_fx "$TMP/f27" 0 4 510 2568 noact pdbad=4;      expect "NOT YET: fewer than 5 sampled runs are never judged on push-dedupe failures" 2 "not activated" "$TMP/f27"; }
r_deadline_edge(){ build_fx "$TMP/f28" 0 25 510 2568 noact;          expect "NOT YET: exactly 30 days after the merge is not yet past the deadline" 2 "not activated" "$TMP/f28" SOAK_NOW_EPOCH=$(( $(date -u -d "$MERGED_ISO" +%s) + 30 * 86400 )); }
ALL_ROWS=(r_pass r_zero r_unmatched1 r_unmatched3 r_over r_allmean r_nomarker r_nine r_six r_seven r_precedence r_jobsfail
          r_decoy_mixed r_decoy_nots r_decoy_pdred r_noperm_act r_noperm_act_elided r_noperm_marker r_nonurl_marker
          r_adr_proposed r_unregistered r_stuck29 r_stuck30 r_nonactive_deadline r_deact r_commentsfail
          r_adr_idle r_adr_quoted r_adr_case r_adr_note r_adr_nostatus r_adr_missing r_testall_missing r_regcomment r_prefull
          r_reactivate r_twoact r_twodeact r_latebatch r_idle_cap r_max_cap r_would r_marker_write r_marker_read r_crlf r_badts r_midact
          r_lookalike r_foreign r_pdbad6 r_pdbad5 r_pdbad_dark r_pdbad_few r_deadline_edge r_privmember r_assoc_decoy r_permfail r_nolib r_nofn r_srcfail r_write_act r_maint_act r_nobodies r_onlybodies r_bodies_nocreated r_trfail r_needtools r_markers r_deact_healthy r_needcomplete)
run_rows() { local r; for r in "$@"; do "$r"; done; }
run_rows "${ALL_ROWS[@]}"

# --- the rest of the contract (not mutated below) -----------------------------------------------------------------
build_fx "$TMP/d1" 5 20 510 2568 noact;                 expect "FAIL: elided runs with nothing activated on the tracker (an org-level or unrecorded flip)" 1 "no activation on record" "$TMP/d1"
build_fx "$TMP/d2" 10 15 510 2568 early=2;              expect "FAIL: two runs elided BEFORE the recorded activation" 1 "2 push run" "$TMP/d2"
build_fx "$TMP/d3" 0 25 510 2568 noact;                 expect "NOT YET: not activated, nothing elided" 2 "not activated" "$TMP/d3"
build_fx "$TMP/d8" 10 15 510 2568 unmerged;             expect "NOT YET: the S2 PR is not merged" 2 "not merged" "$TMP/d8"
build_fx "$TMP/d9" 10 15 510 2568 marker=mid;           expect "NOT YET: the marker must start a line, a mention does not count" 2 "S2-EXIT-CENSUS" "$TMP/d9"
build_fx "$TMP/d9b" 10 15 510 2568 marker=placeholder;  expect "NOT YET: the literal placeholder S2-EXIT-CENSUS: <url> does not count" 2 "S2-EXIT-CENSUS" "$TMP/d9b"
build_fx "$TMP/d10" 10 15 510 2568 noissue;             expect "NOT YET: the tracker is not among the open follow-through issues" 2 "tracker issue" "$TMP/d10"
build_fx "$TMP/d11" 10 15 510 2568 pdred;               expect "PASS: a full run whose push-dedupe is red is a normal full run, not a wrong elision" 0 "PASS" "$TMP/d11"
build_fx "$TMP/d17" 10 15 510 2568 adr=adopting;        expect "PASS: ADR-276 reading adopting allows the soak to pass" 0 "adr_status=adopting" "$TMP/d17"
for r in push mg; do
  build_fx "$TMP/e-$r" 10 15 510 2568 "fail$r"
                                                        expect "CANNOT ESTABLISH: the $r read fails (never a pass, never a fail)" 3 "CANNOT ESTABLISH" "$TMP/e-$r"
done
build_fx "$TMP/e1" 10 15 510 2568;                      expect "an unset GH_TOKEN is CANNOT ESTABLISH, never a pass" 3 "GH_TOKEN is not set" "$TMP/e1" GH_TOKEN=
build_fx "$TMP/e2" 10 15 510 2568
out="$(env FX="$TMP/e2" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$TMP/e2/ADR-276-fixture.md" SOAK_TEST_ALL="$TMP/e2/test-all.sh" bash -x "$PROBE" 2>&1)"; rc=$?
if [[ "$rc" == 78 ]]; then pass "xtrace with a live GH_TOKEN is refused (rc=78)"; else fail "xtrace refusal: rc=$rc"; fi
# the query shapes the probe documents: the push window, the exact jobs read, open-only tracker lookup, and a
# merge_group window anchored one day before the OLDEST sampled run (the oldest of c1's runs is act+1h)
_act=$((NOW_EPOCH - 12 * 86400)); _bound="$(date -u -d "@$((_act + 3600 - 86400))" +%Y-%m-%dT%H:%M:%SZ)"
if grep -cF 'created=%3E2026-10-10T00:00:00Z' "$TMP/c1/requests.log" >/dev/null && grep -cF 'branch=main&status=completed' "$TMP/c1/requests.log" >/dev/null \
   && grep -cF "event=merge_group&per_page=100&created=%3E$_bound" "$TMP/c1/requests.log" >/dev/null \
   && grep -cF '/jobs?per_page=100&filter=latest' "$TMP/c1/requests.log" >/dev/null \
   && grep -cF 'issues?labels=follow-through&state=open&per_page=100' "$TMP/c1/requests.log" >/dev/null; then pass "the queries carry their documented parameters (push window, merge_group bound, jobs filter, open tracker)"
else fail "the queries lost their parameters: $(head -6 "$TMP/c1/requests.log" | tr '\n' '|')"; fi
# the trust read: ONE `issue view` of the tracker, and one permission request per distinct human author (c1 has three: noted by the
# owner, the activation by priv-op, the census by a member), each shaped repos/<repo>/collaborators/<login>/permission
_n_iv="$(grep -cxF 'issue view 4242 --repo jikig-ai/soleur --json comments' "$TMP/c1/requests.log")"
_n_pm="$(grep -cE '^repos/jikig-ai/soleur/collaborators/[a-z-]+/permission$' "$TMP/c1/requests.log")"
_n_pu="$(grep -E '^repos/jikig-ai/soleur/collaborators/[a-z-]+/permission$' "$TMP/c1/requests.log" | sort -u | wc -l)"
if [ "$_n_iv" = 1 ] && [ "$_n_pm" = 3 ] && [ "$_n_pu" = 3 ] && ! grep -q 'issues/4242/comments' "$TMP/c1/requests.log"; then
  pass "the probe reads the tracker through ONE issue view and resolves each distinct author once (no REST comments read)"
else fail "trust-read request shape: issue-view=$_n_iv permission=$_n_pm distinct=$_n_pu legacy=$(grep -c 'issues/4242/comments' "$TMP/c1/requests.log")"; fi

# --- mutation rows: each mutated COPY of the probe must turn at least one named row red ----------------------------------
MUT_RUN=0; MUT_CAUGHT=0
# mutant_probe <name> <old> <new> <row ids...>: build the mutated copy INSIDE a mirrored tree and run the rows against it. Sets
# MUT_LANDED, MUT_CRASHED and (through core_rows_quiet) MUT_REDS. A bash-level error in the mutant's output means it CRASHED: every
# row then reads red, which proves nothing about the guard that was removed.
MUT_LANDED=1; MUT_CRASHED=0
mutant_probe() {
  local name="$1" old="$2" new="$3"; shift 3
  local f="$TMP/mut-$name.sh"
  MUT_LANDED=1; MUT_CRASHED=0; MUT_REDS=0; rm -f "$TMP/crashed"
  if ! python3 - "$PROBE" "$f" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  then MUT_LANDED=0; return 0; fi
  cmp -s "$f" "$PROBE" && { MUT_LANDED=0; return 0; }
  chmod +x "$f"
  bash -n "$f" 2>/dev/null || MUT_CRASHED=1
  PROBE_UNDER="$(mk_tree "m-$name" "$f")"; core_rows_quiet "$@"; PROBE_UNDER="$PROBE"
  [ -f "$TMP/crashed" ] && MUT_CRASHED=1
  return 0
}
mutant() { # <name> <old> <new> <row ids...>
  local name="$1"
  MUT_RUN=$((MUT_RUN + 1))
  mutant_probe "$@"
  if [ "$MUT_LANDED" -eq 0 ]; then fail "MUTANT $name: mutation did NOT land (or is byte-identical to the probe)"; return; fi
  if [ "$MUT_CRASHED" -eq 1 ]; then fail "MUTANT $name: the mutant CRASHED (a bash error), which proves nothing"; return; fi
  if [ "$MUT_REDS" -gt 0 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "MUTANT $name turned $MUT_REDS named row(s) red"
  else fail "MUTANT $name: none of rows [${*:4}] went red"; fi
}
core_rows_quiet() { # run the named rows against $PROBE_UNDER, counting reds without recording them as this suite's failures
  local p0=$passes f0=$fails a0=$asserted n0=${#FAILURES[@]}
  run_rows "$@" >/dev/null
  MUT_REDS=$((fails - f0))
  passes=$p0; fails=$f0; asserted=$a0; FAILURES=("${FAILURES[@]:0:$n0}")
}
mutant m-min-elided   '(( elided < MIN_ELIDED || age_days < MIN_DAYS ))' '(( 0 ))' r_nine r_six r_zero
mutant m-no-voucher   'if ! [ "${covered:-0}" -gt 0 ] 2>/dev/null; then' 'if false; then' r_unmatched1 r_unmatched3
mutant m-first-only   'elided=$((elided + 1))' 'elided=$((elided + 1)); [ "$elided" -gt 1 ] && continue' r_unmatched3
mutant m-elided-mean  'n=$((n + 1)); total_s=$((total_s + secs))' 'n=$((n + 1)); [ "$is_elided" = "yes" ] && total_s=$((total_s + secs))' r_allmean r_over
mutant m-boundary     'total_s * 100 > MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n' 'total_s * 100 >= MEAN_LIMIT_HUNDREDTHS_MIN * 60 * n' r_pass
mutant m-api-quiet    'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }' 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 0; }' r_jobsfail r_commentsfail
mutant m-precedence   'if (( wrong > 0 )); then' 'if (( wrong > 0 && elided >= MIN_ELIDED )); then' r_precedence
mutant m-no-marker    'if (( census_marked == 0 )); then' 'if false; then' r_nomarker r_noperm_marker r_nonurl_marker
mutant m-unmatched-ok 'covered="$(jq -r --arg sha "$sha" '"'"'map(select(. == $sha)) | length'"'"' <<<"$mg_json" 2>/dev/null)" || fail_api "voucher lookup"' 'covered=1' r_unmatched1
mutant m-trusted      'trusted_raw="$(trusted_verdict_bodies "$tracker" "$REPO")" || fail_comments "tracker $tracker comments (trusted-author resolution)"' 'trusted_raw="$(trusted_verdict_bodies "$tracker" "$REPO")"' r_commentsfail r_permfail
mutant m-adr-status   '[ "$adr_status" = "proposed" ]' '[ "$adr_status" = "never" ]' r_adr_proposed
mutant m-registered   'if (( suite_registered == 0 )); then' 'if false; then' r_unregistered
mutant m-stuck-deadline 'if (( age_days >= DEADLINE_DAYS )); then' 'if false; then' r_stuck30
mutant m-ts-any       '($ts | all(.conclusion == "skipped"))' '($ts | any(.conclusion == "skipped"))' r_decoy_mixed
mutant m-ts-empty     '($ts | length) > 0 and ' '' r_decoy_nots
mutant m-pd-success   '$pd > 0 and ' '' r_decoy_pdred
mutant m-skipped-filter '.conclusion != "skipped" and ((.runner_id' '((.runner_id' r_pass
mutant m-runner-type  '((.runner_id | type) == "number") and .runner_id > 0 and ' '' r_pass
mutant m-negdur       ' | select(. >= 0)' '' r_over
mutant m-deact        'if [ "$on_epoch" -gt "$off_epoch" ]; then' 'if true; then' r_deact
mutant m-adr-needs-elided '(( elided_any > 0 )) && [ "$adr_status" = "proposed" ]' '[ "$adr_status" = "proposed" ]' r_adr_idle
mutant m-adr-quotes 'tr -d "\"'"'"'[:space:]"' 'tr -d "[:space:]"' r_adr_quoted r_adr_note
mutant m-adr-nocomment 'sed '"'"'s/[[:space:]]*#.*$//'"'"' | ' '' r_adr_note
mutant m-adr-nolower ' | tr '"'"'A-Z'"'"' '"'"'a-z'"'"'' '' r_adr_case
mutant m-adr-missing-status '[ -n "$adr_status" ] || fail_api "ADR-276 status line"' ':' r_adr_nostatus
mutant m-testall-readable '[ -r "$TEST_ALL" ] || fail_api "scripts/test-all.sh"' ':' r_testall_missing
mutant m-registered-comment 'grep -cE '"'"'^[[:space:]]*run_suite[[:space:]].*scripts/ci-push-dedupe\.test\.sh'"'"'' 'grep -cF '"'"'scripts/ci-push-dedupe.test.sh'"'"'' r_regcomment
mutant m-continue-inside 'early_list="$early_list run=$id sha=${sha:0:10}"; fi
    continue' 'early_list="$early_list run=$id sha=${sha:0:10}"; continue; fi' r_prefull
mutant m-latest 'sort | tail -n 1; printf '"'"'#%s'"'"'' 'sort | head -n 1; printf '"'"'#%s'"'"'' r_twoact r_twodeact
mutant m-off-any '[ "$on_epoch" -gt "$off_epoch" ]' '[ -z "$last_off" ]' r_reactivate
mutant m-idle-cap '(( active )) || cap="$IDLE_RUNS"' ':' r_idle_cap
mutant m-max-cap 'MAX_RUNS=100 ' 'MAX_RUNS=30  ' r_max_cap
mutant m-would-count '[[ "$proof_holds" =~ ^[0-9]+$ ]] && [ "$proof_holds" -gt 0 ] && would=$((would + 1))' ':' r_would
mutant m-step-name 'select(.name == "Proof holds for this SHA" and' 'select(.name == "Proof holds" and' r_would
mutant m-crlf '"$trusted_raw" | tr -d '"'"'\r'"'"')"' '"$trusted_raw")"' r_crlf
# the trust-source mutants: the helper call is replaced by a raw `issue view` read through the same fake arm
_HELPER='trusted_raw="$(trusted_verdict_bodies "$tracker" "$REPO")" || fail_comments "tracker $tracker comments (trusted-author resolution)"'
mutant m-legacy-assoc "$_HELPER" 'trusted_raw="$(gh issue view "$tracker" --repo "$REPO" --json comments --jq '"'"'.comments[] | select(.authorAssociation | IN("OWNER", "MEMBER", "COLLABORATOR")) | .body'"'"')" || fail_comments "tracker $tracker comments"' r_privmember r_assoc_decoy
mutant m-unfiltered-raw "$_HELPER" 'trusted_raw="$(gh issue view "$tracker" --repo "$REPO" --json comments --jq '"'"'.comments[] | .body'"'"')" || fail_comments "tracker $tracker comments"' r_assoc_decoy r_noperm_act r_noperm_act_elided r_noperm_marker r_marker_read
mutant m-empty-helper "$_HELPER" 'trusted_raw=""' r_pass r_privmember r_seven r_write_act
mutant m-comments-quiet 'fail_comments() { echo "CANNOT ESTABLISH: comment or permission read failed ($1)"; exit 3; }' 'fail_comments() { echo "CANNOT ESTABLISH: comment or permission read failed ($1)"; exit 0; }' r_commentsfail r_permfail
# the function check removed AND the missing views stubbed to print nothing, so the mutant runs on instead of crashing on `command not found` (which proves nothing)
mutant m-no-fn-check ' \
   || ! declare -F trusted_verdict_bodies >/dev/null; then' ' \
   || { declare -F trusted_verdict_bodies >/dev/null || trusted_verdict_bodies() { :; }; false; }; then' r_nofn r_nobodies
mutant m-guard-wrong-view ' \
   || ! declare -F trusted_verdict_bodies >/dev/null; then' ' \
   || ! { declare -F trusted_verdict_comments >/dev/null && { declare -F trusted_verdict_bodies >/dev/null || trusted_verdict_bodies() { :; }; }; }; then' r_nobodies r_onlybodies
mutant m-comments-view "$_HELPER" 'trusted_raw="$(trusted_verdict_comments "$tracker" "$REPO" | jq -r .b)" || fail_comments "tracker $tracker comments (trusted-author resolution)"' r_bodies_nocreated
mutant m-tr-unchecked ' || fail_projection "tracker $tracker comments (CR strip)"' '' r_trfail
mutant m-projection-label 'fail_projection() { echo "CANNOT ESTABLISH: comment projection failed (local tool) ($1)"; exit 3; }' 'fail_projection() { echo "CANNOT ESTABLISH: comment or permission read failed ($1)"; exit 3; }' r_trfail
# the marker chains: each restored to the bare, unchecked form the review found (the status of every stage dropped)
mutant m-act-unchecked 'marker_stamp S2-ACTIVATED; last_on="$MARKER_VAL"' 'last_on="$(printf '"'"'%s\n'"'"' "$trusted" | grep -oE "^S2-ACTIVATED: $TS_RE\$" | sed '"'"'s/^S2-ACTIVATED: //'"'"' | sort | tail -n 1)"' r_markers
mutant m-deact-unchecked 'marker_stamp S2-DEACTIVATED; last_off="$MARKER_VAL"' 'last_off="$(printf '"'"'%s\n'"'"' "$trusted" | grep -oE "^S2-DEACTIVATED: $TS_RE\$" | sed '"'"'s/^S2-DEACTIVATED: //'"'"' | sort | tail -n 1)"' r_markers
mutant m-census-unchecked 'marker_count S2-EXIT-CENSUS '"'"'^S2-EXIT-CENSUS: https://github\.com/[^ ]+$'"'"'; census_marked="$MARKER_VAL"' 'census_marked="$(printf '"'"'%s\n'"'"' "$trusted" | grep -cE '"'"'^S2-EXIT-CENSUS: https://github\.com/[^ ]+$'"'"')"' r_markers
mutant m-stamp-status-any 'case "$st" in "0 0 0 0 0"|"0 1 0 0 0") : ;; *) fail_marker "$name" ;; esac' ':' r_markers
mutant m-stamp-rc1 '"0 0 0 0 0"|"0 1 0 0 0") : ;;' '"0 0 0 0 0") : ;;' r_pass r_deact
mutant m-count-status-any 'case "$st" in "0 0"|"0 1") [[ "$MARKER_VAL" =~ ^[0-9]+$ ]] || fail_marker "$name" ;; *) fail_marker "$name" ;; esac' ':' r_markers
mutant m-count-numeric ') [[ "$MARKER_VAL" =~ ^[0-9]+$ ]] || fail_marker "$name" ;;' ') : ;;' r_markers
mutant m-count-rc1 '"0 0"|"0 1") [[' '"0 0") [[' r_nomarker r_noperm_marker
mutant m-undeclared-tool 'NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"' 'NOW="${SOAK_NOW_EPOCH:-$(date -u +%s)}"; wc -l </dev/null >/dev/null' r_needcomplete
mutant m-need-short 'for need in gh jq base64 awk mktemp sort grep sed tr tail head date rm dirname; do' 'for need in gh jq base64 awk mktemp sort; do' r_needtools
mutant m-no-source-check 'if ! source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/trusted-verdict.sh" \
   ||' 'if ! { source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/trusted-verdict.sh"; true; } \
   ||' r_srcfail
mutant m-ts-loose 'T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'"'"'' 'T[0-9:]+Z?'"'"'' r_badts
mutant m-act-anchor-start 'grep -oE "^$name: $TS_RE\$"' 'grep -oE "$name: $TS_RE\$"' r_midact
mutant m-act-anchor-end 'grep -oE "^$name: $TS_RE\$"' 'grep -oE "^$name: $TS_RE"' r_midact
mutant m-census-dot ''"'"'^S2-EXIT-CENSUS: https://github\.com/[^ ]+$'"'"'' ''"'"'^S2-EXIT-CENSUS: https://github.com/[^ ]+$'"'"'' r_lookalike
mutant m-census-host ''"'"'^S2-EXIT-CENSUS: https://github\.com/[^ ]+$'"'"'' ''"'"'^S2-EXIT-CENSUS: https://[^ ]+$'"'"'' r_foreign
mutant m-pd-off 'if (( seen >= PD_MIN_SAMPLE && pd_bad * 5 > seen )); then' 'if false; then' r_pdbad6 r_pdbad_dark
mutant m-pd-bound 'pd_bad * 5 > seen' 'pd_bad * 5 >= seen' r_pdbad5
mutant m-pd-min 'seen >= PD_MIN_SAMPLE && ' '' r_pdbad_few
mutant m-voucher-status '.status == "completed" and .conclusion == "success") | .head_sha]' '.status == "completed") | .head_sha]' r_unmatched1
mutant m-deadline-edge '(( NOW - merged_epoch > DEADLINE_DAYS * 86400 ))' '(( NOW - merged_epoch >= DEADLINE_DAYS * 86400 ))' r_deadline_edge
mutant m-heavy-prefix 'test("^test-scripts( |$)")' 'test("^test-scripts")' r_pass
mutant m-heavy-exact 'test("^test-scripts( |$)")' 'test("^test-scripts$")' r_pass
# harness controls: the helper must be able to report a SURVIVOR and a CRASH, or its verdicts mean nothing
CTRL_OK=0
mutant_probe c-equivalent 'MAX_RUNS=100' 'MAX_RUNS=100;' r_pass
if [ "$MUT_LANDED" -eq 1 ] && [ "$MUT_CRASHED" -eq 0 ] && [ "$MUT_REDS" -eq 0 ]; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an equivalent mutant survives (no row red, no crash)"
else fail "harness control: the equivalent mutant was not reported as a survivor (landed=$MUT_LANDED crashed=$MUT_CRASHED reds=$MUT_REDS)"; fi
mutant_probe c-crash 'MAX_RUNS=100' 'MAX_RUNS=100; readonly X=(' r_pass
if [ "$MUT_LANDED" -eq 1 ] && [ "$MUT_CRASHED" -eq 1 ]; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that does not parse is flagged as crashed"
else fail "harness control: the crashing mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
# the stderr detector itself: a mutant that PARSES but fails at runtime must be flagged too
mutant_probe c-crash-rt 'MAX_RUNS=100' 'MAX_RUNS=100; no_such_command_zz' r_pass
if [ "$MUT_LANDED" -eq 1 ] && [ "$MUT_CRASHED" -eq 1 ] && bash -n "$TMP/mut-c-crash-rt.sh" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that parses but fails at runtime is flagged as crashed"
else fail "harness control: the runtime-crashing mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
# the mirrored tree itself: an IDENTITY copy must show zero reds over the full row set (else every mutant verdict is polluted), and a copy
# whose lib symlink is REMOVED must red at least one row (else the tree is not what resolves the lib)
PROBE_UNDER="$(mk_tree identity "$PROBE")"; core_rows_quiet "${ALL_ROWS[@]}"; PROBE_UNDER="$PROBE"
if [ "$MUT_REDS" -eq 0 ]; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an identity copy in the mirrored tree turns no row red"
else fail "harness control: the identity copy turned $MUT_REDS row(s) red (the tree is broken)"; fi
PROBE_UNDER="$(mk_tree nolink "$PROBE" nolink)"; core_rows_quiet "${ALL_ROWS[@]}"; PROBE_UNDER="$PROBE"
if [ "$MUT_REDS" -gt 0 ]; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a copy without the lib symlink turns $MUT_REDS row(s) red (the tree resolves the lib)"
else fail "harness control: a copy without the lib symlink turned no row red"; fi
# the VERDICT itself: an inert, a PARSE-crashing and an anchor-NOT-LANDED mutant fed through `mutant` must each be REPORTED as what it is (exactly one
# failure, nothing counted as caught, the right word in the report); counters are restored after. A verdict forced to `caught`
# (`if [ "$MUT_REDS" -gt 0 ]` -> `if true`) reports the inert mutant as caught and fails the first control. ctrl_verdict refuses an empty word, and the
# last control asserts it can REFUSE (a wrong word must fail it), so deleting the word check from the helper goes red.
ctrl_verdict() { # <name> <word the report must contain> <old> <new> <row ids...>
  local name="$1" word="$2"; shift 2
  [ -n "$word" ] || return 2
  local p0=$passes f0=$fails a0=$asserted n0=${#FAILURES[@]} r0=$MUT_RUN c0=$MUT_CAUGHT nfail ncaught
  mutant "$name" "$@" > "$TMP/ctrl-$name.out"
  nfail=$((fails - f0)); ncaught=$((MUT_CAUGHT - c0))
  passes=$p0; fails=$f0; asserted=$a0; FAILURES=("${FAILURES[@]:0:$n0}"); MUT_RUN=$r0; MUT_CAUGHT=$c0
  [ "$nfail" -eq 1 ] && [ "$ncaught" -eq 0 ] && grep -q -- "$word" "$TMP/ctrl-$name.out"
}
if ctrl_verdict c-inert 'went red' 'MAX_RUNS=100' 'MAX_RUNS=100;' r_pass; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: an inert mutant is reported as a SURVIVOR and makes the suite red"
else fail "harness control: an inert mutant was not reported as a survivor"; fi
if ctrl_verdict c-parse-verdict CRASHED 'MAX_RUNS=100' 'MAX_RUNS=100; readonly X=(' r_pass; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a PARSE-crashing mutant fed through mutant() is reported CRASHED and makes the suite red"
else fail "harness control: a parse-crashing mutant was not reported as CRASHED through mutant()"; fi
if ctrl_verdict c-nolanding 'did NOT land' 'ANCHOR_THAT_IS_NOT_IN_THE_PROBE_ZZ' 'x' r_pass; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant whose anchor does not land is reported NOT LANDED and makes the suite red"
else fail "harness control: a mutant with a missing anchor was not reported as NOT LANDED"; fi
if ! ctrl_verdict c-wrongword CRASHED 'MAX_RUNS=100' 'MAX_RUNS=100;' r_pass && ! ctrl_verdict c-emptyword '' 'MAX_RUNS=100' 'MAX_RUNS=100;' r_pass; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: the verdict helper REFUSES a report that lacks the expected word (and an empty word), so its word check cannot be deleted green"
else fail "harness control: the verdict helper accepted a report without the expected word"; fi
# CRASH_RE alternatives: one runtime-only mutant per alternative (each parses; only that alternative can flag it). `command not found` is the c-crash-rt control above.
mutant_probe c-crash-badsub 'MAX_RUNS=100' 'MAX_RUNS=100; _x=a; : "${_x@Z}"' r_pass
if [ "$MUT_LANDED" -eq 1 ] && [ "$MUT_CRASHED" -eq 1 ] && bash -n "$TMP/mut-c-crash-badsub.sh" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that dies on a bad substitution is flagged as crashed (CRASH_RE keeps that alternative)"
else fail "harness control: the bad-substitution mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
mutant_probe c-crash-unbound 'MAX_RUNS=100' 'MAX_RUNS=100; : "$UNSET_ZZ_SENTINEL"' r_pass
if [ "$MUT_LANDED" -eq 1 ] && [ "$MUT_CRASHED" -eq 1 ] && bash -n "$TMP/mut-c-crash-unbound.sh" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant that dies on an unbound variable is flagged as crashed (CRASH_RE keeps that alternative)"
else fail "harness control: the unbound-variable mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
mutant_probe c-crash-syntax 'MAX_RUNS=100' "MAX_RUNS=100; eval '('" r_pass
if [ "$MUT_LANDED" -eq 1 ] && [ "$MUT_CRASHED" -eq 1 ] && bash -n "$TMP/mut-c-crash-syntax.sh" 2>/dev/null; then CTRL_OK=$((CTRL_OK + 1)); pass "harness control: a mutant whose runtime eval dies on a syntax error is flagged as crashed (CRASH_RE keeps that alternative)"
else fail "harness control: the runtime syntax-error mutant was not flagged (landed=$MUT_LANDED crashed=$MUT_CRASHED)"; fi
if [ "$CTRL_OK" -ne 12 ]; then fail "harness controls: $CTRL_OK of 12 held"; fi
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ] && [ "$MUT_RUN" -ge 67 ]; then pass "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"; else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; floor 67)"; fi

# the request-shape mutants cannot reach a row's EXIT CODE (the fake gh answers any well-formed jobs path), so they are
# pinned by the requests.log assertion above: drop each parameter from a copy and confirm the assertion text no longer holds
_shape_bad=""
for pair in "jobs?per_page=100&filter=latest|jobs?per_page=100" "state=open&per_page=100|state=all&per_page=100" "oldest_epoch - 86400|oldest_epoch + 864000"; do
  old="${pair%%|*}"; new="${pair#*|}"
  python3 - "$PROBE" "$TMP/shape-src.sh" "$old" "$new" <<'PY' || { _shape_bad="$_shape_bad nolanding($old)"; continue; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$TMP/shape-src.sh"; shape_probe="$(mk_tree shape "$TMP/shape-src.sh")"
  build_fx "$TMP/shp" 10 15 510 2568
  # the shimmed gh rejects the mutated endpoint shapes (exit 64), so the probe cannot read: CANNOT ESTABLISH, never a pass
  out="$(env FX="$TMP/shp" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" SOAK_ADR_FILE="$TMP/shp/ADR-276-fixture.md" SOAK_TEST_ALL="$TMP/shp/test-all.sh" bash "$shape_probe" 2>&1)"; rc=$?
  case "$old" in
    oldest_epoch*) # the fake gh does no server-side filtering: the window bound shows only in the request it was sent
      grep -cF "event=merge_group&per_page=100&created=%3E$_bound" "$TMP/shp/requests.log" >/dev/null && _shape_bad="$_shape_bad window-unchanged($new)" ;;
    *) [ "$rc" != 0 ] || _shape_bad="$_shape_bad passes($new)" ;;
  esac
done
if [ -z "$_shape_bad" ]; then pass "request-shape mutants (jobs filter dropped, tracker state widened, merge_group window moved) are refused by the fake gh, never a pass"; else fail "request-shape mutants survived:$_shape_bad"; fi

# harness row: a probe that always exits 0 must be refused by the named rows (the rows can fail)
printf '#!/usr/bin/env bash\necho PASS\nexit 0\n' > "$TMP/always-pass.sh"; chmod +x "$TMP/always-pass.sh"
PROBE_UNDER="$TMP/always-pass.sh"; core_rows_quiet "${ALL_ROWS[@]}"; PROBE_UNDER="$PROBE"
if [ "$MUT_REDS" -ge 76 ]; then pass "HARNESS: an always-PASS probe turns $MUT_REDS rows red"; else fail "HARNESS: an always-PASS probe turned only $MUT_REDS rows red"; fi

printf 'ci-push-dedupe-soak-9512: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
# DELIBERATELY NOT ROUTED THROUGH fail(): compares against a literal and exits directly.
_total=$((passes + fails))
_FLOOR=176
if [ "$_total" -lt "$_FLOOR" ]; then
  printf '[FATAL] assertion floor: executed %d < %d\n' "$_total" "$_FLOOR" >&2
  exit 1
fi
exit $(( ${#FAILURES[@]} > 0 ))
