#!/usr/bin/env bash
# ci-draft-light-soak-9728.test.sh — Guard 2 for #9728 (ADR-276 S3): drives the soak probe through a fake `gh`
# and a stub verdict resolver, pins its exit-code contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH,
# 78 xtrace refusal), with mutation rows against mutated COPIES of the probe. An exit-code contract nothing
# drives is a comment.
#
# The clock is injected (SOAK_NOW_EPOCH) and the resolver is a stub (CI_HEAD_VERDICT_CMD) that prints the exact
# `SOLEUR_CI_HEAD_VERDICT state=... pr=... sha=... run=... reason=...` line, so no row sleeps and none depends on
# the wall clock, the live repo or the real resolver. Fixtures are synthesized (shas are `L###`/`F###`/`H###`,
# PR numbers are 6xx-8xx, the tracker is the real #9728 only because the probe names it); nothing is written
# outside a mktemp dir.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
export TZ=UTC
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/ci-draft-light-soak-9728.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/dls-soak.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; rm -rf "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
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
MERGED_EPOCH=$((NOW_EPOCH - 12 * 86400))
isoof() { printf -v "$2" '%(%Y-%m-%dT%H:%M:%SZ)T' "$1"; }   # isoof <epoch> <varname>

# --- the stub resolver: prints what ci-head-verdict.sh `verdict <pr>` prints (plan Phase 7 item 1) ----------------------
cat > "$TMP/verdict-stub.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "verdict" ] || exit 64
[ -f "$FX/verdict-fail-$2" ] && { echo "resolver: HTTP 500" >&2; exit 1; }
[ -f "$FX/verdict-$2.txt" ] || exit 65
cat "$FX/verdict-$2.txt"
STUB

# --- the job templates: one static jobs listing per run kind (a run's kind is read from $FX/kind-<run id>) -----------------
mkdir -p "$TMP/tpl" "$TMP/bin"
mk_jobs() { # <file> <gated conclusion> <test conclusion|-> [extra jq jobs...]
  local f="$1" g="$2" t="$3"; shift 3
  jq -n --arg g "$g" --arg t "$t" '{jobs: ([
      {name:"detect-changes",conclusion:"success"}, {name:"draft-light",conclusion:"success"},
      {name:"test-webplat (1/2)",conclusion:$g}, {name:"test-webplat (2/2)",conclusion:$g},
      {name:"test-scripts (1/8)",conclusion:$g}, {name:"test-scripts (2/8)",conclusion:$g},
      {name:"test-scripts-heavy",conclusion:$g}, {name:"shard-totality-mutations",conclusion:$g},
      {name:"test-bun",conclusion:"success"}, {name:"lint-webplat",conclusion:"success"}]
      + (if $t == "-" then [] else [{name:"test",conclusion:$t}] end))}' > "$f"
}
mk_jobs "$TMP/tpl/jobs-full.json" success success
mk_jobs "$TMP/tpl/jobs-fullred.json" success failure
mk_jobs "$TMP/tpl/jobs-light.json" skipped failure
mk_jobs "$TMP/tpl/jobs-lightok.json" skipped success      # a light run whose `test` went green: Option R broken
mk_jobs "$TMP/tpl/jobs-lightnotest.json" skipped -        # a light run with no `test` row at all
# decoys that are NOT light: one gated job ran, one family absent, the `test-scripts` family absent with only -heavy skipped
jq '.jobs |= map(if .name == "test-scripts (2/8)" then .conclusion = "success" else . end)' "$TMP/tpl/jobs-light.json" > "$TMP/tpl/jobs-mixed.json"
jq '.jobs |= map(if .name == "test-scripts (1/8)" or .name == "test-scripts (2/8)" then .conclusion = "success" else . end)' "$TMP/tpl/jobs-light.json" > "$TMP/tpl/jobs-heavyonly.json"
jq '.jobs |= map(select(.name != "shard-totality-mutations"))' "$TMP/tpl/jobs-light.json" > "$TMP/tpl/jobs-nofam.json"
jq '.jobs |= map(select(.name | startswith("test-scripts (") | not))' "$TMP/tpl/jobs-light.json" > "$TMP/tpl/jobs-noscripts.json"

# --- the fake gh: answers the endpoints the probe reads from $FX/*.json, applying --jq with real jq ---------------------------
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = "api" ] || exit 64
shift
paginate=0; jqx=""; ep=""; gsha=""
while (( $# )); do
  case "$1" in
    --paginate) paginate=1 ;;
    --jq) jqx="$2"; shift ;;
    -f|-F) case "$2" in sha=*) gsha="${2#sha=}" ;; esac; shift ;;
    -*) exit 64 ;;
    *) ep="$1" ;;
  esac
  shift
done
printf '%s\n' "$ep${gsha:+ sha=$gsha}" >> "$FX/requests.log"
emit() { [ -f "$1" ] || exit 1; if [ -n "$jqx" ]; then jq -r "$jqx" "$1"; else cat "$1"; fi; exit 0; }
case "$ep" in
  repos/*/pulls/9885) [ -f "$FX/fail-pr" ] && { echo "gh: HTTP 500" >&2; exit 1; }; emit "$FX/pr.json" ;;
  repos/*/pulls\?state=open\&per_page=100) [ -f "$FX/fail-open" ] && { echo "gh: HTTP 500" >&2; exit 1; }; emit "$FX/open.json" ;;
  repos/*/pulls/[0-9]*) [ -f "$FX/fail-mgpr" ] && { echo "gh: HTTP 500" >&2; exit 1; }; emit "$FX/prn-${ep##*/}.json" ;;
  repos/*/issues/9728/comments\?per_page=100)
    [ -f "$FX/fail-comments" ] && { echo "gh: HTTP 403 Resource not accessible" >&2; exit 1; }
    (( paginate )) || exit 64   # past 100 comments only a paginated read sees a later marker
    for f in "$FX/comments-1.json" "$FX/comments-2.json"; do [ -f "$f" ] && { if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi; }; done
    exit 0 ;;
  repos/*/actions/workflows/ci.yml/runs\?event=pull_request\&status=completed*) [ -f "$FX/fail-runs" ] && { echo "gh: HTTP 500" >&2; exit 1; }; emit "$FX/runs.json" ;;
  repos/*/actions/workflows/ci.yml/runs\?event=pull_request\&head_sha=*) [ -f "$FX/fail-headrun" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    s="${ep#*head_sha=}"; emit "$FX/headrun-${s%%&*}.json" ;;
  repos/*/actions/workflows/ci.yml/runs\?event=merge_group*) [ -f "$FX/fail-mg" ] && { echo "gh: HTTP 500" >&2; exit 1; }; emit "$FX/mg.json" ;;
  repos/*/actions/runs/*/jobs\?per_page=100\&filter=latest)
    [ -f "$FX/fail-jobs" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    r="${ep#*runs/}"; r="${r%%/*}"; [ -f "$FX/kind-$r" ] || exit 1; emit "$TPL/jobs-$(cat "$FX/kind-$r").json" ;;
  graphql) [ -f "$FX/fail-gql" ] && { echo "gh: HTTP 502" >&2; exit 1; }; emit "$FX/gql-$gsha.json" ;;
  *) exit 64 ;;
esac
FAKE
chmod +x "$TMP/bin/gh"

# build_fx <dir> <light runs> <full runs> [key=value ...]    (newest runs first in the fake listing; every run is a completed PR run)
#   actdays=D  S3-ACTIVATED D days before the injected now (default 8, by an OWNER); noact: none; untrustedact: by NONE
#   deact: a later S3-DEACTIVATED (act+30h)   page2: it is on comments page 2   twoact: an older ACTIVATED too (act-8d)
#   crlf: markers end in CRLF   badts: ACTIVATED without the Z   midact: ACTIVATED mid-line/with trailing text
#   confirmed=url|quote|none|late|untrusted|placeholder|bare|mid   the S3-CONFIRMED comment (default url, before the activation)
#   marker=yes|none|mid|untrusted|nonurl|placeholder|collab|contrib|lookalike|foreign   the S3-EXIT-CENSUS comment
#   merged=<epoch>  the S3 PR merge time (default now-12d)   unmerged: the PR is not merged
#   earlylight=K  K light runs BEFORE the activation   rerun=K  K more runs on the first K light shas
#   extra=<k>[,<k>...]  one more run per kind, newest in the listing: lightsuccess lightnotest lightready lightconverted
#     lightbeforeready lightnever lightconvfirst lightnopr lightmultipr tltrunc mixed heavyonly noscripts nofam cancelskip lightafteroff
#   oldlast=<k>  one run of that kind OLDER than every other (outside a short sample)   pad=K  K extra full runs between
#   stalled=N[,N..]  those open PRs get a stalled verdict   vfail|vgarbage|vunknown|vmismatch|vnoise0: the resolver misbehaves on PR 701
#   noopen: no open PRs   mgbad: PR 803's newest pull_request run is light   mgolder: PR 804 has an older light run only
#   mgnonqueue: a merge_group run on a non-queue branch   mgn=K  K merge_group runs (default 6)   mgbadat=I  mgbad at queue position I
#   conf2: a second, LATER S3-CONFIRMED   between: a light run between two activations (with twoact)
#   failX: the X read fails (pr|open|comments|runs|jobs|gql|mg|mgpr|headrun)
build_fx() {
  local fx="$1" nl="$2" nf="$3"; shift 3
  assert_fixture_dir "$fx"; rm -rf "$fx"; mkdir -p "$fx"
  local actdays=8 noact=0 untrustedact=0 deact=0 page2=0 twoact=0 crlf=0 badts=0 midact=0 confirmed=url marker=yes
  local merged="$MERGED_EPOCH" unmerged=0 earlylight=0 rerun=0 extra="" oldlast="" pad=0 stalled="" vmode="" noopen=0
  local mgbad=0 mgolder=0 mgnonqueue=0 mgn=6 mgbadat=3 conf2=0 between=0 kv
  for kv in "$@"; do
    case "$kv" in
      actdays=*) actdays="${kv#*=}" ;; noact) noact=1 ;; untrustedact) untrustedact=1 ;; deact) deact=1 ;; page2) page2=1 ;;
      twoact) twoact=1 ;; crlf) crlf=1 ;; badts) badts=1 ;; midact) midact=1 ;; confirmed=*) confirmed="${kv#*=}" ;;
      marker=*) marker="${kv#*=}" ;; merged=*) merged="${kv#*=}" ;; unmerged) unmerged=1 ;; earlylight=*) earlylight="${kv#*=}" ;;
      rerun=*) rerun="${kv#*=}" ;; extra=*) extra="${kv#*=}" ;; oldlast=*) oldlast="${kv#*=}" ;; pad=*) pad="${kv#*=}" ;;
      stalled=*) stalled="${kv#*=}" ;; vfail|vgarbage|vunknown|vmismatch|vnoise0) vmode="$kv" ;; noopen) noopen=1 ;;
      conf2) conf2=1 ;; between) between=1 ;; mgbad) mgbad=1 ;; mgolder) mgolder=1 ;; mgnonqueue) mgnonqueue=1 ;; mgn=*) mgn="${kv#*=}" ;; mgbadat=*) mgbadat="${kv#*=}" ;;
      fail*) : > "$fx/fail-${kv#fail}" ;;
    esac
  done
  local act_epoch=$((NOW_EPOCH - actdays * 86400)) act_iso off_epoch=$((NOW_EPOCH - actdays * 86400 + 30 * 3600)) t t1 t2
  isoof "$act_epoch" act_iso
  local first_on_epoch="$act_epoch"; (( twoact )) && first_on_epoch=$((act_epoch - 8 * 86400))
  if (( unmerged )); then printf '{"merged_at":null}\n' > "$fx/pr.json"
  else isoof "$merged" t; printf '{"merged_at":"%s"}\n' "$t" > "$fx/pr.json"; fi

  # ---- the sampled runs ----
  : > "$fx/runs.tsv"
  add_run() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$fx/runs.tsv"; printf '%s' "$6" > "$fx/kind-$2"; }   # epoch id sha branch conclusion kind
  gql() { # <sha> <pr number> <branch> <variant> <run created epoch>
    local sha="$1" n="$2" br="$3" var="$4" c="$5" nodes="" draft=true more=false pre=""
    local rdy='{"__typename":"ReadyForReviewEvent","createdAt":"%s"}' cnv='{"__typename":"ConvertToDraftEvent","createdAt":"%s"}'
    case "$var" in
      draftopen) : ;;
      beforeready) isoof $((c + 600)) t; nodes="$(printf "$rdy" "$t")"; draft=false ;;
      ready)       isoof $((c - 600)) t; nodes="$(printf "$rdy" "$t")"; draft=false ;;
      converted)   isoof $((c - 7200)) t1; isoof $((c - 3600)) t2; nodes="$(printf "$rdy" "$t1"),$(printf "$cnv" "$t2")"; draft=true ;;
      never)       draft=false ;;
      convfirst)   isoof $((c + 600)) t; nodes="$(printf "$cnv" "$t")"; draft=true ;;
      trunc)       isoof $((c - 600)) t; nodes="$(printf "$rdy" "$t")"; draft=false; more=true ;;
      nopr)        printf '{"data":{"repository":{"object":{"associatedPullRequests":{"nodes":[]}}}}}\n' > "$fx/gql-$sha.json"; return ;;
      multipr)     isoof $((c - 600)) t; pre="{\"number\":$((n + 5000)),\"isDraft\":false,\"headRefName\":\"other-branch\",\"timelineItems\":{\"pageInfo\":{\"hasNextPage\":false},\"nodes\":[$(printf "$rdy" "$t")]}}," ;;
    esac
    printf '{"data":{"repository":{"object":{"associatedPullRequests":{"nodes":[%s{"number":%s,"isDraft":%s,"headRefName":"%s","timelineItems":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]}}]}}}}}\n' \
      "$pre" "$n" "$draft" "$br" "$more" "$nodes" > "$fx/gql-$sha.json"
  }
  local i sha
  for ((i = 1; i <= nl; i++)); do
    sha="L$(printf '%03d' "$i")"; add_run $((act_epoch + 3600 * i)) $((2000 + i)) "$sha" "br-$sha" failure light
    gql "$sha" $((600 + i)) "br-$sha" draftopen $((act_epoch + 3600 * i))
  done
  for ((i = 1; i <= rerun; i++)); do
    sha="L$(printf '%03d' "$i")"; add_run $((act_epoch + 3600 * i + 900)) $((2500 + i)) "$sha" "br-$sha" failure light
  done
  for ((i = 1; i <= earlylight; i++)); do
    sha="E$(printf '%03d' "$i")"; add_run $((act_epoch - 3600 * i)) $((2600 + i)) "$sha" "br-$sha" failure light
    gql "$sha" $((700 + i)) "br-$sha" draftopen $((act_epoch - 3600 * i))
  done
  for ((i = 1; i <= nf; i++)); do
    if (( i % 3 == 0 )); then add_run $((act_epoch + 3600 * i + 1800)) $((3000 + i)) "F$(printf '%03d' "$i")" "br-F$i" failure fullred
    else add_run $((act_epoch + 3600 * i + 1800)) $((3000 + i)) "F$(printf '%03d' "$i")" "br-F$i" success full; fi
  done
  for ((i = 1; i <= pad; i++)); do add_run $((act_epoch - 600 - 3600 * i)) $((3500 + i)) "P$(printf '%03d' "$i")" "br-P$i" success full; done
  special() { # <kind name> <epoch> <id>
    local k="$1" c="$2" id="$3" sha="S$3" tk=light conc=failure gv=draftopen
    case "$k" in
      lightsuccess) tk=lightok; conc=success ;; lightnotest) tk=lightnotest ;; lightready) gv=ready ;; lightconverted) gv=converted ;;
      lightbeforeready) gv=beforeready ;; lightnever) gv=never ;; lightconvfirst) gv=convfirst ;; lightnopr) gv=nopr ;;
      lightmultipr) gv=multipr ;; tltrunc) gv=trunc ;; mixed|heavyonly|noscripts|nofam) tk="$k" ;;
      cancelskip) conc=cancelled; gv=ready ;; lightafteroff) : ;;
    esac
    add_run "$c" "$id" "$sha" "br-$sha" "$conc" "$tk"
    gql "$sha" "$((id + 100))" "br-$sha" "$gv" "$c"
  }
  if (( between )); then   # a light run between the first and the latest activation: legitimate
    add_run $((act_epoch - 2 * 86400)) 4800 SB01 br-SB01 failure light; gql SB01 4801 br-SB01 draftopen $((act_epoch - 2 * 86400))
  fi
  local k n=0
  for k in ${extra//,/ }; do n=$((n + 1)); special "$k" $((act_epoch + 3600 * 30 + 60 * n)) $((4000 + n)); done
  [ -n "$oldlast" ] && special "$oldlast" $((act_epoch - 10 * 86400)) 4900
  sort -t$'\t' -k1,1nr "$fx/runs.tsv" | jq -R -s '{workflow_runs: [split("\n")[] | select(length > 0) | split("\t")
      | {id: (.[1] | tonumber), head_sha: .[2], head_branch: .[3], created_at: (.[0] | tonumber | todate), conclusion: .[4], status: "completed", event: "pull_request"}]}' > "$fx/runs.json"

  # ---- the open PRs and their verdict lines (the stub resolver prints these) ----
  local list="" st
  vline() { printf 'SOLEUR_CI_HEAD_VERDICT state=%s pr=%s sha=H%s run=none reason=fixture\n' "$2" "$1" "$1"; }
  if (( ! noopen )); then
    local -a prs=(701:n/a 702:full-decided 703:pending-full 704:no-run 705:awaiting-approval)
    local s
    for s in ${stalled//,/ }; do prs+=("$s:stalled"); done
    for s in "${prs[@]}"; do
      vline "${s%%:*}" "${s#*:}" > "$fx/verdict-${s%%:*}.txt"
      list="$list{\"number\":${s%%:*},\"draft\":false},"
    done
    # a DRAFT PR whose stub line says stalled: the probe must never consult it
    vline 706 stalled > "$fx/verdict-706.txt"; list="$list{\"number\":706,\"draft\":true},"
  fi
  printf '[%s]\n' "${list%,}" > "$fx/open.json"
  case "$vmode" in
    vfail) : > "$fx/verdict-fail-701" ;;
    vgarbage) printf 'something else entirely\n' > "$fx/verdict-701.txt" ;;
    vunknown) printf 'SOLEUR_CI_HEAD_VERDICT state=weird pr=701 sha=H701 run=none reason=fixture\n' > "$fx/verdict-701.txt" ;;
    vmismatch) printf 'SOLEUR_CI_HEAD_VERDICT state=n/a pr=999 sha=H701 run=none reason=fixture\n' > "$fx/verdict-701.txt" ;;
    vnoise0) { printf 'resolver: reading timeline\n'; vline 701 n/a; printf 'resolver: done\n'; } > "$fx/verdict-701.txt" ;;
  esac

  # ---- merge_group runs: queue branch names carry the PR number; each PR's head newest pull_request run is full unless mgbad ----
  local mg="" q h
  for ((q = 1; q <= mgn; q++)); do
    h="H$((800 + q))"
    mg="$mg{\"id\":$((7000 + q)),\"head_branch\":\"gh-readonly-queue/main/pr-$((800 + q))-0123456789abcdef0123456789abcdef01234567\"},"
    printf '{"head":{"sha":"%s"}}\n' "$h" > "$fx/prn-$((800 + q)).json"
    local bad=0; (( mgbad && q == mgbadat )) && bad=1
    if (( bad )); then
      printf '{"workflow_runs":[{"id":%d}]}\n' $((9100 + q)) > "$fx/headrun-$h.json"; printf light > "$fx/kind-$((9100 + q))"
    elif (( mgolder && q == 4 )); then
      printf '{"workflow_runs":[{"id":%d},{"id":%d}]}\n' $((9100 + q)) $((9200 + q)) > "$fx/headrun-$h.json"; printf full > "$fx/kind-$((9100 + q))"; printf light > "$fx/kind-$((9200 + q))"
    else
      printf '{"workflow_runs":[{"id":%d}]}\n' $((9100 + q)) > "$fx/headrun-$h.json"; printf full > "$fx/kind-$((9100 + q))"
    fi
  done
  (( mgnonqueue )) && mg="$mg{\"id\":7999,\"head_branch\":\"feature/pr-899-deadbeef\"},"
  printf '{"workflow_runs":[%s]}\n' "${mg%,}" > "$fx/mg.json"

  # ---- the tracker's comments: [{body, author_association, created_at}] ----
  local cr=; (( crlf )) && cr=$'\r'
  local -a cm=() cm2=()
  addc() { # <array name> <association> <created epoch> <body>
    local -n arr="$1"; local iso; isoof "$3" iso
    arr+=("$(jq -nc --arg b "$4" --arg a "$2" --arg t "$iso" '{body:$b,author_association:$a,created_at:$t}')")
  }
  addc cm OWNER $((act_epoch - 90000)) "noted"
  local ts_on; isoof "$act_epoch" ts_on
  if (( ! noact )); then
    local assoc=OWNER; (( untrustedact )) && assoc=NONE
    if (( badts )); then addc cm OWNER "$act_epoch" "S3-ACTIVATED: ${ts_on%Z}"
    elif (( midact )); then addc cm OWNER "$act_epoch" "see S3-ACTIVATED: $ts_on"$'\n'"S3-ACTIVATED: $ts_on and then some"
    else addc cm "$assoc" "$act_epoch" "activated${cr}"$'\n'"S3-ACTIVATED: $ts_on${cr}"; fi
    if (( twoact )); then local ts_old; isoof "$first_on_epoch" ts_old; addc cm OWNER "$first_on_epoch" "S3-ACTIVATED: $ts_old"; fi
  fi
  if (( deact )); then
    local ts_off; isoof "$off_epoch" ts_off
    if (( page2 )); then addc cm2 OWNER "$off_epoch" "S3-DEACTIVATED: $ts_off"; else addc cm OWNER "$off_epoch" "S3-DEACTIVATED: $ts_off"; fi
  fi
  local conf_at=$((first_on_epoch - 3600)); (( noact )) && conf_at=$((NOW_EPOCH - 5 * 86400))
  case "$confirmed" in
    url)         addc cm MEMBER "$conf_at" "CTO review, as posted:${cr}"$'\n'"S3-CONFIRMED: https://github.com/jikig-ai/soleur/pull/9876#issuecomment-1${cr}" ;;
    quote)       addc cm OWNER "$conf_at" "S3-CONFIRMED: \"activation proceeds without the CTO comment\"" ;;
    late)        addc cm OWNER $((first_on_epoch + 3600)) "S3-CONFIRMED: https://github.com/jikig-ai/soleur/pull/9876#issuecomment-1" ;;
    untrusted)   addc cm NONE "$conf_at" "S3-CONFIRMED: https://github.com/jikig-ai/soleur/pull/9876#issuecomment-1" ;;
    placeholder) addc cm OWNER "$conf_at" "S3-CONFIRMED: <url or quoted statement>" ;;
    bare)        addc cm OWNER "$conf_at" "S3-CONFIRMED: ok" ;;
    mid)         addc cm OWNER "$conf_at" "I will post S3-CONFIRMED: https://github.com/jikig-ai/soleur/pull/9876" ;;
  esac
  (( conf2 )) && addc cm OWNER $((first_on_epoch + 7200)) "S3-CONFIRMED: https://github.com/jikig-ai/soleur/pull/9876#issuecomment-9"
  case "$marker" in
    yes)         addc cm MEMBER $((NOW_EPOCH - 3600)) "exit census${cr}"$'\n'"S3-EXIT-CENSUS: https://github.com/jikig-ai/soleur/issues/9728#issuecomment-2${cr}" ;;
    lookalike)   addc cm OWNER $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: https://githubXcom/x/y" ;;
    foreign)     addc cm OWNER $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: https://example.com/x/y" ;;
    contrib)     addc cm CONTRIBUTOR $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: https://github.com/x/y" ;;
    collab)      addc cm COLLABORATOR $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: https://github.com/x/y" ;;
    mid)         addc cm OWNER $((NOW_EPOCH - 3600)) "we will post an S3-EXIT-CENSUS: https://github.com/x/y" ;;
    untrusted)   addc cm NONE $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: https://github.com/x/y" ;;
    nonurl)      addc cm OWNER $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: see-my-notes" ;;
    placeholder) addc cm OWNER $((NOW_EPOCH - 3600)) "S3-EXIT-CENSUS: <url>" ;;
  esac
  printf '[%s]\n' "$(IFS=,; printf '%s' "${cm[*]}")" > "$fx/comments-1.json"
  (( page2 )) && printf '[%s]\n' "$(IFS=,; printf '%s' "${cm2[*]}")" > "$fx/comments-2.json"
  return 0
}

# expect <label> <want-rc> <want-text> <fx> [env...]  — runs $PROBE_UNDER (default the live probe)
PROBE_UNDER="$PROBE"
expect() {
  local label="$1" want="$2" text="$3" fx="$4"; shift 4
  local out rc
  out="$(env FX="$fx" TPL="$TMP/tpl" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" CI_HEAD_VERDICT_CMD="$TMP/verdict-stub.sh" "$@" bash "$PROBE_UNDER" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" && "$out" == *"$text"* ]]; then pass "$label (rc=$rc)"; else fail "$label: want rc=$want containing '$text', got rc=$rc: $(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}
# the same run, returning the output (for assertions on the request log or the info line)
LAST_OUT=""
expect_out() { LAST_OUT="$(env FX="$1" TPL="$TMP/tpl" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" CI_HEAD_VERDICT_CMD="$TMP/verdict-stub.sh" bash "$PROBE_UNDER" 2>&1)"; }

# A lean PASS fixture is 20 light pushes + 6 full runs, active 8 days, confirmed before the activation, census attached.
# --- baseline and the info line ------------------------------------------------------------------------------------------
r_pass()      { build_fx "$TMP/c1" 20 6;                                   expect "PASS: 20 distinct draft pushes light over 8 days, confirmed, census attached, a draft PR with a stalled stub line ignored" 0 "PASS" "$TMP/c1"; }
r_info()      { build_fx "$TMP/c2" 20 6;                                   expect "the info line reports the counts" 0 "light_pushes=20 " "$TMP/c2"; }
# --- (a) STALL --------------------------------------------------------------------------------------------------------------
r_stall()     { build_fx "$TMP/a1" 20 6 stalled=707;                       expect "FAIL: an open ready PR whose verdict is stalled is named" 1 "#707" "$TMP/a1"; }
r_stall2()    { build_fx "$TMP/a2" 20 6 stalled=707,708;                   expect "FAIL: two stalled PRs are both named" 1 "#707 #708" "$TMP/a2"; }
r_stall_dark(){ build_fx "$TMP/a3" 0 6 noact stalled=707 merged=$((NOW_EPOCH - 3600)); expect "FAIL: a stalled PR is reported while still dark (no activation, merged an hour ago)" 1 "#707" "$TMP/a3"; }
r_stall_prec(){ build_fx "$TMP/a4" 5 6 actdays=2 stalled=707;              expect "FAIL takes precedence over NOT YET (a stalled PR with too few days and pushes)" 1 "#707" "$TMP/a4"; }
r_vfail()     { build_fx "$TMP/a5" 20 6 vfail;                             expect "CANNOT ESTABLISH: the resolver exits non-zero" 3 "CANNOT ESTABLISH" "$TMP/a5"; }
r_vgarbage()  { build_fx "$TMP/a6" 20 6 vgarbage;                          expect "CANNOT ESTABLISH: the resolver prints no verdict line" 3 "CANNOT ESTABLISH" "$TMP/a6"; }
r_vunknown()  { build_fx "$TMP/a7" 20 6 vunknown;                          expect "CANNOT ESTABLISH: a state outside the closed set is never read as healthy" 3 "CANNOT ESTABLISH" "$TMP/a7"; }
r_vmismatch() { build_fx "$TMP/a8" 20 6 vmismatch;                         expect "CANNOT ESTABLISH: the verdict line names a different PR" 3 "CANNOT ESTABLISH" "$TMP/a8"; }
r_vnoise()    { build_fx "$TMP/a9" 20 6 vnoise0;                           expect "PASS: resolver chatter around the verdict line is ignored" 0 "PASS" "$TMP/a9"; }
r_noopen()    { build_fx "$TMP/a10" 20 6 noopen;                           expect "PASS: no open PRs means no stall" 0 "PASS" "$TMP/a10"; }
r_openfail()  { build_fx "$TMP/a11" 20 6 failopen;                         expect "CANNOT ESTABLISH: the open PR listing fails" 3 "CANNOT ESTABLISH" "$TMP/a11"; }
# --- (b) DARK DEADLINE -------------------------------------------------------------------------------------------------------
r_deadline()  { build_fx "$TMP/b1" 0 6 noact merged=$((NOW_EPOCH - 86400 - 1)); expect "FAIL: more than 1 day after the merge with no S3-ACTIVATED" 1 "no S3-ACTIVATED" "$TMP/b1"; }
r_deadline_edge(){ build_fx "$TMP/b2" 0 6 noact merged=$((NOW_EPOCH - 86400)); expect "NOT YET: exactly 1 day after the merge is not past the deadline" 2 "not activated" "$TMP/b2"; }
r_dark_young(){ build_fx "$TMP/b3" 0 6 noact merged=$((NOW_EPOCH - 3600));  expect "NOT YET: merged an hour ago, nothing activated" 2 "not activated" "$TMP/b3"; }
r_untrusted_act(){ build_fx "$TMP/b4" 0 6 untrustedact;                    expect "FAIL: an ACTIVATED comment by a NONE-association commenter does not stop the deadline" 1 "no S3-ACTIVATED" "$TMP/b4"; }
r_unmerged()  { build_fx "$TMP/b5" 20 6 unmerged;                          expect "NOT YET: the S3 PR is not merged" 2 "not merged" "$TMP/b5"; }
r_deact()     { build_fx "$TMP/b6" 20 6 deact;                             expect "NOT YET: a later S3-DEACTIVATED ends the activation (no deadline once an activation was recorded)" 2 "deactivated" "$TMP/b6"; }
r_page2()     { build_fx "$TMP/b7" 20 6 deact page2;                       expect "NOT YET: a DEACTIVATED marker on comments page 2 is read" 2 "deactivated" "$TMP/b7"; }
r_badts()     { build_fx "$TMP/b8" 0 6 badts merged=$((NOW_EPOCH - 3600)); expect "NOT YET: an ACTIVATED timestamp without the Z is not a marker" 2 "not activated" "$TMP/b8"; }
r_midact()    { build_fx "$TMP/b9" 0 6 midact merged=$((NOW_EPOCH - 3600)); expect "NOT YET: ACTIVATED mid-line or with trailing text is not a marker" 2 "not activated" "$TMP/b9"; }
r_crlf()      { build_fx "$TMP/b10" 20 6 crlf;                             expect "PASS: CRLF comment lines (browser-posted) still parse" 0 "PASS" "$TMP/b10"; }
r_twoact()    { build_fx "$TMP/b11" 20 6 twoact;                           expect "the LATEST of two ACTIVATED markers sets the age" 0 "age_days=8 " "$TMP/b11"; }
# --- (c) DETECTIVE ACTIVATION CHECK ------------------------------------------------------------------------------------------
r_light_noact(){ build_fx "$TMP/c3" 3 6 noact;                             expect "FAIL: light runs with no activation on record" 1 "no activation on record" "$TMP/c3"; }
r_light_untrusted(){ build_fx "$TMP/c4" 3 6 untrustedact;                  expect "FAIL: light runs while only an untrusted activation exists" 1 "no activation on record" "$TMP/c4"; }
r_light_early(){ build_fx "$TMP/c5" 20 6 earlylight=2;                     expect "FAIL: light runs created BEFORE the recorded activation" 1 "predate" "$TMP/c5"; }
r_noconf()    { build_fx "$TMP/c6" 20 6 confirmed=none;                    expect "FAIL: light runs with no S3-CONFIRMED comment" 1 "S3-CONFIRMED" "$TMP/c6"; }
r_conf_untrusted(){ build_fx "$TMP/c7" 20 6 confirmed=untrusted;           expect "FAIL: an S3-CONFIRMED by a NONE-association commenter does not count" 1 "S3-CONFIRMED" "$TMP/c7"; }
r_conf_placeholder(){ build_fx "$TMP/c8" 20 6 confirmed=placeholder;       expect "FAIL: the literal placeholder S3-CONFIRMED: <url or quoted statement> does not count" 1 "S3-CONFIRMED" "$TMP/c8"; }
r_conf_bare() { build_fx "$TMP/c9" 20 6 confirmed=bare;                    expect "FAIL: S3-CONFIRMED with neither a github URL nor a quoted statement does not count" 1 "S3-CONFIRMED" "$TMP/c9"; }
r_conf_mid()  { build_fx "$TMP/c10" 20 6 confirmed=mid;                    expect "FAIL: S3-CONFIRMED mid-line does not count" 1 "S3-CONFIRMED" "$TMP/c10"; }
r_conf_late() { build_fx "$TMP/c11" 20 6 confirmed=late;                   expect "FAIL: S3-CONFIRMED posted AFTER the activation (order is the control)" 1 "after the activation" "$TMP/c11"; }
r_conf_quote(){ build_fx "$TMP/c12" 20 6 confirmed=quote;                  expect "PASS: a quoted operator statement is a valid S3-CONFIRMED" 0 "PASS" "$TMP/c12"; }
r_conf_two()  { build_fx "$TMP/c19" 20 6 conf2;                            expect "PASS: the EARLIEST of two S3-CONFIRMED comments is the one compared with the activation" 0 "PASS" "$TMP/c19"; }
r_between()   { build_fx "$TMP/c20" 20 6 twoact between;                   expect "PASS: a light run between the first and the latest activation is legitimate (the FIRST activation bounds 'early')" 0 "PASS" "$TMP/c20"; }
r_nolight_noconf(){ build_fx "$TMP/c13" 0 6 confirmed=none;                expect "NOT YET: no light run observed, so a missing S3-CONFIRMED alone is not a FAIL (detective, light-run triggered)" 2 "0 distinct" "$TMP/c13"; }
r_decoy_mixed(){ build_fx "$TMP/c14" 0 6 noact extra=mixed merged=$((NOW_EPOCH - 3600));       expect "NOT YET: one gated job that RAN means the run is not light" 2 "not activated" "$TMP/c14"; }
r_decoy_heavy(){ build_fx "$TMP/c15" 0 6 noact extra=heavyonly merged=$((NOW_EPOCH - 3600));   expect "NOT YET: test-scripts-heavy skipped but test-scripts ran is not light" 2 "not activated" "$TMP/c15"; }
r_decoy_nofam(){ build_fx "$TMP/c16" 0 6 noact extra=nofam merged=$((NOW_EPOCH - 3600));       expect "NOT YET: a run missing a gated family is not light" 2 "not activated" "$TMP/c16"; }
r_decoy_prefix(){ build_fx "$TMP/c17" 0 6 noact extra=noscripts merged=$((NOW_EPOCH - 3600));  expect "NOT YET: only test-scripts-heavy skipped, no test-scripts job (the family match is not a bare prefix)" 2 "not activated" "$TMP/c17"; }
r_decoy_cancel(){ build_fx "$TMP/c18" 0 6 noact extra=cancelskip merged=$((NOW_EPOCH - 3600)); expect "NOT YET: a CANCELLED run with skipped gated jobs is not an observation" 2 "not activated" "$TMP/c18"; }
# --- (d) LIVE INVARIANTS -----------------------------------------------------------------------------------------------------
r_inv1_success(){ build_fx "$TMP/d1" 20 6 extra=lightsuccess;              expect "FAIL: a light run whose test concluded success" 1 "did not fail" "$TMP/d1"; }
r_inv1_notest(){ build_fx "$TMP/d2" 20 6 extra=lightnotest;                expect "FAIL: a light run with no test row at all" 1 "did not fail" "$TMP/d2"; }
r_inv2_ready(){ build_fx "$TMP/d3" 20 6 extra=lightready;                  expect "FAIL: a light run created after its PR's ready event" 1 "not a draft" "$TMP/d3"; }
r_inv2_converted(){ build_fx "$TMP/d4" 20 6 extra=lightconverted;          expect "PASS: a light run after ready-then-converted-to-draft is legitimate" 0 "PASS" "$TMP/d4"; }
r_inv2_beforeready(){ build_fx "$TMP/d5" 20 6 extra=lightbeforeready;      expect "PASS: a light run before the ready event (the PR was draft) is legitimate" 0 "PASS" "$TMP/d5"; }
r_inv2_never(){ build_fx "$TMP/d6" 20 6 extra=lightnever;                  expect "FAIL: a light run on a PR that was never a draft" 1 "not a draft" "$TMP/d6"; }
r_inv2_convfirst(){ build_fx "$TMP/d7" 20 6 extra=lightconvfirst;          expect "FAIL: a light run before a first convert-to-draft event (the PR was opened ready)" 1 "not a draft" "$TMP/d7"; }
r_inv2_nopr() { build_fx "$TMP/d8" 20 6 extra=lightnopr;                   expect "PASS: a light run whose head no PR claims is counted as unjoined, not a failure" 0 "unjoined=1" "$TMP/d8"; }
r_inv2_multipr(){ build_fx "$TMP/d9" 20 6 extra=lightmultipr;              expect "PASS: only the PR whose head branch matches the run judges it" 0 "PASS" "$TMP/d9"; }
r_inv2_trunc(){ build_fx "$TMP/d10" 20 6 extra=tltrunc;                    expect "PASS: a truncated timeline is unjoined, never guessed" 0 "unjoined=1" "$TMP/d10"; }
r_gqlfail()   { build_fx "$TMP/d11" 20 6 failgql;                          expect "CANNOT ESTABLISH: the PR join read fails" 3 "CANNOT ESTABLISH" "$TMP/d11"; }
r_mgbad()     { build_fx "$TMP/d12" 20 6 mgbad;                            expect "FAIL: a merge_group entry whose PR head's newest pull_request run was light" 1 "#803" "$TMP/d12"; }
r_mgolder()   { build_fx "$TMP/d13" 20 6 mgolder;                          expect "PASS: only the NEWEST pull_request run at the head decides (an older light run does not)" 0 "PASS" "$TMP/d13"; }
r_mgnonqueue(){ build_fx "$TMP/d14" 20 6 mgnonqueue;                       expect "PASS: a merge_group run on a branch that is not a queue branch is ignored" 0 "PASS" "$TMP/d14"; }
r_mgfail()    { build_fx "$TMP/d15" 20 6 failmg;                           expect "CANNOT ESTABLISH: the merge_group listing fails" 3 "CANNOT ESTABLISH" "$TMP/d15"; }
r_mgprfail()  { build_fx "$TMP/d16" 20 6 failmgpr;                         expect "CANNOT ESTABLISH: the queue PR's head read fails" 3 "CANNOT ESTABLISH" "$TMP/d16"; }
r_mgrunfail() { build_fx "$TMP/d17" 20 6 failheadrun;                      expect "CANNOT ESTABLISH: the newest pull_request run lookup fails" 3 "CANNOT ESTABLISH" "$TMP/d17"; }
r_mgcap()     { build_fx "$TMP/d18" 20 6 mgn=35 mgbad mgbadat=31;          expect "PASS: only the newest 30 merge_group runs are sampled (a bad entry at position 31 is outside)" 0 "PASS" "$TMP/d18"; }
r_mg_dark()   { build_fx "$TMP/d19" 0 6 noact merged=$((NOW_EPOCH - 3600)) mgbad; expect "NOT YET: with nothing activated the merge_group listing is not even read" 2 "not activated" "$TMP/d19"
                if grep -cF 'event=merge_group' "$TMP/d19/requests.log" >/dev/null; then fail "merge_group was read while dark"; else pass "no merge_group read while dark"; fi; }
r_light_after_off(){ build_fx "$TMP/d20" 20 6 deact extra=lightafteroff;    expect "FAIL: a light run created after the recorded deactivation" 1 "after the deactivation" "$TMP/d20"; }
# --- (e) EXIT ----------------------------------------------------------------------------------------------------------------
r_six()       { build_fx "$TMP/e3" 20 6 actdays=6;                         expect "NOT YET: 6 days since activation" 2 "6 day" "$TMP/e3"; }
r_seven()     { build_fx "$TMP/e4" 20 6 actdays=7;                         expect "boundary: exactly 7 days PASSES" 0 "PASS" "$TMP/e4"; }
r_nineteen()  { build_fx "$TMP/e5" 19 6;                                   expect "NOT YET: 19 distinct draft pushes" 2 "19 distinct" "$TMP/e5"; }
r_rerun()     { build_fx "$TMP/e6" 19 6 rerun=5;                           expect "NOT YET: re-runs of one head SHA are one push (24 runs, 19 distinct)" 2 "19 distinct" "$TMP/e6"; }
r_stuck29()   { build_fx "$TMP/e7" 19 6 actdays=29 merged=$((NOW_EPOCH - 40 * 86400)); expect "NOT YET: 29 days active with 19 pushes (the deadline is 30)" 2 "19 distinct" "$TMP/e7"; }
r_stuck30()   { build_fx "$TMP/e8" 19 6 actdays=30 merged=$((NOW_EPOCH - 40 * 86400)); expect "FAIL: 30 days active and the soak never reached 20 draft pushes" 1 "19 distinct" "$TMP/e8"; }
r_nomarker()  { build_fx "$TMP/e9" 20 6 marker=none;                       expect "NOT YET: no S3-EXIT-CENSUS marker (the sweeper closes on exit 0)" 2 "S3-EXIT-CENSUS" "$TMP/e9"; }
r_untrusted_marker(){ build_fx "$TMP/e10" 20 6 marker=untrusted;           expect "NOT YET: an exit-census marker by an untrusted commenter does not count" 2 "S3-EXIT-CENSUS" "$TMP/e10"; }
r_nonurl_marker(){ build_fx "$TMP/e11" 20 6 marker=nonurl;                 expect "NOT YET: an exit-census marker without an https github URL does not count" 2 "S3-EXIT-CENSUS" "$TMP/e11"; }
r_placeholder_marker(){ build_fx "$TMP/e12" 20 6 marker=placeholder;       expect "NOT YET: the literal placeholder S3-EXIT-CENSUS: <url> does not count" 2 "S3-EXIT-CENSUS" "$TMP/e12"; }
r_mid_marker(){ build_fx "$TMP/e13" 20 6 marker=mid;                       expect "NOT YET: the marker must start a line" 2 "S3-EXIT-CENSUS" "$TMP/e13"; }
r_lookalike() { build_fx "$TMP/e14" 20 6 marker=lookalike;                 expect "NOT YET: a lookalike host (githubXcom) is not a census URL" 2 "S3-EXIT-CENSUS" "$TMP/e14"; }
r_foreign()   { build_fx "$TMP/e15" 20 6 marker=foreign;                   expect "NOT YET: a non-github URL is not a census URL" 2 "S3-EXIT-CENSUS" "$TMP/e15"; }
r_collab()    { build_fx "$TMP/e16" 20 6 marker=collab;                    expect "PASS: a COLLABORATOR's exit-census comment counts" 0 "PASS" "$TMP/e16"; }
r_contrib()   { build_fx "$TMP/e17" 20 6 marker=contrib;                   expect "NOT YET: a CONTRIBUTOR's exit-census comment does not count" 2 "S3-EXIT-CENSUS" "$TMP/e17"; }
# --- sample caps ---------------------------------------------------------------------------------------------------------------
r_idle_cap()  { build_fx "$TMP/g1" 0 44 noact merged=$((NOW_EPOCH - 3600)) oldlast=lightsuccess; expect "NOT YET: while idle only the newest 40 runs are sampled (a light run at position 45 is outside)" 2 "not activated" "$TMP/g1"; }
r_max_cap()   { build_fx "$TMP/g2" 20 0 pad=85 oldlast=lightsuccess;       expect "PASS: only the newest 100 runs are sampled (a bad light run at position 106 is outside)" 0 "PASS" "$TMP/g2"; }
# --- reads that fail -----------------------------------------------------------------------------------------------------------
r_prfail()    { build_fx "$TMP/h1" 20 6 failpr;                            expect "CANNOT ESTABLISH: the PR merge-time read fails" 3 "CANNOT ESTABLISH" "$TMP/h1"; }
r_commentsfail(){ build_fx "$TMP/h2" 20 6 failcomments;                    expect "CANNOT ESTABLISH: the tracker comments read fails (403)" 3 "CANNOT ESTABLISH" "$TMP/h2"; }
r_runsfail()  { build_fx "$TMP/h3" 20 6 failruns;                          expect "CANNOT ESTABLISH: the pull_request runs listing fails" 3 "CANNOT ESTABLISH" "$TMP/h3"; }
r_jobsfail()  { build_fx "$TMP/h4" 20 6 failjobs;                          expect "CANNOT ESTABLISH: a jobs read fails" 3 "CANNOT ESTABLISH" "$TMP/h4"; }
# the query shapes the probe documents: the since-merge window, the exact jobs read, the sha-keyed PR join, and a
# merge_group window anchored at the activation; one join read per DISTINCT light head (re-runs share it)
r_shapes() {
  build_fx "$TMP/z2" 19 6 rerun=5
  expect_out "$TMP/z2"
  local mi="" ai=""; isoof "$MERGED_EPOCH" mi; isoof "$((NOW_EPOCH - 8 * 86400))" ai
  if grep -cF "status=completed&per_page=100&created=%3E$mi" "$TMP/z2/requests.log" >/dev/null \
     && grep -cF "event=merge_group&status=completed&per_page=100&created=%3E$ai" "$TMP/z2/requests.log" >/dev/null \
     && grep -cF '/jobs?per_page=100&filter=latest' "$TMP/z2/requests.log" >/dev/null \
     && grep -cF 'event=pull_request&head_sha=H801&per_page=1' "$TMP/z2/requests.log" >/dev/null \
     && [ "$(grep -c '^graphql ' "$TMP/z2/requests.log")" -eq 19 ]; then
    pass "the queries carry their documented parameters (merge window, activation-anchored merge_group, jobs filter, head_sha lookup, one join per distinct head)"
  else fail "the queries lost their parameters: $(head -8 "$TMP/z2/requests.log" | tr '\n' '|') graphql=$(grep -c '^graphql ' "$TMP/z2/requests.log")"; fi
}

ALL_ROWS=(r_pass r_info r_stall r_stall2 r_stall_dark r_stall_prec r_vfail r_vgarbage r_vunknown r_vmismatch r_vnoise r_noopen r_openfail
          r_deadline r_deadline_edge r_dark_young r_untrusted_act r_unmerged r_deact r_page2 r_badts r_midact r_crlf r_twoact
          r_light_noact r_light_untrusted r_light_early r_noconf r_conf_untrusted r_conf_placeholder r_conf_bare r_conf_mid r_conf_late
          r_conf_quote r_nolight_noconf r_decoy_mixed r_decoy_heavy r_decoy_nofam r_decoy_prefix r_decoy_cancel
          r_inv1_success r_inv1_notest r_inv2_ready r_inv2_converted r_inv2_beforeready r_inv2_never r_inv2_convfirst r_inv2_nopr
          r_inv2_multipr r_inv2_trunc r_gqlfail r_mgbad r_mgolder r_mgnonqueue r_mgfail r_mgprfail r_mgrunfail r_mgcap r_mg_dark
          r_light_after_off r_six r_seven r_nineteen r_rerun r_stuck29 r_stuck30 r_nomarker r_untrusted_marker r_nonurl_marker
          r_placeholder_marker r_mid_marker r_lookalike r_foreign r_collab r_contrib r_idle_cap r_max_cap
          r_prfail r_commentsfail r_runsfail r_jobsfail r_conf_two r_between r_shapes)
run_rows() { local r; for r in "$@"; do "$r"; done; }
run_rows "${ALL_ROWS[@]}"

# --- the rest of the contract (not mutated below) ------------------------------------------------------------------------------
build_fx "$TMP/z1" 20 6
expect "an unset GH_TOKEN is CANNOT ESTABLISH, never a pass" 3 "GH_TOKEN is not set" "$TMP/z1" GH_TOKEN=
out="$(env FX="$TMP/z1" TPL="$TMP/tpl" PATH="$TMP/bin:$PATH" GH_TOKEN=x SOAK_NOW_EPOCH="$NOW_EPOCH" CI_HEAD_VERDICT_CMD="$TMP/verdict-stub.sh" bash -x "$PROBE" 2>&1)"; rc=$?
if [[ "$rc" == 78 ]]; then pass "xtrace with a live GH_TOKEN is refused (rc=78)"; else fail "xtrace refusal: rc=$rc"; fi
expect "a non-epoch SOAK_NOW_EPOCH is CANNOT ESTABLISH" 3 "not an epoch" "$TMP/z1" SOAK_NOW_EPOCH=soon
expect "a missing resolver script is CANNOT ESTABLISH, never a pass" 3 "CANNOT ESTABLISH" "$TMP/z1" CI_HEAD_VERDICT_CMD="$TMP/none.sh"
# --- mutation rows: each mutated COPY of the probe must turn at least one named row red ----------------------------------------
MUT_RUN=0; MUT_CAUGHT=0
mutant() { # <name> <old> <new> <row ids...>
  local name="$1" old="$2" new="$3"; shift 3
  MUT_RUN=$((MUT_RUN + 1))
  local f="$TMP/mut-$name.sh"
  if ! python3 - "$PROBE" "$f" "$old" "$new" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.stderr.write("anchor count %d for %r\n" % (s.count(old), old)); sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  then fail "MUTANT $name: mutation did NOT land"; return; fi
  cmp -s "$f" "$PROBE" && { fail "MUTANT $name: byte-identical to the probe"; return; }
  chmod +x "$f"
  PROBE_UNDER="$f"; core_rows_quiet "$@"; PROBE_UNDER="$PROBE"
  if [ "$MUT_REDS" -gt 0 ]; then MUT_CAUGHT=$((MUT_CAUGHT + 1)); pass "MUTANT $name turned $MUT_REDS named row(s) red"
  else fail "MUTANT $name: none of rows [$*] went red"; fi
}
core_rows_quiet() { # run the named rows against $PROBE_UNDER, counting reds without recording them as this suite's failures
  local p0=$passes f0=$fails a0=$asserted n0=${#FAILURES[@]}
  run_rows "$@" >/dev/null
  MUT_REDS=$((fails - f0))
  passes=$p0; fails=$f0; asserted=$a0; FAILURES=("${FAILURES[@]:0:$n0}")
}
mutant m-stall-ignored 'stalled) stalled_list="$stalled_list #$pr" ;;' 'stalled) : ;;' r_stall r_stall2 r_stall_dark
mutant m-stall-needs-pushes 'if [ -n "$stalled_list" ]; then' 'if [ -n "$stalled_list" ] && (( light_pushes >= MIN_PUSHES )); then' r_stall_prec r_stall_dark
mutant m-draft-filter '[.[] | select(.draft != true) | .number]' '[.[] | .number]' r_pass
mutant m-closed-set '*) fail_api "verdict for PR $pr (state '"'"'$vstate'"'"' is outside the closed set)" ;;' '*) : ;;' r_vunknown
mutant m-vpr-match '[ "$vpr" = "$pr" ] || fail_api "verdict for PR $pr (the line names PR '"'"'$vpr'"'"')"' ':' r_vmismatch
mutant m-light-any 'all(.conclusion == "skipped")))) as $light' 'any(.conclusion == "skipped")))) as $light' r_decoy_mixed r_decoy_heavy
mutant m-light-nonempty '(length > 0 and all(.conclusion == "skipped"))' '(all(.conclusion == "skipped"))' r_decoy_nofam r_decoy_prefix
mutant m-light-prefix 'test("^" + $n + "( |$)")' 'test("^" + $n)' r_decoy_prefix
mutant m-light-exact 'test("^" + $n + "( |$)")' 'test("^" + $n + "$")' r_pass
mutant m-cancelled 'select(.conclusion == \"success\" or .conclusion == \"failure\") | ' '' r_decoy_cancel
mutant m-test-red 'if [ "$tconc" != "failure" ]; then bad_test=' 'if false; then bad_test=' r_inv1_success r_inv1_notest
mutant m-conf-missing 'if [ -z "$conf_epoch" ]; then' 'if false; then' r_noconf r_conf_untrusted r_conf_placeholder
mutant m-conf-order 'if [ "$conf_epoch" -gt "$first_on_epoch" ]; then' 'if false; then' r_conf_late
mutant m-conf-earliest '.t'"'"' <<<"$comments" 2>/dev/null | sort | head -n 1)"' '.t'"'"' <<<"$comments" 2>/dev/null | sort | tail -n 1)"' r_conf_two
mutant m-conf-anchor "CONF_RE='^S3-CONFIRMED: " "CONF_RE='S3-CONFIRMED: " r_conf_mid
mutant m-conf-any '(https://github\.com/[^ ]+|"[^"]{3,}")$'"'" '.+$'"'" r_conf_bare r_conf_placeholder
mutant m-trusted 'IN("OWNER", "MEMBER", "COLLABORATOR")' 'IN("OWNER", "MEMBER", "COLLABORATOR", "NONE")' r_untrusted_act r_conf_untrusted r_untrusted_marker
mutant m-no-collab 'IN("OWNER", "MEMBER", "COLLABORATOR")' 'IN("OWNER", "MEMBER")' r_collab
mutant m-contrib 'IN("OWNER", "MEMBER", "COLLABORATOR")' 'IN("OWNER", "MEMBER", "COLLABORATOR", "CONTRIBUTOR")' r_contrib
mutant m-early 'if (( ! has_on )) || [ "$created" -lt "$first_on_epoch" ]; then' 'if false; then' r_light_early
mutant m-late 'elif (( deactivated )) && [ "$created" -gt "$off_epoch" ]; then' 'elif false; then' r_light_after_off
mutant m-first-on 'S3-ACTIVATED: //'"'"' | sort | head -n 1)"' 'S3-ACTIVATED: //'"'"' | sort | tail -n 1)"' r_between
mutant m-last-on 'S3-ACTIVATED: //'"'"' | sort | tail -n 1)"' 'S3-ACTIVATED: //'"'"' | sort | head -n 1)"' r_twoact
mutant m-deact-order 'if [ "$act_epoch" -gt "$off_epoch" ]; then active=1; else deactivated=1; fi' 'if true; then active=1; else deactivated=1; fi' r_deact r_page2
mutant m-distinct 'LSHA[$sha]=1' 'LSHA[$id]=1' r_rerun
mutant m-min-pushes 'if (( light_pushes < MIN_PUSHES || age_days < MIN_DAYS )); then' 'if (( age_days < MIN_DAYS )); then' r_nineteen r_rerun
mutant m-min-days 'if (( light_pushes < MIN_PUSHES || age_days < MIN_DAYS )); then' 'if (( light_pushes < MIN_PUSHES )); then' r_six
mutant m-days-edge 'age_days < MIN_DAYS' 'age_days <= MIN_DAYS' r_seven
mutant m-pushes-edge 'light_pushes < MIN_PUSHES' 'light_pushes <= MIN_PUSHES' r_pass
mutant m-stuck 'if (( age_days >= DEADLINE_DAYS )); then' 'if false; then' r_stuck30
mutant m-census 'if (( census_marked == 0 )); then' 'if false; then' r_nomarker r_untrusted_marker r_nonurl_marker
mutant m-census-dot "'^S3-EXIT-CENSUS: https://github\\.com/[^ ]+\$'" "'^S3-EXIT-CENSUS: https://github.com/[^ ]+\$'" r_lookalike
mutant m-census-host "'^S3-EXIT-CENSUS: https://github\\.com/[^ ]+\$'" "'^S3-EXIT-CENSUS: https://[^ ]+\$'" r_foreign
mutant m-census-anchor "'^S3-EXIT-CENSUS: https://github\\.com/[^ ]+\$'" "'S3-EXIT-CENSUS: https://github\\.com/[^ ]+\$'" r_mid_marker
mutant m-deadline 'if (( NOW - merged_epoch > DARK_DAYS * 86400 )); then' 'if false; then' r_deadline r_untrusted_act
mutant m-deadline-edge 'NOW - merged_epoch > DARK_DAYS * 86400' 'NOW - merged_epoch >= DARK_DAYS * 86400' r_deadline_edge
mutant m-mg-flag '&& mg_light_list="$mg_light_list #$qpr"' '&& :' r_mgbad
mutant m-mg-newest "--jq '.workflow_runs[0].id // empty'" "--jq '.workflow_runs[-1].id // empty'" r_mgolder
mutant m-mg-cap 'MG_MAX=30' 'MG_MAX=60' r_mgcap
mutant m-mg-queue-re "QUEUE_RE='^gh-readonly-queue/.+/pr-" "QUEUE_RE='pr-" r_mgnonqueue
mutant m-mg-dark 'mg_light_list=""
if (( active )); then' 'mg_light_list=""
if true; then' r_mg_dark
mutant m-ready-ignored 'ready) bad_ready=$((bad_ready + 1)); bad_ready_list="$bad_ready_list run=$id sha=${sha:0:10}" ;;' 'ready) : ;;' r_inv2_ready r_inv2_never
mutant m-state-swap 'if $last.k == "ReadyForReviewEvent" then "ready" else "draft" end' 'if $last.k == "ReadyForReviewEvent" then "draft" else "ready" end' r_inv2_ready r_inv2_converted
mutant m-first-event 'elif ($ev | length) > 0 then (if $ev[0].k == "ReadyForReviewEvent" then "draft" else "ready" end)' 'elif ($ev | length) > 0 then "draft"' r_inv2_convfirst
mutant m-isdraft 'else (if $p.isDraft then "draft" else "ready" end) end' 'else "draft" end' r_inv2_never
mutant m-branch-join 'map(select(.headRefName == $br))' 'map(.)' r_inv2_multipr
mutant m-trunc 'if $p.timelineItems.pageInfo.hasNextPage then "unknown"' 'if false then "unknown"' r_inv2_trunc
mutant m-gql-cache 'if [ -z "${GQL[$sha]:-}" ]; then' 'if true; then' r_shapes
mutant m-created-window 'created=%3E$merged_at' 'created=%3E$last_on' r_shapes
mutant m-mg-window 'created=%3E$last_on"' 'created=%3E$merged_at"' r_shapes
mutant m-jobs-filter '/jobs?per_page=100&filter=latest' '/jobs?per_page=100' r_shapes r_pass
mutant m-headrun-page 'head_sha=$qsha&per_page=1"' 'head_sha=$qsha&per_page=30"' r_shapes
mutant m-unmerged '[ -n "$merged_at" ] || { echo "NOT YET: PR $S3_PR is not merged"; exit 2; }' ':' r_unmerged
mutant m-api-quiet 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }' 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 0; }' r_jobsfail r_commentsfail r_gqlfail
mutant m-idle-cap '(( active )) || cap="$IDLE_RUNS"' ':' r_idle_cap
mutant m-max-cap 'MAX_RUNS=100' 'MAX_RUNS=200' r_max_cap
mutant m-crlf "tr -d '\\r')\"" ')"' r_crlf
mutant m-ts-loose "TS_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'" "TS_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z?'" r_badts
mutant m-act-anchor 'first_on="$(printf '"'"'%s\n'"'"' "$trusted" | grep -oE "^S3-ACTIVATED' 'first_on="$(printf '"'"'%s\n'"'"' "$trusted" | grep -oE "S3-ACTIVATED' r_midact

if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ] && [ "$MUT_RUN" -ge 40 ]; then pass "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"; else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught; floor 40)"; fi

# harness row: a probe that always exits 0 must be refused by the named rows (the rows can fail)
printf '#!/usr/bin/env bash\necho PASS\nexit 0\n' > "$TMP/always-pass.sh"; chmod +x "$TMP/always-pass.sh"
PROBE_UNDER="$TMP/always-pass.sh"; core_rows_quiet "${ALL_ROWS[@]}"; PROBE_UNDER="$PROBE"
if [ "$MUT_REDS" -ge 60 ]; then pass "HARNESS: an always-PASS probe turns $MUT_REDS rows red"; else fail "HARNESS: an always-PASS probe turned only $MUT_REDS rows red"; fi

printf 'ci-draft-light-soak-9728: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
# DELIBERATELY NOT ROUTED THROUGH fail(): compares against a literal and exits directly.
_total=$((passes + fails))
_FLOOR=150
if [ "$_total" -lt "$_FLOOR" ]; then
  printf '[FATAL] assertion floor: executed %d < %d\n' "$_total" "$_FLOOR" >&2
  exit 1
fi
exit $(( ${#FAILURES[@]} > 0 ))
