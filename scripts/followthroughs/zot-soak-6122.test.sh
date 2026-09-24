#!/usr/bin/env bash
# Exit-code harness for zot-soak-6122.sh's decision arms (#6462 AC7/AC9).
#
# WHY A PATH-STUB HARNESS AND NOT A FUNCTION OVERRIDE: the plan originally specified
# "a shell stub harness overriding sentry_count". That is INFEASIBLE and was proven so —
# sentry_count is defined at top level in the soak, which overwrites any pre-export; there
# is no BASH_SOURCE guard, no main(), and the script exit()s at top level, so there is no
# source-and-override seam. `export -f`, BASH_ENV and pre-definition all lose to the
# definition. The seam that DOES exist is PATH: the soak shells out to `curl` and `gh`, so
# stubbing those on PATH drives every arm through the REAL script, including its real jq
# parse path.
#
# WHAT THIS GUARDS: the soak's PASS authorizes ADR-096 5.6 (adopting -> accepted, once 5.3b-iii and
# 5.4 are also done) and #6129 (WARN -> ENFORCE), and it CLOSES the #6122 epic it is enrolled on.
# Every assertion here is about which exit code an arm returns, because the exit code IS the
# authorization artifact. The cardinal sin is exit 0.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOAK="$HERE/zot-soak-6122.sh"
fails=0
GH_ARGV_SINK="$(mktemp)"
URL_SINK="$(mktemp)"
UNMATCHED_SINK="$(mktemp)"
trap 'rm -f "$GH_ARGV_SINK" "$URL_SINK" "$UNMATCHED_SINK"' EXIT
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }
# Instrument self-test (#6500 review): fail() must move the counter the verdict reads, and pass()
# must move its own. Reported with printf + exit, never through the helpers under test.
fail "self-test (expected)" 2>/dev/null; pass "self-test (expected)" >/dev/null
if [[ "$fails" -ne 1 || "$passes" -ne 1 ]]; then
  printf 'FATAL: the verdict helpers do not count (fails=%s passes=%s)\n' "$fails" "$passes" >&2
  exit 1
fi
fails=0; passes=0

[[ -f "$SOAK" ]] || { echo "FATAL: soak not found at $SOAK" >&2; exit 1; }

# Build a stub dir: `curl` answers Sentry queries from a per-query count map, `gh` answers
# the blocker-state probe. Everything else resolves normally via the real PATH.
#
# COUNTS_SPEC is "<substring>=<count>" pairs; the first substring matching the request URL
# wins. HTTP_CODE lets us simulate a non-200 (the TRANSIENT sentinel path).
make_stubs() {
  local dir="$1" counts_spec="$2" gh_state="$3" http_code="${4:-200}" fail_url_substr="${5:-}" gh_reason="${6:-COMPLETED}"
  mkdir -p "$dir" || { echo "FATAL: could not create stub dir $dir" >&2; exit 1; }
  # Mirror sentry_count's REAL contract exactly: it calls
  #   curl -sS -w '\nHTTP_STATUS:%{http_code}' ... "<url>"
  # and then splits body/status with sed. So the stub must emit the JSON body, a newline,
  # then the HTTP_STATUS: trailer — not a bare appended code.
  cat > "$dir/curl" <<STUB
#!/usr/bin/env bash
url=""
for a in "\$@"; do case "\$a" in https://*) url="\$a";; esac; done
# A PER-QUERY 500. Without this the only way to exercise sentry_count's TRANSIENT sentinel was
# a GLOBAL 500 — which the soak catches at its FIRST guarded query (the FAIL_QUERIES loop) and
# so never reaches the later APP_ZOT guard the AC9 arm is named for. See arm 5.
printf '%s\n' "\$url" >> "\${STUB_URL_LOG:-/dev/null}"
if [[ -n "$fail_url_substr" && "\$url" == *"$fail_url_substr"* ]]; then
  printf '{"detail":"boom"}\nHTTP_STATUS:500'; exit 0
fi
matched=0
n=0
IFS=';' read -ra pairs <<< "$counts_spec"
for p in "\${pairs[@]}"; do
  key="\${p%%=*}"; val="\${p##*=}"
  if [[ -n "\$key" && "\$url" == *"\$key"* ]]; then n="\$val"; matched=1; break; fi
done
# ⚠ FAIL LOUD on an unmatched URL rather than defaulting to a counted zero. A silent n=0 would
# read as "healthy" to every FAIL arm, so renaming a stage literal would leave those arms green
# while testing nothing — an unmeasured-value-is-zero default inside the harness written to
# prove the soak never does exactly that. 500 surfaces as TRANSIENT and reddens the arm.
if [[ "\$matched" -eq 0 ]]; then
  printf '%s\n' "\$url" >> "\${STUB_UNMATCHED:-/dev/null}"
  printf '{"detail":"harness: no COUNTS_SPEC key matched %s"}\nHTTP_STATUS:500' "\$url"; exit 0
fi
data=""
if [[ "\$n" -gt 0 ]]; then
  for ((i=0;i<n;i++)); do data="\${data}{\"title\":\"e\",\"timestamp\":\"t\"},"; done
  data="\${data%,}"
fi
printf '{"data":[%s]}\nHTTP_STATUS:%s' "\$data" "$http_code"
STUB
  # Values are exported into the stub's ENVIRONMENT, not interpolated into its SOURCE, so the
  # heredoc is QUOTED. An unquoted <<STUB expands $gh_state at write time, and a `"` or `$(...)`
  # in any value would break out of the generated script — a latent injection in the very file
  # guarding an irreversible act.
  cat > "$dir/gh" <<'STUB'
#!/usr/bin/env bash
# The soak calls: gh issue view <n> --repo github.com/jikig-ai/soleur --json state,stateReason
# Record argv so an arm can assert the repo pin is actually passed. The stub SHADOWS gh's repo
# resolution, so it cannot observe a GH_REPO hijack directly — argv is the witness that the
# soak does not depend on that resolution at all.
printf '%s\n' "$*" >> "$STUB_GH_ARGV"
# The START anchor (#8036 1d, Guard 3): `gh pr view 8660 --repo … --json mergedAt`. Answered
# before the issue branch so an issue-state answer can never be parsed as a mergedAt.
case " $* " in
  *" pr view "*)
    [[ "${STUB_GH_MERGED_AT:-}" == "__UNREADABLE__" ]] && exit 1
    printf '{"mergedAt":"%s"}\n' "${STUB_GH_MERGED_AT-2026-09-24T03:22:41Z}"; exit 0 ;;
esac
# PER-ISSUE ANSWERS (#8651). The soak now consults TWO blockers, and a stub that answers the
# same state for both cannot drive one arm while holding the other settled. Default the web
# blocker to the inngest one so every pre-existing row keeps its exact meaning.
_state="$STUB_GH_STATE"; _reason="$STUB_GH_REASON"
case " $* " in
  *" 8651 "*) [[ -n "${STUB_GH_STATE_WEB:-}" ]] && { _state="$STUB_GH_STATE_WEB"; _reason="${STUB_GH_REASON_WEB:-}"; } ;;
esac
if [[ "$_state" == "__UNREADABLE__" ]]; then exit 1; fi
printf '{"state":"%s","stateReason":"%s"}\n' "$_state" "$_reason"
STUB
  chmod 0755 "$dir/curl" "$dir/gh"
}

# Run the soak with stubs prepended to PATH. Echoes "<exit>|<stdout+stderr>".
# `inngest_fixed` (5th arg): when "yes", run the soak from a THROWAWAY COPY of the repo whose
# cloud-init-inngest.yml carries a zot path + soleur-boot-emit — i.e. the world after #6500 is
# genuinely fixed. This is how the PASS path is tested without touching the real tree: the
# blocker arm resolves cloud-init-inngest.yml relative to the soak's own location (BASH_SOURCE),
# so relocating the script relocates what it corroborates against. No test-only backdoor in the
# gate itself — the gate has no override, and that is deliberate.
run_soak() {
  # `fixture_body` (7th arg, #6500): with inngest_fixed=body, the relocated cloud-init-inngest.yml
  # is exactly this text, so a case can instantiate "one call site" or "calls only as comments",
  # which the fixed yes/old fixtures cannot express. SOAK_UNDER_TEST lets a case run a MUTATED
  # copy of the soak (the in-suite mutation rows below) through the same harness.
  local counts_spec="$1" gh_state="$2" http_code="${3:-200}" fail_url_substr="${4:-}" inngest_fixed="${5:-no}" gh_reason="${6:-COMPLETED}" fixture_body="${7:-}"
  # `web_state`/`web_reason` (8th/9th, #8651): the SECOND blocker arm. Both default to the
  # inngest blocker's values, so every row written before #8651 keeps its exact meaning.
  local web_state="${8:-}" web_reason="${9:-}"
  local src="${SOAK_UNDER_TEST:-$SOAK}"
  local d out rc soak="$src"
  d="$(mktemp -d)"
  if [[ "$inngest_fixed" == "body" ]]; then
    mkdir -p "$d/repo/scripts/followthroughs" "$d/repo/apps/web-platform/infra"
    cp "$src" "$d/repo/scripts/followthroughs/$(basename "$SOAK")"
    printf '%s\n' "$fixture_body" > "$d/repo/apps/web-platform/infra/cloud-init-inngest.yml"
    soak="$d/repo/scripts/followthroughs/$(basename "$SOAK")"
  elif [[ "$inngest_fixed" == "yes" ]]; then
    mkdir -p "$d/repo/scripts/followthroughs" "$d/repo/apps/web-platform/infra"
    cp "$src" "$d/repo/scripts/followthroughs/$(basename "$SOAK")"
    cat > "$d/repo/apps/web-platform/infra/cloud-init-inngest.yml" <<'FIXED'
# Synthetic fixture: the dedicated inngest host AFTER #6500 is fixed — zot-only since #8036 1d (a
# miss is terminal), reporting on the Sentry stage: schema from BOTH outcome arms, in the exact
# call-site form cloud-init-inngest.yml uses. Synthesized, never captured.
    if [ -n "$ZURL" ] && curl -s -o /dev/null --max-time 3 "http://$ZURL/v2/"; then
      IREF="$ZURL/jikig-ai/soleur-inngest-bootstrap:v1.1.19"
    fi
  - path: /usr/local/bin/soleur-boot-emit
    soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true
    soleur-boot-emit inngest_pull_fatal fatal "rc=$zot_rc" || true
FIXED
    soak="$d/repo/scripts/followthroughs/$(basename "$SOAK")"
  elif [[ "$inngest_fixed" == "old" ]]; then
    # Synthetic fixture: the host BEFORE any zot arm — GHCR-only, no off-box report of a zot
    # outcome. Case 7 used to get this state from the REAL repo, which was true until #7462
    # gave that file a zot arm; the case then failed because its PREMISE had gone stale, not
    # because the gate broke. A gate's negative case must instantiate the condition it tests
    # rather than depend on the repo happening to still be in it. The comment lines are
    # deliberate: they name `zot` and `soleur-boot-emit`, so this fixture also re-proves the
    # syntax-anchoring rule (a comment can satisfy no `^\s*`-anchored alternative).
    mkdir -p "$d/repo/scripts/followthroughs" "$d/repo/apps/web-platform/infra"
    cp "$src" "$d/repo/scripts/followthroughs/$(basename "$SOAK")"
    cat > "$d/repo/apps/web-platform/infra/cloud-init-inngest.yml" <<'OLD'
# Synthetic fixture: the dedicated inngest host BEFORE #6500 — hard-pinned GHCR, no zot path.
# TODO: add zot support here one day
# soleur-boot-emit would report this if it existed on this host
    IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.24
    docker pull "$IREF"
OLD
    soak="$d/repo/scripts/followthroughs/$(basename "$SOAK")"
  fi
  make_stubs "$d" "$counts_spec" "$gh_state" "$http_code" "$fail_url_substr" "$gh_reason"
  # Assert the stub actually SHADOWS the real binaries. Without this, a silent stub-creation
  # failure would let the real curl hit sentry.io with a bogus token → 401 → TRANSIENT → exit 2
  # — and arms 5/6 both assert rc=2, so they would pass for entirely the wrong reason.
  local resolved
  resolved="$(PATH="$d:$PATH" command -v curl)"
  [[ "$resolved" == "$d/curl" ]] || { echo "FATAL: stub curl did not shadow the real one (got $resolved)" >&2; exit 1; }
  resolved="$(PATH="$d:$PATH" command -v gh)"
  [[ "$resolved" == "$d/gh" ]] || { echo "FATAL: stub gh did not shadow the real one (got $resolved)" >&2; exit 1; }
  : > "$GH_ARGV_SINK"; : > "$URL_SINK"; : > "$UNMATCHED_SINK"
  # SOAK_START_OVERRIDE=__UNSET__ runs the soak on its OWN default START (no ZOT_SOAK_START in its
  # env at all) — the only way to reach the #8660 mergedAt anchor, which guards the default only.
  local start_env=(ZOT_SOAK_START="${SOAK_START_OVERRIDE:-2026-07-01T00:00:00}")
  [[ "${SOAK_START_OVERRIDE:-}" == "__UNSET__" ]] && start_env=()
  out="$(env -u ZOT_SOAK_START PATH="$d:$PATH" SENTRY_ACTIONS_RO_TOKEN=stub GH_TOKEN=stub \
        STUB_GH_STATE="$gh_state" STUB_GH_REASON="$gh_reason" STUB_GH_ARGV="$GH_ARGV_SINK" \
        STUB_GH_STATE_WEB="$web_state" STUB_GH_REASON_WEB="$web_reason" \
        STUB_GH_MERGED_AT="${STUB_GH_MERGED_AT-2026-09-24T03:22:41Z}" \
        STUB_URL_LOG="$URL_SINK" STUB_UNMATCHED="$UNMATCHED_SINK" \
        "${start_env[@]}" bash "$soak" 2>&1)"; rc=$?
  rm -rf "$d"
  printf '%s|%s' "$rc" "$out"
}

# Query substrings that identify each signal in the request URL (percent-encoded by the soak,
# so match on the stage NAME which survives encoding).
Q_ZOTWEB='image%3A%22web%22'
Q_ZOTING='image%3A%22inngest%22'
# The web fresh-boot fatal arm (#8036 1d): `stage:"pull" level:fatal`, OUTSIDE FAIL_QUERIES.
# `%22pull%22` occurs in no other query (op:image-pull is unquoted), so this key is unambiguous.
Q_WEBFATAL='stage%3A%22pull%22'

# A "healthy fleet" baseline: no fallbacks, sample satisfied, denominator satisfied.
# `soleur-inngest` is FIRST (#6500): the stub matches keys as substrings in order, first match
# wins, and only the host-pinned INNGEST_ZOT query carries that string. Without it every case that
# passes the APP_ZOT arm would 500 on the new query and read TRANSIENT instead of its verdict.
# The RETIRED_QUERIES arm (#8036 1d): the three retired names, each a bare stage: query whose
# name occurs in no other query, so a plain name key is unambiguous. Appended to every spec that
# reaches that arm — without them the stub 500s and the row reads TRANSIENT instead of its verdict.
RETIRED0="app_ghcr_fallback=0;app_ghcr_served=0;inngest_ghcr_fallback=0"
HEALTHY="host_name%3A%22soleur-inngest%22=1;zot-gate-degraded=0;inngest_pull_fatal=0;$Q_WEBFATAL=0;app_zot=3;$Q_ZOTWEB=5;$Q_ZOTING=5;$RETIRED0"

echo "== AC7: the arms return the right exit codes =="

# 1. Dark beacon: zero fallbacks, sample fine, but NO zot-served fresh boot.
#    MUST be exit 1 (FAIL) — never 0, never 2. This is the whole denominator.
r="$(run_soak "zot-gate-degraded=0;inngest_pull_fatal=0;$Q_WEBFATAL=0;app_zot=0;$Q_ZOTWEB=5;$Q_ZOTING=5;$RETIRED0" CLOSED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"no-freshboot-evidence"* ]]; then
  pass "dark beacon (app_zot=0, no fallbacks) -> exit 1 FAIL(no-freshboot-evidence)"
else
  fail "dark beacon must exit 1 with no-freshboot-evidence; got rc=$rc out=$out"
fi

# 2. Blocker OPEN: every soak criterion holds, but the 7th path is still live.
#    exit 1 (FAIL), not 2 — the criteria ARE met; the retirement is BLOCKED.
r="$(run_soak "$HEALTHY" OPEN)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"FAIL(blocked)"* ]]; then
  pass "criteria hold + #6500 OPEN -> exit 1 FAIL(blocked)"
else
  fail "blocker-open must exit 1 with FAIL(blocked); got rc=$rc out=$out"
fi

# 3. The only PASS: criteria hold, the blocker is CLOSED, AND the code corroborates it.
#    Runs against a throwaway tree whose inngest cloud-init is zot-primary + stage:-reporting.
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "0" && "$out" == PASS* ]]; then
  pass "criteria hold + #6500 CLOSED -> exit 0 PASS"
else
  fail "healthy+closed must exit 0 PASS; got rc=$rc out=$out"
fi

# ── #8651: the WEB-HOST blocker arm. Four rows, because a blocker owes both directions:
#    it must be able to REFUSE (3a/3b/3c) and to be SATISFIED (3d). An arm that only ever
#    refuses is indistinguishable from one wired shut, and the PASS row above cannot tell
#    them apart — with the stub defaulting the web state to the inngest one, row 3 would stay
#    green even if this arm hard-failed on OPEN only.

# 3a. The inngest blocker is settled but a fresh WEB boot is dark: exit 1, and the message must
#     name the WEB arm, not the inngest one (they fail for different reasons and the operator
#     needs to know which host is unfixed).
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes COMPLETED "" OPEN)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"FAIL(blocked-web)"* ]]; then
  pass "#8651 3a: #6500 settled + #8651 OPEN -> exit 1 FAIL(blocked-web)"
else
  fail "#8651 3a: web-blocker-open must exit 1 with FAIL(blocked-web); got rc=$rc out=$out"
fi

# 3b. CLOSED is not consent on this arm either. A not-planned close is the realistic path,
#     because autonomous triage operates over this backlog.
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes COMPLETED "" CLOSED NOT_PLANNED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"web-blocker-closed-not-completed"* ]]; then
  pass "#8651 3b: #8651 CLOSED as NOT_PLANNED -> exit 1 (closure reason is not consent)"
else
  fail "#8651 3b: not-planned close must exit 1 web-blocker-closed-not-completed; got rc=$rc out=$out"
fi

# 3c. Fail SAFE on an unreadable web state: TRANSIENT (2), never 0. "Could not measure" must
#     never read as "the measurement is false" on the arm guarding an irreversible act.
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes COMPLETED "" __UNREADABLE__)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "2" && "$out" == *"cannot read #8651 state"* ]]; then
  pass "#8651 3c: unreadable web-blocker state -> exit 2 TRANSIENT (fails safe)"
else
  fail "#8651 3c: unreadable web state must exit 2 TRANSIENT; got rc=$rc out=$out"
fi

# 3d. POSITIVE CONTROL — the arm must be SATISFIABLE. Both blockers CLOSED as COMPLETED, stated
#     explicitly rather than inherited from the default, so this row still means something if
#     the stub's defaulting ever changes. Without it, an arm wired to refuse unconditionally
#     would pass 3a-3c and nothing would notice.
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes COMPLETED "" CLOSED COMPLETED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "0" && "$out" == PASS* ]]; then
  pass "#8651 3d: both blockers CLOSED as COMPLETED -> exit 0 PASS (arm is satisfiable)"
else
  fail "#8651 3d: both-closed must exit 0 PASS; got rc=$rc out=$out"
fi

# 4. A real FAIL_QUERIES event still FAILs, and the per-signal breakdown still prints (the arm the
#    denominator must not have displaced — an operator hitting a real event needs it). One row per
#    member (#8036 1d), so a breakdown that drops either name reds its own row.
r="$(run_soak "inngest_pull_fatal=2;zot-gate-degraded=0;$Q_WEBFATAL=0;app_zot=3;$Q_ZOTWEB=5;$Q_ZOTING=5;$RETIRED0" CLOSED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == FAIL:* && "$out" == *"inngest-pull-fatal=2"* && "$out" == *"gate-degraded=0"* ]]; then
  pass "inngest_pull_fatal>0 -> exit 1 FAIL with per-signal breakdown incl. inngest-pull-fatal"
else
  fail "inngest-pull-fatal must exit 1 and print the breakdown; got rc=$rc out=$out"
fi
r="$(run_soak "zot-gate-degraded=1;inngest_pull_fatal=0;$Q_WEBFATAL=0;app_zot=3;$Q_ZOTWEB=5;$Q_ZOTING=5;$RETIRED0" CLOSED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == FAIL:* && "$out" == *"gate-degraded=1"* && "$out" == *"inngest-pull-fatal=0"* ]]; then
  pass "zot-gate-degraded>0 -> exit 1 FAIL with per-signal breakdown incl. gate-degraded"
else
  fail "gate-degraded must exit 1 and print the breakdown; got rc=$rc out=$out"
fi

# 4b. The insufficient-sample arm. It carries 8 lines of "MUST keep exit 1 — do NOT 'fix' it to
#     TRANSIENT" and had NO test: it is the ONLY detector for the #6437 Sentry-dark mode, so a
#     well-meaning refactor to exit 2 would silently disarm it. One run_soak proves it.
r="$(run_soak "host_name%3A%22soleur-inngest%22=1;zot-gate-degraded=0;inngest_pull_fatal=0;$Q_WEBFATAL=0;app_zot=3;$Q_ZOTWEB=1;$Q_ZOTING=5;$RETIRED0" CLOSED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"FAIL(insufficient-sample)"* ]]; then
  pass "thin zot sample -> exit 1 FAIL(insufficient-sample) (the only #6437 detector)"
else
  fail "thin sample must exit 1 FAIL(insufficient-sample); got rc=$rc out=$out"
fi

echo "== AC9: no arithmetic on an unguarded count (the TRANSIENT sentinel) =="

# 5. THE HAZARD THIS PR'S OWN PLAN DOCUMENTS THREE TIMES: sentry_count echoes the bare word
#    TRANSIENT on a non-200. Arithmetic on that word errors under set -u, and absent set -u
#    would read it as 0 — which for the denominator means "no evidence" (a FAIL that is really
#    a probe failure) and for a counter means "no fallbacks" (a FALSE PASS -> PAT revoked).
#
#    ⚠ THE 500 MUST BE PER-QUERY, NOT GLOBAL. An earlier draft passed a global 500, which the
#    soak catches at its FIRST guarded query (the FAIL_QUERIES loop) and so never reached the
#    APP_ZOT guard this arm is NAMED for — deleting that guard left this suite fully green.
#    A section header naming a guard it never reaches is the exact vacuity class this PR exists
#    to fix, surviving inside the arm written to prevent it. Target app_zot alone.
r="$(run_soak "$HEALTHY" CLOSED 200 'app_zot')"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "2" && "$out" == *"'app_zot' failed"* ]]; then
  pass "app_zot query 500s -> TRANSIENT sentinel -> exit 2 at the APP_ZOT guard, never 0"
else
  fail "a 500 on app_zot alone must exit 2 at the APP_ZOT guard; got rc=$rc out=$out"
fi

# 5b. The same sentinel on a FAIL_QUERIES member (the pre-existing #6435-era guard). Distinct
#     from 5: a different guard, a different arm, and the one a global 500 was really testing.
r="$(run_soak "$HEALTHY" CLOSED 200 'inngest_pull_fatal')"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "2" && "$out" == *"TRANSIENT"* ]]; then
  pass "a FAIL_QUERIES member 500s -> exit 2, never a counted zero"
else
  fail "a 500 on a FAIL_QUERIES member must exit 2; got rc=$rc out=$out"
fi

echo "== C1: the blocker arm fails SAFE on an unreadable state =="

# 6. A gate must never read "I could not measure" as "the measurement is false". Treating an
#    unreadable issue state as CLOSED would PASS the gate during a GitHub outage while the
#    7th path is still live. exit 2 (the probe could not run) — never 0.
r="$(run_soak "$HEALTHY" __UNREADABLE__)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "2" && "$out" == *"cannot read #6500"* ]]; then
  pass "unreadable blocker state -> exit 2 TRANSIENT, never 0"
else
  fail "unreadable blocker must exit 2 TRANSIENT (never 0); got rc=$rc out=$out"
fi

# 7. CLOSED is not FIXED. The blocker arm reads issue STATE, so a careless close would
#    authorize the revoke; the code-corroboration conjunct is what stops it. This harness runs
#    against a SYNTHETIC GHCR-only fixture. It used to run against the REAL repo and rely on
#    cloud-init-inngest.yml still having no zot path — which #7462 made false, so the case
#    started failing on a stale premise rather than a broken gate. A negative case must
#    instantiate the condition it tests; depending on the corpus staying in that condition is
#    corpus accident, and it expires silently the moment someone fixes the thing.
r="$(run_soak "$HEALTHY" CLOSED 200 "" old)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"blocker-closed-but-condition-unmet"* ]]; then
  pass "#6500 CLOSED but the inngest host still GHCR-only -> exit 1, closing the issue cannot bypass"
else
  fail "a CLOSED blocker with the condition unmet must exit 1; got rc=$rc out=$out"
fi

# 8. The repo pin. security-sentinel proved the unpinned form live: with every other arm
#    satisfied, `GH_REPO=microsoft/vscode` made the soak read THAT repo's #6500 (which is
#    closed) and emit rc=0 "Safe to retire GHCR". A stub gh SHADOWS the resolution it would
#    need to observe, so assert on argv instead: the soak must pin host+repo and therefore
#    never depend on ambient GH_REPO/GH_HOST at all.
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes)"
gh_argv="$(cat "$GH_ARGV_SINK" 2>/dev/null || true)"
if [[ "$gh_argv" == *"--repo github.com/jikig-ai/soleur"* ]]; then
  pass "blocker arm pins host+repo on gh (ambient GH_REPO/GH_HOST cannot redirect it)"
else
  fail "gh must be called with --repo github.com/jikig-ai/soleur; argv was: ${gh_argv:-<none>}"
fi

# 9. CLOSED is not consent. Every closure reason returns state=CLOSED, so a not-planned /
#    duplicate / autonomous-triage close (ticket-triage and drain-labeled-backlog both operate
#    over this backlog) would otherwise authorize an irreversible PAT revoke.
r="$(run_soak "$HEALTHY" CLOSED 200 "" yes NOT_PLANNED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"blocker-closed-not-completed"* ]]; then
  pass "#6500 closed as NOT_PLANNED -> exit 1, a tidy-up close cannot authorize"
else
  fail "a not-planned close must exit 1; got rc=$rc out=$out"
fi

# 10. The corroboration grep must not be satisfied by PROSE. Verified as a real bypass: two
#     comment lines ("# TODO: add zot support", "# soleur-boot-emit would report this") passed
#     the earlier bare-word grep on a file that was still GHCR-only — the guard added to close
#     the careless-close bypass was itself bypassable by a comment. Anchors on ^\s*IREF=.*$ZURL
#     and ^\s*soleur-boot-emit now; a comment line begins with '#' and cannot produce either.
d10="$(mktemp -d)"
mkdir -p "$d10/repo/scripts/followthroughs" "$d10/repo/apps/web-platform/infra"
cp "$SOAK" "$d10/repo/scripts/followthroughs/"
printf '# TODO: add zot support here one day\n# soleur-boot-emit would report this\nIREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.19\n' \
  > "$d10/repo/apps/web-platform/infra/cloud-init-inngest.yml"
make_stubs "$d10" "$HEALTHY" CLOSED 200 "" COMPLETED
out10="$(PATH="$d10:$PATH" SENTRY_ACTIONS_RO_TOKEN=stub GH_TOKEN=stub \
        STUB_GH_STATE=CLOSED STUB_GH_REASON=COMPLETED STUB_GH_ARGV="$GH_ARGV_SINK" \
        ZOT_SOAK_START="2026-07-01T00:00:00" bash "$d10/repo/scripts/followthroughs/$(basename "$SOAK")" 2>&1)"; rc10=$?
rm -rf "$d10"
if [[ "$rc10" == "1" && "$out10" == *"blocker-closed-but-condition-unmet"* ]]; then
  pass "comments naming zot/soleur-boot-emit do NOT satisfy the corroboration grep"
else
  fail "prose must not satisfy the corroboration grep; got rc=$rc10 out=$out10"
fi

echo "== #6500 Guard 6: the dedicated host's Sentry evidence, and its code, gate the PASS =="

# Fixtures for the corroboration predicate. Each is a DIFFERENT partial state of the fix.
F_BS_ONLY='    ZIREF="$ZOT_EP/jikig-ai/soleur-inngest-bootstrap:v1.1.37@sha256:0000"
        /usr/local/bin/inngest-boot-phone-home.sh inngest_zot "bootstrap image served by zot ep=$ZOT_EP"'
F_ZOT_ONLY="$F_BS_ONLY"'
        soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true'
F_COMMENTS="$F_BS_ONLY"'
        # soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true
        # soleur-boot-emit inngest_pull_fatal fatal "rc=$zot_rc" || true'
F_BOTH="$F_BS_ONLY"'
  - path: /usr/local/bin/soleur-boot-emit
        soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true
        soleur-boot-emit inngest_pull_fatal fatal "rc=$zot_rc" || true'
# The call sites without the write_files entry that delivers the emitter (security F3).
F_NO_EMITTER="$F_BS_ONLY"'
        soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true
        soleur-boot-emit inngest_pull_fatal fatal "rc=$zot_rc" || true'

# g6 <label> <expected rc> <expected substring> <run_soak args...>: one row, one verdict. Returns 0
# when the verdict matched, so the mutation rows below can reuse the same row as their oracle.
g6_row() {
  local want_rc="$1" want="$2"; shift 2
  local r rc out
  r="$(run_soak "$@")"; rc="${r%%|*}"; out="${r#*|}"
  G6_LAST="rc=$rc out=${out:0:300} unmatched=$(head -c 200 "$UNMATCHED_SINK")"
  [[ ! -s "$UNMATCHED_SINK" && "$rc" == "$want_rc" && "$out" == *"$want"* ]]
}
g6() {
  local label="$1"; shift
  if g6_row "$@"; then pass "G6 $label"; else fail "G6 $label; got $G6_LAST"; fi
}
# Row 1: today's pre-#6500 shape (Better Stack only) — CLOSED/COMPLETED must still not PASS.
g6 "row 1: only the Better Stack inngest_zot call -> blocker-closed-but-condition-unmet" \
  1 "blocker-closed-but-condition-unmet" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_BS_ONLY"
g6 "row 2: soleur-boot-emit inngest_zot without inngest_pull_fatal -> condition unmet" \
  1 "blocker-closed-but-condition-unmet" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_ZOT_ONLY"
g6 "row 3: both calls present only as comments -> condition unmet" \
  1 "blocker-closed-but-condition-unmet" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_COMMENTS"
G6_NOEV="${HEALTHY/host_name%3A%22soleur-inngest%22=1/host_name%3A%22soleur-inngest%22=0}"
g6 "row 4: the dedicated host reported no zot-served boot -> FAIL(no-inngest-freshboot-evidence)" \
  1 "no-inngest-freshboot-evidence" "$G6_NOEV" CLOSED 200 "" body COMPLETED "$F_BOTH"
g6 "row 5: the host-pinned query 500s -> exit 2 TRANSIENT, never 0" \
  2 "'inngest_zot host_name:soleur-inngest' failed" "$HEALTHY" CLOSED 200 "host_name%3A%22soleur-inngest%22" body COMPLETED "$F_BOTH"
# Row 8: a colocated WEB host reported inngest_zot, the dedicated host did not. Also the
# discriminator for a dropped host_name filter: without it the query would match `inngest_zot=1`.
G6_COLOC="host_name%3A%22soleur-inngest%22=0;inngest_zot=1;${HEALTHY#host_name%3A%22soleur-inngest%22=1;}"
g6 "row 8: only a colocated web host reported inngest_zot -> FAIL(no-inngest-freshboot-evidence)" \
  1 "no-inngest-freshboot-evidence" "$G6_COLOC" CLOSED 200 "" body COMPLETED "$F_BOTH"
g6 "row 9 (must-PASS): both calls, #6500 CLOSED/COMPLETED, soleur-inngest=1 -> exit 0" \
  0 "PASS" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_BOTH"

# G1 row 10: the emitter's HOST_NAME literal and the soak's host_name filter are one value.
EMIT_HOST="$(grep -oE "^[[:space:]]*HOST_NAME='[^']+'" "$HERE/../../apps/web-platform/infra/cloud-init-inngest.yml" | head -1 | sed -E "s/.*'([^']+)'/\1/" || true)"
SOAK_HOST="$(grep -E '^INNGEST_ZOT=\$\(sentry_count ' "$SOAK" | grep -oE 'host_name:"[^"]+"' | sed -E 's/host_name:"([^"]+)"/\1/' || true)"
if [[ -n "$EMIT_HOST" && "$EMIT_HOST" == "$SOAK_HOST" ]]; then
  pass "G1 row 10: the emitter's HOST_NAME ($EMIT_HOST) is the soak denominator's host_name filter"
else
  fail "G1 row 10: emitter HOST_NAME '${EMIT_HOST:-<none>}' != soak host_name '${SOAK_HOST:-<none>}'"
fi

g6 "security F3: both call sites but no write_files entry delivering the emitter -> condition unmet" \
  1 "blocker-closed-but-condition-unmet" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_NO_EMITTER"
# The REAL cloud-init-inngest.yml satisfies the corroboration (review P2-4 of the pattern seat):
# every other CLOSED row uses a fixture, so without this the grep never meets the real file.
g6 "real file: the repo's cloud-init-inngest.yml satisfies every corroboration predicate -> exit 0" \
  0 "PASS" "$HEALTHY" CLOSED 200 "" no COMPLETED
# The dedicated-host query is EXACTLY the pinned clause (review P1-1). The stub matches by
# substring, so a widened query (`… OR stage:"inngest_zot"`) still contains the clause and still
# answers; only the exact decoded query distinguishes them.
exact_inngest_query() {
  python3 - "$URL_SINK" <<'PYQ'
import sys, urllib.parse
want = 'stage:"inngest_zot" host_name:"soleur-inngest"'
qs = [urllib.parse.parse_qs(urllib.parse.urlsplit(l.strip()).query).get("query", [""])[0]
      for l in open(sys.argv[1]) if l.strip()]
hits = [q for q in qs if "inngest_zot" in q]
sys.exit(0 if hits == [want] else 1)
PYQ
}
g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_BOTH" >/dev/null
if exact_inngest_query; then
  pass "G6: the dedicated-host denominator query is exactly stage:\"inngest_zot\" host_name:\"soleur-inngest\""
else
  fail "G6: the dedicated-host denominator query is not the exact pinned clause: $(grep -c . "$URL_SINK") URL(s) logged"
fi
# START is spliced into the URL unencoded; a prefix-only check admitted a second start= param.
if SOAK_START_OVERRIDE='2026-01-01T&start=2026-09-01T00:00:00' g6_row 2 "START is unpinned or malformed" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_BOTH"; then
  pass "START carrying a smuggled query parameter -> exit 2 TRANSIENT, never a verdict"
else
  fail "START carrying a smuggled query parameter must exit 2; got $G6_LAST"
fi

# Mutation rows 6-7 (+ the host_name filter): mutate a COPY of the soak, require the mutation to
# have landed, then run the row that must go RED on it.
g6_mutant() { # g6_mutant <label> <sed-script> <row args...>
  local label="$1" script="$2"; shift 2
  local m; m="$(mktemp)"
  sed -e "$script" "$SOAK" > "$m"
  if cmp -s "$SOAK" "$m"; then
    fail "G6 $label — HARNESS ABORT: the mutation did not land"
  elif SOAK_UNDER_TEST="$m" g6_row "$@"; then
    fail "G6 $label — mutant SURVIVED"
  else
    pass "G6 $label — mutant killed"
  fi
  rm -f "$m"
}
g6_mutant "row 6: delete the INNGEST_ZOT arm" \
  '/^INNGEST_ZOT=\$(sentry_count/,/^fi$/d; /^if (( INNGEST_ZOT == 0 )); then$/,/^fi$/d' \
  1 "no-inngest-freshboot-evidence" "$G6_NOEV" CLOSED 200 "" body COMPLETED "$F_BOTH"
g6_mutant "row 7: drop _zot_reports_sentry_stage from the corroboration if" \
  's/ || ! _zot_reports_sentry_stage "\$INNGEST_CI"//' \
  1 "blocker-closed-but-condition-unmet" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_BS_ONLY"
g6_mutant_query() { # the widening (review P1-1): mutant must fail the EXACT-query check
  local m; m="$(mktemp)"
  sed -e 's/stage:"inngest_zot" host_name:"soleur-inngest"/stage:"inngest_zot" host_name:"soleur-inngest" OR stage:"inngest_zot"/' "$SOAK" > "$m"
  if cmp -s "$SOAK" "$m"; then fail "G6 widened query — HARNESS ABORT: the mutation did not land"
  else
    SOAK_UNDER_TEST="$m" g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_BOTH" >/dev/null
    if exact_inngest_query; then fail "G6 widened query (… OR stage:inngest_zot) — mutant SURVIVED"
    else pass "G6 widened query (… OR stage:inngest_zot) — mutant killed"; fi
  fi
  rm -f "$m"
}
g6_mutant_query
g6_mutant "extra: drop the host_name filter from the denominator" \
  's/stage:"inngest_zot" host_name:"soleur-inngest"/stage:"inngest_zot"/' \
  1 "no-inngest-freshboot-evidence" "$G6_COLOC" CLOSED 200 "" body COMPLETED "$F_BOTH"
# Harness row: run in a subshell so its deliberate FAIL does not count; the output is the witness.
G6_PROBE="$(g6_mutant "probe" 's/THIS-STRING-IS-NOT-IN-THE-SOAK/x/' 0 "never" "$HEALTHY" CLOSED 2>&1)"
if [[ "$G6_PROBE" == *"HARNESS ABORT"* ]]; then
  pass "G6 harness: a mutation that matches nothing is reported as HARNESS ABORT, never scored"
else
  fail "G6 harness: an unlanded mutation was not reported as HARNESS ABORT; got: ${G6_PROBE:0:200}"
fi

# F_BOTH's shape under the RETIRED name: a template still emitting inngest_ghcr_fallback must not
# satisfy the #6500 corroboration (#8036 1d renamed the stage; the predicate reads the new one).
F_OLD_NAME="$F_BS_ONLY"'
  - path: /usr/local/bin/soleur-boot-emit
        soleur-boot-emit inngest_zot info "ep=$ZOT_EP" || true
        soleur-boot-emit inngest_ghcr_fallback warning "rc=$zot_rc" || true'
g6 "#8036 1d: the miss arm still on the retired inngest_ghcr_fallback name -> condition unmet" \
  1 "blocker-closed-but-condition-unmet" "$HEALTHY" CLOSED 200 "" body COMPLETED "$F_OLD_NAME"

echo "== #8036 1d: the web fresh-boot fatal arm (outside FAIL_QUERIES) =="

# WF1. A web fresh boot that died at stage=pull FAILs the soak, with every other signal healthy.
#      Named label + the count, so the operator can tell it from a FAIL_QUERIES event.
g6 "WF1: stage:\"pull\" level:fatal = 1, all else healthy -> exit 1 FAIL(web-pull-fatal)" \
  1 "FAIL(web-pull-fatal)" "${HEALTHY/$Q_WEBFATAL=0/$Q_WEBFATAL=1}" CLOSED 200 "" yes COMPLETED
if [[ "$G6_LAST" == *"web-pull-fatal=1"* ]]; then
  pass "WF1b: the web-fatal FAIL line carries the web-pull-fatal=<n> count"
else
  fail "WF1b: the web-fatal FAIL line must carry web-pull-fatal=1; got $G6_LAST"
fi
# WF2. The string guard before the arithmetic: a 500 on this query alone is TRANSIENT, never a
#      counted zero (which would be a false PASS) and never an arithmetic error.
g6 "WF2: the web-fatal query 500s -> exit 2 TRANSIENT at its own guard" \
  2 "'web-pull-fatal' failed" "$HEALTHY" CLOSED 200 "$Q_WEBFATAL" yes COMPLETED
# WF3. The query is EXACTLY the pinned clause (the stub matches by substring, so a widened or
#      prefixed query would still answer; only the decoded query distinguishes them).
exact_query() { # exact_query <needle> <want>: every logged query containing needle == want, >=1
  python3 - "$URL_SINK" "$1" "$2" <<'PYQ'
import sys, urllib.parse
qs = [urllib.parse.parse_qs(urllib.parse.urlsplit(l.strip()).query).get("query", [""])[0]
      for l in open(sys.argv[1]) if l.strip()]
hits = [q for q in qs if sys.argv[2] in q]
sys.exit(0 if hits == [sys.argv[3]] else 1)
PYQ
}
g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" yes COMPLETED >/dev/null
if exact_query '"pull"' 'stage:"pull" level:fatal'; then
  pass "WF3: the web-fatal query is exactly stage:\"pull\" level:fatal (bare — _emit writes no feature/op)"
else
  fail "WF3: the web-fatal query is not the exact pinned clause"
fi
# WF4. Mutation: delete the arm. WF1's fixture must then stop FAILing on web-pull-fatal.
g6_mutant "WF4: delete the WEB_FATAL arm" \
  '/^WEB_FATAL=\$(sentry_count/,/^fi$/d; /^if (( WEB_FATAL > 0 )); then$/,/^fi$/d' \
  1 "FAIL(web-pull-fatal)" "${HEALTHY/$Q_WEBFATAL=0/$Q_WEBFATAL=1}" CLOSED 200 "" yes COMPLETED
# WF5. NOT a FAIL_QUERIES member: the rule⇔soak parity contract (op-contract test) would break,
#      because web_terminal_boot_fatal — not zot_mirror_fallback_rate — pages this stage.
SOAK_ARRAY_BODY="$(awk '/^declare -A FAIL_QUERIES=\(/{f=1;next} f&&/^\)/{exit} f' "$SOAK")"
if [[ -n "$SOAK_ARRAY_BODY" && "$SOAK_ARRAY_BODY" != *'"pull"'* ]] \
   && grep -qE "^WEB_FATAL=\\\$\\(sentry_count 'stage:\"pull\" level:fatal'\\)$" "$SOAK"; then
  pass "WF5: stage:\"pull\" is counted by WEB_FATAL and is NOT a FAIL_QUERIES member (parity holds)"
else
  fail "WF5: the web-fatal query must live outside FAIL_QUERIES, as WEB_FATAL=\$(sentry_count 'stage:\"pull\" level:fatal')"
fi

echo "== #8036 1d Guard 3: the default START is the operator's re-arm, anchored on #8660 =="

# The literal the operator recorded on #6122 (comment 5811202876, 2026-09-24T09:07:09Z) as the
# soak re-arm, which is also PR #8660's mergedAt (2026-09-24T03:22:41Z). Both records sit outside
# this commit, so a diff that moves the literal contradicts a record it cannot edit.
REARM_START="2026-09-24T03:22:41"
start_pin_ok() { # start_pin_ok <soak-file>: exactly ONE START= assignment, and its default == REARM_START
  local f="$1" n v
  n="$(grep -cE '^[[:space:]]*START=' "$f")"
  v="$(sed -nE 's/^START="\$\{ZOT_SOAK_START:-([^}]*)\}"$/\1/p' "$f")"
  START_PIN_LAST="assignments=$n default='${v:-<unparsed>}'"
  [[ "$n" == "1" && "$v" == "$REARM_START" ]]
}
if start_pin_ok "$SOAK"; then
  pass "G3: exactly one START= assignment, default == $REARM_START (#6122 c5811202876 / #8660 mergedAt)"
else
  fail "G3: default START must be exactly $REARM_START in a single assignment; got $START_PIN_LAST"
fi
# Guard 3 mutation rows 1-3, in-suite: each mutant of the soak must fail start_pin_ok.
g3_mutant() { # g3_mutant <label> <sed-script>
  local m; m="$(mktemp)"
  sed -e "$2" "$SOAK" > "$m"
  if cmp -s "$SOAK" "$m"; then fail "G3 $1 — HARNESS ABORT: the mutation did not land"
  elif start_pin_ok "$m"; then fail "G3 $1 — mutant SURVIVED ($START_PIN_LAST)"
  else pass "G3 $1 — mutant killed ($START_PIN_LAST)"; fi
  rm -f "$m"
}
g3_mutant "row 1: default one second later" 's/ZOT_SOAK_START:-2026-09-24T03:22:41}/ZOT_SOAK_START:-2026-09-24T03:22:42}/'
g3_mutant "row 2: the old 2026-07-17T19:45:00 default restored" 's/ZOT_SOAK_START:-2026-09-24T03:22:41}/ZOT_SOAK_START:-2026-07-17T19:45:00}/'
g3_mutant "row 3: a second START= assignment later in the body" '/^END=\$(date/a START=2026-09-30T00:00:00'

# The runtime anchor (the default only; ZOT_SOAK_START is the documented test/manual seam).
# MA1: default START, #8660 mergedAt == START -> the anchor is satisfied and the soak reaches PASS.
if SOAK_START_OVERRIDE=__UNSET__ g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" yes COMPLETED; then
  pass "MA1: default START == #8660 mergedAt -> the anchor holds (exit 0 PASS)"
else
  fail "MA1: default START equal to #8660 mergedAt must not block the PASS; got $G6_LAST"
fi
gh_argv="$(cat "$GH_ARGV_SINK" 2>/dev/null || true)"
if [[ "$gh_argv" == *"pr view 8660 --repo github.com/jikig-ai/soleur --json mergedAt"* ]]; then
  pass "MA1b: the anchor reads #8660 mergedAt with the host+repo pin"
else
  fail "MA1b: expected gh pr view 8660 --repo github.com/jikig-ai/soleur --json mergedAt; argv was: ${gh_argv:-<none>}"
fi
# MA2: #8660 unreadable -> TRANSIENT (could not measure), never a verdict.
if SOAK_START_OVERRIDE=__UNSET__ STUB_GH_MERGED_AT=__UNREADABLE__ g6_row 2 "cannot read #8660 mergedAt" "$HEALTHY" CLOSED 200 "" yes COMPLETED; then
  pass "MA2: #8660 mergedAt unreadable -> exit 2 TRANSIENT"
else
  fail "MA2: an unreadable #8660 mergedAt must exit 2; got $G6_LAST"
fi
# MA2b: readable but not a timestamp (an unmerged PR answers null) -> TRANSIENT too.
if SOAK_START_OVERRIDE=__UNSET__ STUB_GH_MERGED_AT="" g6_row 2 "cannot read #8660 mergedAt" "$HEALTHY" CLOSED 200 "" yes COMPLETED; then
  pass "MA2b: #8660 mergedAt empty/null -> exit 2 TRANSIENT"
else
  fail "MA2b: an empty #8660 mergedAt must exit 2; got $G6_LAST"
fi
# MA3: the default START is LATER than the record it cites -> FAIL (the false-PASS route: a late
#      START drops bad events from the window). Simulated by moving the anchor one second earlier.
if SOAK_START_OVERRIDE=__UNSET__ STUB_GH_MERGED_AT="2026-09-24T03:22:40Z" g6_row 1 "FAIL(start-after-anchor)" "$HEALTHY" CLOSED 200 "" yes COMPLETED; then
  pass "MA3: default START later than #8660 mergedAt -> exit 1 FAIL(start-after-anchor)"
else
  fail "MA3: a default START after #8660 mergedAt must exit 1; got $G6_LAST"
fi
# MA4 (Guard 3 row 4, harness, must-PASS): an explicit ZOT_SOAK_START later than the anchor is the
#      documented override seam and is NOT checked against #8660 — the pin is on the default.
if SOAK_START_OVERRIDE="2026-09-25T00:00:00" STUB_GH_MERGED_AT="2026-09-24T03:22:40Z" g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" yes COMPLETED; then
  pass "MA4: ZOT_SOAK_START=2026-09-25T00:00:00 override -> anchor not applied, exit 0 PASS"
else
  fail "MA4: an explicit ZOT_SOAK_START must bypass the default-only anchor; got $G6_LAST"
fi
# MA5: mutation — delete the anchor's FAIL branch; MA3's fixture must then no longer FAIL on it.
ma5="$(mktemp)"
sed -e '/^  if \[\[ "\${START%Z}" > "\${anchor%Z}" \]\]; then$/,/^  fi$/d' "$SOAK" > "$ma5"
if cmp -s "$SOAK" "$ma5"; then
  fail "MA5 — HARNESS ABORT: the mutation did not land"
elif SOAK_UNDER_TEST="$ma5" SOAK_START_OVERRIDE=__UNSET__ STUB_GH_MERGED_AT="2026-09-24T03:22:40Z" g6_row 1 "FAIL(start-after-anchor)" "$HEALTHY" CLOSED 200 "" yes COMPLETED; then
  fail "MA5: deleting the anchor's FAIL branch — mutant SURVIVED"
else
  pass "MA5: deleting the anchor's FAIL branch — mutant killed"
fi
rm -f "$ma5"

echo "== #8036 1d: the RETIRED-NAMES arm (outside FAIL_QUERIES) =="

# RN1a-c. Each retired name, alone, FAILs a window that is otherwise fully healthy — one flat row
#         per name (a loop over a table hides a missing entry). The breakdown must name it.
g6 "RN1a: app_ghcr_fallback=1, all else healthy -> exit 1 FAIL(retired-names)" \
  1 "FAIL(retired-names)" "${HEALTHY/app_ghcr_fallback=0/app_ghcr_fallback=1}" CLOSED 200 "" yes COMPLETED
[[ "$G6_LAST" == *"app_ghcr_fallback=1"* ]] && pass "RN1a': the breakdown names app_ghcr_fallback=1" || fail "RN1a': breakdown missing app_ghcr_fallback=1; got $G6_LAST"
g6 "RN1b: app_ghcr_served=2, all else healthy -> exit 1 FAIL(retired-names)" \
  1 "FAIL(retired-names)" "${HEALTHY/app_ghcr_served=0/app_ghcr_served=2}" CLOSED 200 "" yes COMPLETED
[[ "$G6_LAST" == *"app_ghcr_served=2"* ]] && pass "RN1b': the breakdown names app_ghcr_served=2" || fail "RN1b': breakdown missing app_ghcr_served=2; got $G6_LAST"
g6 "RN1c: inngest_ghcr_fallback=1, all else healthy -> exit 1 FAIL(retired-names)" \
  1 "FAIL(retired-names)" "${HEALTHY/inngest_ghcr_fallback=0/inngest_ghcr_fallback=1}" CLOSED 200 "" yes COMPLETED
[[ "$G6_LAST" == *"inngest_ghcr_fallback=1"* ]] && pass "RN1c': the breakdown names inngest_ghcr_fallback=1" || fail "RN1c': breakdown missing inngest_ghcr_fallback=1; got $G6_LAST"
# RN2. The string guard before the arithmetic: a 500 on one retired query is TRANSIENT, never a
#      counted zero (a false PASS over the very boots this arm exists to see).
g6 "RN2: a retired-name query 500s -> exit 2 TRANSIENT at its own guard" \
  2 "'retired:inngest_ghcr_fallback' failed" "$HEALTHY" CLOSED 200 "inngest_ghcr_fallback" yes COMPLETED
# RN3. Each query is EXACTLY the bare clause (the stub matches by substring; a prefixed query —
#      which would match zero events forever — still answers there).
g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" yes COMPLETED >/dev/null
if exact_query 'app_ghcr_fallback' 'stage:"app_ghcr_fallback"' \
   && exact_query 'app_ghcr_served' 'stage:"app_ghcr_served"' \
   && exact_query 'inngest_ghcr_fallback' 'stage:"inngest_ghcr_fallback"'; then
  pass "RN3: the three retired-name queries are exactly the bare stage:\"<name>\" clauses"
else
  fail "RN3: a retired-name query is not its exact bare clause"
fi
# RN4. The block itself: exactly the three whole query strings, and a runtime floor of 3 (the
#      same emptied-array-sums-to-zero hazard the FAIL_QUERIES floor guards).
RETIRED_BODY="$(awk '/^declare -A RETIRED_QUERIES=\(/{f=1;next} f&&/^\)/{exit} f' "$SOAK")"
if [[ "$RETIRED_BODY" == "  [app_ghcr_fallback]='stage:\"app_ghcr_fallback\"'
  [app_ghcr_served]='stage:\"app_ghcr_served\"'
  [inngest_ghcr_fallback]='stage:\"inngest_ghcr_fallback\"'" ]] \
   && grep -qxF 'if (( ${#RETIRED_QUERIES[@]} != 3 )); then' "$SOAK"; then
  pass "RN4: RETIRED_QUERIES is exactly the three bare retired-name queries, with a runtime floor of 3"
else
  fail "RN4: RETIRED_QUERIES block / floor not as pinned: ${RETIRED_BODY:-<empty>}"
fi
# RN5. Mutation: delete the whole arm (queries, loop and FAIL branch). RN1c's fixture must then
#      stop FAILing on retired-names.
g6_mutant "RN5: delete the RETIRED-NAMES arm" \
  '/^declare -A RETIRED_QUERIES=(/,/^done$/d; /^if (( RETIRED_TOTAL > 0 )); then$/,/^fi$/d' \
  1 "FAIL(retired-names)" "${HEALTHY/inngest_ghcr_fallback=0/inngest_ghcr_fallback=1}" CLOSED 200 "" yes COMPLETED

echo "== #8036 1d: an overridden START is disclosed on the verdict line =="

# OV1. An explicit ZOT_SOAK_START skips the #8660 anchor, so the verdict must say so — on PASS...
g6 "OV1: ZOT_SOAK_START override -> the PASS line carries 'START overridden (anchor check skipped)'" \
  0 "START overridden (anchor check skipped)" "$HEALTHY" CLOSED 200 "" yes COMPLETED
[[ "$G6_LAST" == *"out=PASS"* ]] && pass "OV1': the override note is appended; the line still leads with PASS" || fail "OV1': override PASS line must still start with PASS; got $G6_LAST"
# OV2. ...and on a FAIL line.
g6 "OV2: ZOT_SOAK_START override -> a FAIL line carries the override note too" \
  1 "START overridden (anchor check skipped)" "${HEALTHY/app_zot=3/app_zot=0}" CLOSED 200 "" yes COMPLETED
# OV3. The DEFAULT (sweeper) path must NOT carry it — the anchor ran.
if SOAK_START_OVERRIDE=__UNSET__ g6_row 0 "PASS" "$HEALTHY" CLOSED 200 "" yes COMPLETED \
   && [[ "$G6_LAST" != *"START overridden"* ]]; then
  pass "OV3: default START (anchor checked) -> no override note on the verdict"
else
  fail "OV3: the default-START verdict must not claim an override; got $G6_LAST"
fi
# OV4. Mutation: drop the note's assignment. OV1's row must then go RED.
g6_mutant "OV4: delete the START_NOTE override assignment" \
  '/^\[\[ -n "\${ZOT_SOAK_START:-}" \]\] && START_NOTE=/d' \
  0 "START overridden (anchor check skipped)" "$HEALTHY" CLOSED 200 "" yes COMPLETED

echo "== #8036 1c/1d: FAIL_QUERIES cardinality, floor parity, retired operands =="

# The FAIL set's CARDINALITY, asserted against BOTH declarations that carry it — the array and the
# runtime floor literal — and against each other. The defect this catches is the one the floor
# exists for and cannot catch alone: dropping an operand without moving the floor makes every
# sweep a permanent `exit 2` TRANSIENT, which the sweeper only discovers at runtime, a day later,
# as a comment on the tracker. Read both numbers from the SOURCE, never restated here.
# 5 -> 4 (#8036 1c, ghcr-fallback) -> 2 (#8036 1d, app_ghcr_* retired, freshboot renamed).
SOAK_N_QUERIES="$(awk '/^declare -A FAIL_QUERIES=\(/{f=1;next} f&&/^\)/{exit} f&&/^[[:space:]]*\[[a-z]+\]=/{n++} END{print n+0}' "$SOAK")"
SOAK_FLOOR_LIT="$(sed -nE 's/^if \(\( \$\{#FAIL_QUERIES\[@\]\} != ([0-9]+) \)\); then$/\1/p' "$SOAK" | head -1)"
if [[ "$SOAK_N_QUERIES" == "2" && "$SOAK_FLOOR_LIT" == "2" ]]; then
  pass "#8036 1d: FAIL_QUERIES declares 2 signals and the runtime floor agrees (array=$SOAK_N_QUERIES floor=$SOAK_FLOOR_LIT)"
else
  fail "#8036 1d: FAIL_QUERIES cardinality/floor parity broken (array=${SOAK_N_QUERIES:-<unparsed>} floor=${SOAK_FLOOR_LIT:-<unparsed>}, both must be 2)"
fi

# The two members, as WHOLE query strings (the prefix trap: bare stage: queries only).
if grep -qxF "  [gate]='feature:supply-chain op:image-pull registry:\"zot-gate-degraded\"'" "$SOAK" \
   && grep -qxF "  [freshboot]='stage:\"inngest_pull_fatal\"'" "$SOAK"; then
  pass "#8036 1d: FAIL_QUERIES is exactly [gate]=registry:\"zot-gate-degraded\" (prefixed) + [freshboot]=stage:\"inngest_pull_fatal\" (bare)"
else
  fail "#8036 1d: FAIL_QUERIES members are not the two pinned whole query strings: $SOAK_ARRAY_BODY"
fi

# The retired operands must be gone from the EXECUTABLE soak, not merely from the array. The header
# names them on purpose (the retired list), so scan code lines only — comment lines stripped — and
# exempt EXACTLY the RETIRED_QUERIES block, the one place a code line may still name them (it
# COUNTS them; it is pinned to exactly three whole query strings by the RN rows below).
SOAK_CODE="$(awk '/^declare -A RETIRED_QUERIES=\(/{f=1;next} f&&/^\)/{f=0;next} !f' "$SOAK" | grep -vE '^[[:space:]]*#')"
retired_hits=""
for tok in 'ghcr-fallback' 'app_ghcr_fallback' 'app_ghcr_served' 'inngest_ghcr_fallback'; do
  [[ "$SOAK_CODE" == *"$tok"* ]] && retired_hits="$retired_hits $tok"
done
if [[ -z "$retired_hits" && "$SOAK_ARRAY_BODY" == *"zot-gate-degraded"* && "$SOAK_ARRAY_BODY" == *"inngest_pull_fatal"* && $(printf '%s\n' "$SOAK_CODE" | wc -l) -gt 100 ]]; then
  pass "#8036 1c/1d: no retired operand (ghcr-fallback, app_ghcr_*, inngest_ghcr_fallback) on any soak code line; both survivors present"
else
  fail "#8036 1c/1d: retired operand(s) on a soak code line:${retired_hits:- <none>} (or a survivor missing / code scan vacuous)"
fi

# Assertion floor: a deleted row must red. Literal adjacent to its `if` (guard-vacuity-floor).
# Raised 30 -> 32 in the SAME edit that added the two rows above (a floor left below the count it
# measures is slack, and slack in a floor is how many rows can be deleted before it notices).
# Raised 32 -> 36 in the SAME edit that added the four #8651 web-blocker rows (3a-3d).
# Raised 36 -> 55 in the SAME edit as #8036 1d: -3 restated rows (the <= cutover START row, the
# 4-signal cardinality row, the ghcr-fallback-only residual row), +22 new (row 4 split per member,
# the retired-name G6 row, WF1-WF5 + WF1b, G3 + its three in-suite mutants, MA1-MA5 + MA1b + MA2b,
# the 2-signal cardinality, whole-query and code-line residual rows).
# Raised 55 -> 70 in the SAME edit that added the RETIRED-NAMES arm and the START-override note:
# +15 = RN1a-c and their breakdown rows (6), RN2-RN5 (4, RN5 an in-suite mutant), OV1, OV1',
# OV2, OV3 and the OV4 in-suite mutant (5).
SOAK_MIN_PASSES=70
if [[ "$passes" -lt $SOAK_MIN_PASSES ]]; then
  printf 'FATAL: only %s passing assertions ran, expected at least %s — a row was deleted\n' "$passes" "$SOAK_MIN_PASSES" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf '\nFAILED: %d assertion(s)\n' "$fails" >&2
  exit 1
fi
printf '\nOK: all soak arm exit codes correct\n'
