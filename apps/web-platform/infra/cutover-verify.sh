#!/usr/bin/env bash
# cutover-verify.sh — the committed CUT0'-CUT9 runner for the ADR-194 apex
# cutover (#7640 PR4b, plan 4.7 / AC62).
#
# WHY A COMMITTED RUNNER AND NOT A CHECKLIST
#
# CUT0'-CUT9 gate the T+20 decision point, and that decision is whether to merge
# a rollback PR against a live, HSTS-preloaded apex. A checklist sampled by hand,
# under incident pressure, at 60-second intervals, is judgemental exactly where
# it must not be. This emits one row per assertion and one exit code.
#
# THREE OUTCOMES, NOT TWO (AP-021). `UNREACHABLE` is a first-class result with
# its own exit code, never folded into PASS or FAIL. An assertion that could not
# be evaluated is not an assertion that passed — that collapse is the defect the
# apex origin probe was rewritten to avoid, and it would be worse here, because
# here it gates a destroy.
#
#   exit 0 — every assertion PASSED
#   exit 1 — at least one assertion FAILED         -> the rollback path
#   exit 2 — no failures, but something was UNREACHABLE -> re-run; do NOT proceed
#
# CUT0' IS NOT CUT0. CUT0 as originally written compared the apex against the
# MERGE SHA, and it is unsatisfiable by construction: `deploy-docs.yml` does not
# fire on `dns.tf`, so no build exists at the cutover merge's SHA and all three
# samples would fail, driving a FALSE rollback. CUT0' compares against the SHA
# recorded by PF-DOCS — the last successful docs deploy — which is the invariant
# actually wanted: the apex serves the build the Pages project holds.
set -uo pipefail

# REFUSE TO RUN UNDER XTRACE. This script authenticates with bearer tokens, and
# `set -x` traces every argument of every command — which is exactly how #7797
# printed the Sentry and BetterStack tokens into a transcript. A prose warning in
# the runbook cannot see `bash -x`, `SHELLOPTS=xtrace`, or a BASH_ENV that sets
# it; this can.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script passes bearer tokens, and -x would print them (see #7797)\n' >&2; exit 64 ;;
esac
if [[ "${SHELLOPTS:-}" == *xtrace* ]]; then
  printf '[FATAL] refusing to run with SHELLOPTS=xtrace: this script passes bearer tokens (see #7797)\n' >&2; exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APEX="${CUTOVER_APEX:-soleur.ai}"
BASELINE="${CUTOVER_MX_TXT_BASELINE:-$SCRIPT_DIR/cutover-mx-txt-baseline.txt}"
MONITOR_BASELINE="${CUTOVER_MONITOR_BASELINE:-$SCRIPT_DIR/cutover-monitor-baseline.txt}"
RESOLVER="${CUTOVER_RESOLVER:-1.1.1.1}"
CURL_MAX_TIME="${CUTOVER_CURL_MAX_TIME:-20}"

PASS=0; FAILED=0; UNREACH=0
row() { # <id> <PASS|FAIL|UNREACHABLE> <detail>
  printf '  %-6s %-12s %s\n' "$1" "$2" "$3"
  case "$2" in
    PASS)        PASS=$((PASS + 1)) ;;
    FAIL)        FAILED=$((FAILED + 1)) ;;
    UNREACHABLE) UNREACH=$((UNREACH + 1)) ;;
  esac
}

usage() {
  cat >&2 <<'USAGE'
usage:
  cutover-verify.sh --expected-sha <sha>      run CUT0'-CUT9
  cutover-verify.sh --capture-baseline <path>         write the CUT9 MX/TXT fixture from live DNS
  cutover-verify.sh --capture-monitor-baseline <path> write the CUT8 monitor-health baseline

  Exit codes: 0 all assertions passed; 1 an assertion FAILED (the rollback path);
  2 nothing failed but something was UNREACHABLE (re-run); 64 usage error.

  --expected-sha is the SHA recorded by PF-DOCS (the last successful
  deploy-docs.yml run), NOT the cutover merge SHA. deploy-docs.yml does not fire
  on dns.tf, so no build exists at the merge SHA and CUT0 read literally would
  fail all three samples and drive a false rollback.
USAGE
  # 64 (EX_USAGE), NOT 2. The header contract maps 2 to "re-run", so sharing it
  # with a usage error makes a mistyped flag look like a transient condition and
  # an operator under T+20 pressure re-runs it forever.
  exit 64
}

# ---------------------------------------------------------------------------------------
# CUT9 NORMALISATION — compare SETS, not bytes in wire order
# ---------------------------------------------------------------------------------------
# `dig +short TXT` ordering is NOT stable across queries (round-robin), so a
# byte-comparison of raw output is a flake generator. The plan's own baseline
# prose said "byte-identical SETS", which conflates the two; this sorts, strips
# the quoting `dig` adds, collapses whitespace and drops blanks, so the
# comparison is over the SET of records.
# PER RECORD, one per line. An earlier form used `tr -s '[:space:]' ' '`, which
# collapses NEWLINES as well and joined every record into a single blob — that
# defeats the set comparison entirely: any reordering changes the blob, which is
# precisely the ordering flake this normalisation exists to remove.
#
# `s/" "//g` joins the chunks `dig` emits for a long TXT record (>255 bytes are
# returned as `"part1" "part2"` on one line).
normalise_records() {
  sed 's/"[[:space:]]*"//g; s/^"//; s/"$//; s/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//' \
    | grep -v '^$' | LC_ALL=C sort -u
}

# Prefix EVERY line with a record-type label. This exists as a function because
# the inline form (`printf 'MX\t%s\n' "$mx"`) labelled only the FIRST record:
# printf reuses its format once per ARGUMENT, and a multi-line capture is one
# argument. That shipped at two sites — the capture path and the comparison path
# — and fixing only the first left CUT9 comparing `MX<TAB>20 mailsec...` on one
# side against a bare `20 mailsec...` on the other, i.e. a guaranteed FAIL that
# says "mail routing changed" when nothing had.
# NO-OP ON EMPTY. `printf '%s\n' ""` emits one blank line, which this would turn
# into a bare `MX<TAB>` row that `grep -v '^$'` cannot remove — a phantom record
# that makes CUT9 report "mail routing changed" when one side simply did not
# resolve. Guarding here kills the class rather than one instance of it.
label_records() { awk -v L="$1" 'NF { print L "\t" $0 }'; }

capture_baseline() { # <out>
  local out="$1" mx txt
  mx="$(dig +short MX "$APEX" "@$RESOLVER" 2>/dev/null | normalise_records)"
  txt="$(dig +short TXT "$APEX" "@$RESOLVER" 2>/dev/null | normalise_records)"
  if [[ -z "$mx" || -z "$txt" ]]; then
    printf '[FATAL] could not resolve MX/TXT for %s via %s — refusing to write an EMPTY baseline.\n' "$APEX" "$RESOLVER" >&2
    printf '[FATAL] An empty fixture would make CUT9 compare nothing against nothing and PASS forever.\n' >&2
    return 2
  fi
  {
    printf '# CUT9 baseline — the apex MX and TXT record SETS (#7640 PR4b, AC62).\n'
    printf '#\n'
    printf '# The A->CNAME apex transition must not disturb mail routing or domain\n'
    printf '# verification. That failure would be SILENT: every uptime monitor watches\n'
    printf '# HTTP, so a broken MX shows up as undelivered mail nobody is waiting for.\n'
    printf '#\n'
    printf '# Captured from LIVE DNS, not derived from dns.tf, and the difference is\n'
    printf '# load-bearing: the zone carries TWO google-site-verification values while\n'
    printf '# the config declares one. A fixture built from the declared config would\n'
    printf '# make CUT9 fail on drift that predates this cutover and has nothing to do\n'
    printf '# with it.\n'
    printf '#\n'
    printf '# It lives here rather than in the plan prose because PR5 ARCHIVES that\n'
    printf '# document, and the rollback would then compare against a moved file.\n'
    printf '#\n'
    printf '# Regenerate: bash cutover-verify.sh --capture-baseline %s\n' "$out"
    printf '# Captured %s via %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RESOLVER"
    printf '%s\n' "$mx"  | label_records MX
    printf '%s\n' "$txt" | label_records TXT
  } > "$out" || { printf '[FATAL] could not write %s\n' "$out" >&2; return 2; }
  # A failed redirection leaves the group non-zero but does NOT stop the next
  # command without `set -e`, so an unwritable path previously printed "wrote"
  # and exited 0 — telling the operator a fresh baseline exists while CUT9 kept
  # grading against the stale committed one.
  [[ -s "$out" ]] || { printf '[FATAL] wrote an empty %s\n' "$out" >&2; return 2; }
  printf 'wrote %s\n' "$out"
}

# ---------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------
# MONITOR HEALTH — one probe, used by CUT8 and by --capture-monitor-baseline
# ---------------------------------------------------------------------------------------
# `.status` ON THE MONITOR IS NOT ITS HEALTH. It is the monitor's CONFIGURATION
# state and reads `active` for an enabled monitor whether the site is up or down
# — measured 2026-09-03, all five read `active` while one was in an active
# failure incident. A CUT8 written against that field cannot go RED, and it would
# be standing in front of a decision to destroy. The health signal is
# `checkStatus` on the per-monitor CHECKS collection, a different endpoint under
# /projects/, and it DOES honour a monitor's custom assertion: the ACME probe
# returns HTTP 404 and records `success`, because its `equals 404` assertion is
# live.
#
# Emits one `name<TAB>healthy|unhealthy|unknown` row per monitor. `unknown` is
# never folded into either of the other two.
SENTRY_MONITORS=(soleur-ai-apex soleur-ai-www soleur-ai-changelog-deep soleur-ai-acme-carveout-probe)
BETTERSTACK_MONITOR="${CUTOVER_BETTERSTACK_MONITOR:-soleur dot ai apex}"

probe_monitor_health() {
  local mon_json name mid proj checks total bad bs_json bs_status
  if [[ -n "${SENTRY_AUTH_TOKEN:-}" && -n "${SENTRY_ORG:-}" ]]; then
    mon_json="$(curl_auth "$SENTRY_AUTH_TOKEN" \
        "https://sentry.io/api/0/organizations/${SENTRY_ORG}/uptime/" 2>/dev/null)" || mon_json=""
    if [[ -z "$mon_json" ]] || ! printf '%s' "$mon_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
      for name in "${SENTRY_MONITORS[@]}"; do printf '%s\tunknown\n' "$name"; done
    else
      for name in "${SENTRY_MONITORS[@]}"; do
        mid="$(printf '%s' "$mon_json"  | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)"
        proj="$(printf '%s' "$mon_json" | jq -r --arg n "$name" '.[] | select(.name == $n) | .projectSlug' | head -1)"
        # A monitor CUT8 names but the org does not have is `unknown`, never
        # healthy — "I could not find it" must not read as "it is green".
        if [[ -z "$mid" || "$mid" == "null" ]]; then printf '%s\tunknown\n' "$name"; continue; fi
        checks="$(curl_auth "$SENTRY_AUTH_TOKEN" \
            "https://sentry.io/api/0/projects/${SENTRY_ORG}/${proj}/uptime/${mid}/checks/" 2>/dev/null)" || checks=""
        total="$(printf '%s' "$checks" | jq -r 'if type=="array" then length else "x" end' 2>/dev/null)"
        if [[ ! "$total" =~ ^[0-9]+$ || "$total" == "0" ]]; then printf '%s\tunknown\n' "$name"; continue; fi
        # BOUND THE WINDOW. The endpoint returns a rolling collection with no time
        # bound, so an unbounded `bad == 0` grades the cutover against checks that
        # PREDATE it — including the failures the cutover's own propagation window
        # produces. At T+20, with monitors on a 300 s interval, those are still in
        # the collection, so every monitor reads unhealthy, every one is scored a
        # REGRESSION, and the gate that decides whether to perform a SECOND
        # destructive change is biased hard toward "roll back" by the very outage
        # it is measuring.
        #
        # `CUTOVER_SINCE` (ISO-8601) scopes the grade to checks at or after the
        # cutover. With no post-cutover sample yet the answer is `unknown` — which
        # routes to UNREACHABLE ("re-run"), never to a regression.
        if [[ -n "${CUTOVER_SINCE:-}" ]]; then
          checks="$(printf '%s' "$checks" | jq --arg t "$CUTOVER_SINCE" \
            '[.[] | select((.timestamp // "") >= $t)]' 2>/dev/null)" || checks=""
          total="$(printf '%s' "$checks" | jq -r 'if type=="array" then length else "x" end' 2>/dev/null)"
          if [[ ! "$total" =~ ^[0-9]+$ || "$total" == "0" ]]; then
            printf '%s\tunknown\n' "$name"; continue
          fi
        fi
        bad="$(printf '%s' "$checks" | jq -r '[.[] | select(.checkStatus != "success")] | length' 2>/dev/null)"
        if [[ "$bad" =~ ^[0-9]+$ && "$bad" == "0" ]]; then printf '%s\thealthy\n' "$name"
        else printf '%s\tunhealthy\n' "$name"; fi
      done
    fi
  else
    for name in "${SENTRY_MONITORS[@]}"; do printf '%s\tunknown\n' "$name"; done
  fi

  # The fifth monitor is a DIFFERENT VENDOR (BetterStack), not a fifth Sentry row.
  local bs_token="${BETTERSTACK_API_TOKEN_READONLY:-${BETTERSTACK_API_TOKEN:-}}"
  if [[ -n "$bs_token" ]]; then
    bs_json="$(curl_auth "$bs_token" \
        "https://uptime.betterstack.com/api/v2/monitors" 2>/dev/null)" || bs_json=""
    bs_status="$(printf '%s' "$bs_json" | jq -r --arg n "$BETTERSTACK_MONITOR" \
        '.data[]? | select((.attributes.pronounceable_name // "") == $n) | .attributes.status' 2>/dev/null | head -1)"
    if   [[ -z "$bs_status" ]];      then printf '%s\tunknown\n'   "$BETTERSTACK_MONITOR"
    elif [[ "$bs_status" == "up" ]]; then printf '%s\thealthy\n'   "$BETTERSTACK_MONITOR"
    else                                  printf '%s\tunhealthy\n' "$BETTERSTACK_MONITOR"; fi
  else
    printf '%s\tunknown\n' "$BETTERSTACK_MONITOR"
  fi
}

MODE="${1:-}"
case "$MODE" in
  --capture-baseline) [[ $# -eq 2 ]] || usage; capture_baseline "$2"; exit $?;;
  --capture-monitor-baseline)
    [[ $# -eq 2 ]] || usage
    mb="$(probe_monitor_health)"
    # Refuse ANY unknown row, not merely an all-unknown file. A partial capture
    # (one monitor resolved, four not) is written by the weaker check, and each
    # unresolved monitor then reads `unknown` at CUT8 — the exact ambiguity the
    # guard's own rationale says makes later comparisons unsound.
    if [[ -n "$mb" ]] && grep -q "$(printf '\t')unknown$" <<<"$mb"; then
      printf '[FATAL] refusing to write a baseline with unresolved monitors:\n' >&2
      grep "$(printf '\t')unknown$" <<<"$mb" | sed 's/^/  /' >&2
      printf '[FATAL] fix credentials/connectivity and re-capture; a partial baseline scores those monitors as regressions later.\n' >&2
      exit 2
    fi
    if [[ -z "$mb" ]] || ! grep -qE "$(printf '\t')(healthy|unhealthy)\$" <<<"$mb"; then
      printf '[FATAL] no monitor resolved to a definite state — refusing to write a baseline of all-unknown.\n' >&2
      printf '[FATAL] Such a baseline makes every later comparison read as a REGRESSION.\n' >&2
      exit 2
    fi
    {
      printf '# CUT8 monitor-health baseline — captured BEFORE the apex cutover (#7640 PR4b).\n'
      printf '#\n'
      printf '# CUT8 compares against this rather than demanding absolute green, because a\n'
      printf '# monitor that was ALREADY red cannot be evidence that the cutover broke\n'
      printf '# anything — and the T+20 rule turns any CUT8 failure into a rollback.\n'
      printf '#\n'
      printf '# Regenerate: bash cutover-verify.sh --capture-monitor-baseline %s\n' "$2"
      printf '# Captured %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '%s\n' "$mb"
    } > "$2"
    printf 'wrote %s\n' "$2"
    exit 0 ;;
  --expected-sha)     [[ $# -eq 2 ]] || usage; EXPECTED_SHA="$2" ;;
  *) usage ;;
esac

[[ -n "${EXPECTED_SHA:-}" ]] || usage

# Print every resolved input. Seven env seams can change what this run measures,
# and the T+20 decision is read off this output — a verdict that does not say
# what it graded against is not reproducible.
printf '\ncutover-verify (ADR-194 apex cutover)\n'
printf '  apex=%s expected_sha=%s resolver=%s max_time=%s\n' "$APEX" "$EXPECTED_SHA" "$RESOLVER" "$CURL_MAX_TIME"
printf '  mx_txt_baseline=%s (sha256 %s)\n' "$BASELINE" \
  "$( [[ -r "$BASELINE" ]] && sha256sum "$BASELINE" 2>/dev/null | cut -c1-12 || echo '<unreadable>')"
printf '  monitor_baseline=%s (sha256 %s)\n' "$MONITOR_BASELINE" \
  "$( [[ -r "$MONITOR_BASELINE" ]] && sha256sum "$MONITOR_BASELINE" 2>/dev/null | cut -c1-12 || echo '<unreadable>')"
printf '  redirect_source=%s since=%s\n\n' "${CUTOVER_REDIR_TF:-$SCRIPT_DIR/seo-bulk-redirects.tf}" "${CUTOVER_SINCE:-<unbounded>}"

# Fetch headers+body once per URL. `HTTPCODE=` is emitted by -w so an empty
# response is distinguishable from a 200 with no body.
NONCE="$(date -u +%s)-$$-${RANDOM}"

# ONE owning trap for every tempfile this script allocates (ADR-129). `fetch` is
# called ~20 times and removes its own body file on both paths, but a SIGINT
# between allocation and removal would leak one per interrupted run — and this
# script is run repeatedly, under time pressure, during a cutover window.
# TMPDIR defaults to /var/tmp so a direct invocation does not land in the
# machine-global /tmp tmpfs that parallel worktrees share.
export TMPDIR="${TMPDIR:-/var/tmp}"
CUTOVER_TMPDIR="$(mktemp -d -t cutover-verify.XXXXXXXX)" || {
  printf '[FATAL] could not create a scratch directory\n' >&2; exit 2; }
trap 'rm -rf "$CUTOVER_TMPDIR"' EXIT INT TERM HUP

# AUTH HEADER VIA STDIN, NEVER ARGV. A `-H "Authorization: Bearer $TOK"` sits in
# /proc/<pid>/cmdline and `ps` for the life of the request. `curl --config -`
# reads the header from stdin, so the token never appears in an argument list.
curl_auth() { # <bearer> <url...>
  local tok="$1"; shift
  printf 'header = "Authorization: Bearer %s"\n' "$tok" \
    | curl -sS --max-time "$CURL_MAX_TIME" --config - "$@"
}

fetch() { # <url> -> "code<TAB>headers<TAB>body" via globals; rc 1 on transport failure
  local url="$1" sep
  sep="$(mktemp -p "$CUTOVER_TMPDIR")" || return 1
  if ! FETCH_HEADERS="$(curl -sS -D - -o "$sep" --max-time "$CURL_MAX_TIME" \
        -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
        -w 'HTTPCODE=%{http_code}\n' "$url" 2>/dev/null)"; then
    rm -f "$sep"; return 1
  fi
  FETCH_BODY="$(cat "$sep")"; rm -f "$sep"
  FETCH_CODE="$(printf '%s' "$FETCH_HEADERS" | grep -oE 'HTTPCODE=[0-9]+' | tail -1 | cut -d= -f2)"
  return 0
}

# Single-sourced with apex-origin-probe.sh — the two lists had diverged, and the
# probe held the SHORTER one while being the rollback's branch selector.
# shellcheck source=apps/web-platform/infra/apex-origin-markers.sh
. "$SCRIPT_DIR/apex-origin-markers.sh"
GH_MARKERS="$APEX_GH_ORIGIN_MARKERS"

# --- CUT0': the apex serves the build the Pages project holds --------------------------
if fetch "https://${APEX}/version.txt?cb=${NONCE}"; then
  got="$(printf '%s' "$FETCH_BODY" | tr -d '[:space:]')"
  if [[ "$FETCH_CODE" != "200" ]]; then
    row "CUT0'" UNREACHABLE "version.txt returned HTTP ${FETCH_CODE:-<none>}"
  elif [[ "$got" == "$EXPECTED_SHA" ]]; then
    row "CUT0'" PASS "apex serves ${got}"
  else
    row "CUT0'" FAIL "apex serves '${got}', PF-DOCS recorded '${EXPECTED_SHA}'"
  fi
else
  row "CUT0'" UNREACHABLE "transport failure fetching version.txt"
fi

# --- CUT1 / CUT2 / CUT6: one fetch of the apex root ------------------------------------
if fetch "https://${APEX}/?cb=${NONCE}"; then
  # if/else, not `A && B || C`: `row` is a reporting helper, and if it ever
  # returns non-zero the `||` arm fires too and the assertion is counted twice.
  if [[ "$FETCH_CODE" == "200" ]]; then
    row CUT1 PASS "apex returns 200"
  else
    row CUT1 FAIL "apex returns HTTP ${FETCH_CODE:-<none>}"
  fi

  # A negative assertion whose PASS arm is reached whenever the grep finds
  # nothing also passes on NO headers at all. CUT1 masks that today, but only
  # incidentally, and CUT2's row would still read PASS in the decision log.
  if [[ -z "$FETCH_HEADERS" ]]; then
    row CUT2 UNREACHABLE "no response headers captured — the marker check was not evaluated"
  elif hit="$(grep -iE "$GH_MARKERS" <<<"$FETCH_HEADERS")"; then
    row CUT2 FAIL "GitHub/Fastly origin marker still present: $(printf '%s' "$hit" | head -1 | cut -c1-60)"
  else
    row CUT2 PASS "no GitHub/Fastly origin markers"
  fi

  if grep -qiE '^strict-transport-security:[[:space:]]*max-age=63072000; includeSubDomains; preload' <<<"$FETCH_HEADERS"; then
    row CUT6 PASS "HSTS preload header intact"
  else
    row CUT6 FAIL "HSTS header missing or changed: $(grep -i '^strict-transport-security' <<<"$FETCH_HEADERS" | head -1 | cut -c1-80)"
  fi
else
  row CUT1 UNREACHABLE "transport failure fetching the apex root"
  # MEASURED-BY: the `fetch` above returned non-zero, i.e. curl did not complete
  # the request. These two rows read that response, so they were not evaluated —
  # this states what the run observed, not why the apex was unreachable.
  row CUT2 UNREACHABLE "not evaluated — the apex root fetch did not complete"
  row CUT6 UNREACHABLE "not evaluated — the apex root fetch did not complete"
fi

# --- CUT3 / CUT4: www canonicalization, WITHOUT following the redirect ------------------
check_redirect() { # <id> <from-url> <want-location>
  local id="$1" from="$2" want="$3" loc
  if ! fetch "$from"; then row "$id" UNREACHABLE "transport failure fetching $from"; return; fi
  if [[ "$FETCH_CODE" != "301" ]]; then
    row "$id" FAIL "$from returned HTTP ${FETCH_CODE:-<none>}, want 301"; return
  fi
  loc="$(grep -i '^location:' <<<"$FETCH_HEADERS" | head -1 | sed 's/^[Ll]ocation:[[:space:]]*//' | tr -d '\r')"
  if [[ "$loc" != "$want" ]]; then
    row "$id" FAIL "$from -> '$loc', want '$want'"; return
  fi
  if grep -qiE "$GH_MARKERS" <<<"$FETCH_HEADERS"; then
    row "$id" FAIL "$from 301s correctly but still carries a GitHub/Fastly origin marker"; return
  fi
  row "$id" PASS "$from -> $loc"
}
check_redirect CUT3 "https://www.${APEX}/" "https://${APEX}/"
# Path preservation, not a bare-apex collapse — the failure this separates from
# CUT3 is a redirect that sends every www path to the apex root.
check_redirect CUT4 "https://www.${APEX}/agents/" "https://${APEX}/agents/"

# --- CUT5: a nonexistent path 404s -----------------------------------------------------
if fetch "https://${APEX}/definitely-not-a-real-path-${NONCE}/"; then
  if [[ "$FETCH_CODE" == "404" ]]; then
    row CUT5 PASS "nonexistent path returns 404"
  else
    row CUT5 FAIL "nonexistent path returns HTTP ${FETCH_CODE:-<none>}, want 404"
  fi
else
  row CUT5 UNREACHABLE "transport failure fetching a nonexistent path"
fi

# --- CUT7 (T-WWW): the ten legacy legal paths still 301 on the www host -----------------
# The source->target pairs are DERIVED from seo-bulk-redirects.tf, never assumed.
# A hand-written table here encoded an identity mapping (`<slug>.html` ->
# `/legal/<slug>/`) and was wrong on the live site: `terms-of-service.html`
# deliberately consolidates into `/legal/terms-and-conditions/`, so ten sources
# resolve to nine distinct targets. Deriving them means CUT7 cannot drift from
# the redirect list it is verifying.
REDIR_TF="${CUTOVER_REDIR_TF:-$SCRIPT_DIR/seo-bulk-redirects.tf}"
mapfile -t LEGAL_PAIRS < <(
  awk '/source_url[[:space:]]*=[[:space:]]*"soleur\.ai\/pages\/legal\//{src=$0}
       /target_url/{if(src!=""){print src" ||| "$0; src=""}}' "$REDIR_TF" 2>/dev/null \
  | sed 's/.*source_url[[:space:]]*=[[:space:]]*"soleur\.ai\/pages\/legal\///; s/\.html"[[:space:]]*|||[[:space:]]*target_url[[:space:]]*=[[:space:]]*"/\t/; s/"[[:space:]]*$//'
)
# Fail closed on an empty or truncated parse. A CUT7 that iterates zero pairs
# reports PASS having verified nothing, which is the shape of every vacuous gate
# this repo has been bitten by.
if [[ "${#LEGAL_PAIRS[@]}" -lt 10 ]]; then
  row CUT7 UNREACHABLE "only ${#LEGAL_PAIRS[@]} legacy legal redirect pair(s) parsed from $(basename "$REDIR_TF") — expected at least 10; NOT verified"
  LEGAL_PAIRS=()
fi
t_www_fail=0; t_www_unreach=0; t_www_ok=0
for pair in "${LEGAL_PAIRS[@]}"; do
  slug="${pair%%$'\t'*}"; want_target="${pair#*$'\t'}"
  if ! fetch "https://www.${APEX}/pages/legal/${slug}.html"; then t_www_unreach=$((t_www_unreach + 1)); continue; fi
  loc="$(grep -i '^location:' <<<"$FETCH_HEADERS" | head -1 | sed 's/^[Ll]ocation:[[:space:]]*//' | tr -d '\r')"
  if [[ "$FETCH_CODE" == "301" && "$loc" == "$want_target" ]]; then
    t_www_ok=$((t_www_ok + 1))
  else
    t_www_fail=$((t_www_fail + 1))
    printf '           /pages/legal/%s.html -> HTTP %s %s (want %s)\n' "$slug" "${FETCH_CODE:-<none>}" "${loc:-<no location>}" "$want_target"
  fi
done
# The count is asserted against the ARRAY's own length, not a literal 10 — a
# literal drifts silently the moment a slug is added or removed.
if   [[ "${#LEGAL_PAIRS[@]}" -eq 0 ]]; then : # already reported UNREACHABLE above
elif [[ "$t_www_fail" -gt 0 ]];    then row CUT7 FAIL "$t_www_fail of ${#LEGAL_PAIRS[@]} legacy legal paths did not 301 to the target seo-bulk-redirects.tf declares"
elif [[ "$t_www_unreach" -gt 0 ]]; then row CUT7 UNREACHABLE "$t_www_unreach of ${#LEGAL_PAIRS[@]} legacy legal paths were unreachable"
else row CUT7 PASS "all ${#LEGAL_PAIRS[@]} legacy legal paths 301 to their declared targets"
fi

# --- CUT8: the five monitors ------------------------------------------------------------
# Deliberately NOT a "check the dashboard" step (hr-no-dashboard-eyeball-pull-data-yourself).
# Without credentials this reports UNREACHABLE — never PASS. A monitor gate that
# degrades to "assume green" is worse than an absent one here.
#
# REGRESSION, NOT ABSOLUTE HEALTH — and the distinction decides a destroy.
# CUT8 as specified reads "all five monitors green". Measured 2026-09-03, BEFORE
# this cutover, `soleur-ai-www` is in an active failure incident: it records its
# CORRECT 301 as a failure because the `equals 301` assertion declared in
# `sentry/uptime-monitors.tf` is not live on the monitor. Read absolutely, CUT8
# can therefore never pass, and the T+20 rule ("on any failure, merge the
# rollback") would roll back a perfectly healthy cutover on the strength of a
# defect that predates it. A pre-existing red monitor is not evidence that the
# cutover broke anything.
#
# So: a monitor already unhealthy at baseline is reported loudly and does not by
# itself fail the cutover; one healthy at baseline and unhealthy now is a
# REGRESSION and fails. With no baseline the check falls back to absolute, which
# is the conservative direction.
CUT8_TOTAL=$(( ${#SENTRY_MONITORS[@]} + 1 ))
MON_NOW="$(probe_monitor_health)"
cut8_ok=0; cut8_fail=0; cut8_unreach=0; regressions=0; preexisting=0
while IFS=$'\t' read -r mname mstate; do
  [[ -z "${mname:-}" ]] && continue
  case "$mstate" in
    healthy) cut8_ok=$((cut8_ok + 1)) ;;
    unknown) cut8_unreach=$((cut8_unreach + 1)); printf '           %s: could not be verified\n' "$mname" ;;
    unhealthy)
      cut8_fail=$((cut8_fail + 1))
      base_state=""
      [[ -r "$MONITOR_BASELINE" ]] && base_state="$(grep -F "$mname"$'\t' "$MONITOR_BASELINE" 2>/dev/null | head -1 | cut -f2)"
      # An `unknown` baseline row means the monitor was not measured at capture
      # time, which is not evidence that it was healthy — so it must not produce
      # a REGRESSION verdict. Treat it as unverifiable and route to UNREACHABLE.
      if [[ "$base_state" == "unknown" ]]; then
        cut8_fail=$((cut8_fail - 1)); cut8_unreach=$((cut8_unreach + 1))
        printf '           %s: unhealthy now, but the baseline never measured it — not scored as a regression\n' "$mname"
      elif [[ "$base_state" == "unhealthy" ]]; then
        preexisting=$((preexisting + 1))
        # MEASURED-BY: this monitor's row in $MONITOR_BASELINE, captured before
        # the cutover, records `unhealthy`. That is evidence the failure PREDATES
        # the cutover; it is not evidence about what caused it, and this message
        # deliberately does not claim one.
        printf '           pre-existing: %s was already unhealthy in the pre-cutover baseline (%s)\n' "$mname" "$MONITOR_BASELINE"
      else
        regressions=$((regressions + 1))
        printf '           REGRESSION: %s is unhealthy (baseline: %s)\n' "$mname" "${base_state:-<no baseline>}"
      fi ;;
  esac
done <<< "$MON_NOW"

if   [[ "$regressions" -gt 0 ]];  then row CUT8 FAIL "$regressions of $CUT8_TOTAL monitor(s) REGRESSED since the pre-cutover baseline"
elif [[ "$cut8_unreach" -gt 0 ]]; then row CUT8 UNREACHABLE "$cut8_unreach of $CUT8_TOTAL monitors could not be verified (this is not a pass)"
elif [[ "$preexisting" -gt 0 ]];  then row CUT8 PASS "no monitor regressed; $preexisting pre-existing failure(s) carried — named above. If soleur-ai-www is among them its 301 is still covered in-band by CUT3/CUT4 (#7798)"
else row CUT8 PASS "all $CUT8_TOTAL monitors healthy"
fi

# --- CUT9: mail routing and domain verification are undisturbed -------------------------
if [[ ! -r "$BASELINE" ]]; then
  row CUT9 UNREACHABLE "baseline fixture missing: $BASELINE"
else
  want="$(grep -vE '^#' "$BASELINE" | grep -v '^$' | LC_ALL=C sort -u)"
  # A zero-byte, comments-only or truncated fixture would otherwise compare an
  # empty `want` against a populated `got` and report FAIL — i.e. "mail routing
  # changed" — for a fixture problem. Require at least one row of each type.
  if ! grep -q "^MX$(printf '\t')" <<<"$want" || ! grep -q "^TXT$(printf '\t')" <<<"$want"; then
    row CUT9 UNREACHABLE "baseline $BASELINE carries no MX and/or TXT rows — not evaluated (regenerate with --capture-baseline)"
    want=""
  fi
  if [[ -n "$want" ]]; then :; else true; fi
  mx_now="$(dig +short MX "$APEX" "@$RESOLVER" 2>/dev/null | normalise_records)"
  txt_now="$(dig +short TXT "$APEX" "@$RESOLVER" 2>/dev/null | normalise_records)"
  # `||`, NOT `&&`. Requiring BOTH sides empty means a resolver that answers MX
  # and times out on TXT falls through into the comparison with one side missing,
  # which reports FAIL — and under the T+20 rule any FAIL is "merge the rollback".
  # One dropped UDP packet would roll back a healthy, live, HSTS-preloaded apex
  # while reporting the cause as "mail routing changed". The capture path one
  # screen up already had this right.
  if [[ -z "$mx_now" || -z "$txt_now" ]]; then
    row CUT9 UNREACHABLE "incomplete DNS read from $RESOLVER (MX:$([[ -n "$mx_now" ]] && echo ok || echo empty) TXT:$([[ -n "$txt_now" ]] && echo ok || echo empty)) — not evaluated"
  else
    got="$( { printf '%s\n' "$mx_now" | label_records MX
              printf '%s\n' "$txt_now" | label_records TXT
            } | grep -v '^$' | LC_ALL=C sort -u)"
    if [[ "$want" == "$got" ]]; then
      row CUT9 PASS "apex MX/TXT sets match the baseline"
    else
      row CUT9 FAIL "apex MX/TXT sets DIFFER from the baseline"
      diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/           /'
    fi
  fi
fi

# EVERY assertion must be accounted for. A run that emits fewer rows than the ten
# CUT assertions has skipped one, and a skipped assertion is not a passed one.
CUT_ROWS_EXPECTED=10
_rows=$((PASS + FAILED + UNREACH))
if [[ "$_rows" -ne "$CUT_ROWS_EXPECTED" ]]; then
  printf '\n[FATAL] %d CUT rows emitted, expected exactly %d — an assertion was skipped, and a skipped assertion is not a pass\n' \
    "$_rows" "$CUT_ROWS_EXPECTED" >&2
  exit 64
fi

printf '\ncutover-verify: %d passed, %d failed, %d unreachable\n' "$PASS" "$FAILED" "$UNREACH"
if   [[ "$FAILED" -gt 0 ]]; then printf 'VERDICT: FAIL — this is the rollback path (merge the generated rollback PR).\n'; exit 1
elif [[ "$UNREACH" -gt 0 ]]; then printf 'VERDICT: UNREACHABLE — re-run. An unevaluated assertion is NOT a pass, and must not be read as clearance to proceed.\n'; exit 2
else printf 'VERDICT: PASS — all CUT assertions hold for this sample.\n'; exit 0
fi
