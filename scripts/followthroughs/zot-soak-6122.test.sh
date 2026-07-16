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
# WHAT THIS GUARDS: the soak authorizes ADR-096 5.3-5.5, which rotates AND REVOKES the GHCR
# PAT — irreversible, no rollback. Every assertion here is about which exit code an arm
# returns, because the exit code IS the authorization artifact. The cardinal sin is exit 0.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOAK="$HERE/zot-soak-6122.sh"
fails=0
GH_ARGV_SINK="$(mktemp)"
trap 'rm -f "$GH_ARGV_SINK"' EXIT
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

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
if [[ "$STUB_GH_STATE" == "__UNREADABLE__" ]]; then exit 1; fi
printf '{"state":"%s","stateReason":"%s"}\n' "$STUB_GH_STATE" "$STUB_GH_REASON"
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
  local counts_spec="$1" gh_state="$2" http_code="${3:-200}" fail_url_substr="${4:-}" inngest_fixed="${5:-no}" gh_reason="${6:-COMPLETED}"
  local d out rc soak="$SOAK"
  d="$(mktemp -d)"
  if [[ "$inngest_fixed" == "yes" ]]; then
    mkdir -p "$d/repo/scripts/followthroughs" "$d/repo/apps/web-platform/infra"
    cp "$SOAK" "$d/repo/scripts/followthroughs/"
    cat > "$d/repo/apps/web-platform/infra/cloud-init-inngest.yml" <<'FIXED'
# Synthetic fixture: the dedicated inngest host AFTER #6500 is fixed — zot-primary with a
# GHCR fallback, reporting on the Sentry stage: schema. Synthesized, never captured.
    if [ -n "$ZURL" ] && curl -s -o /dev/null --max-time 3 "http://$ZURL/v2/"; then
      IREF="$ZURL/jikig-ai/soleur-inngest-bootstrap:v1.1.19"
    fi
    soleur-boot-emit inngest_zot info
FIXED
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
  : > "$GH_ARGV_SINK"
  out="$(PATH="$d:$PATH" SENTRY_AUTH_TOKEN=stub GH_TOKEN=stub \
        STUB_GH_STATE="$gh_state" STUB_GH_REASON="$gh_reason" STUB_GH_ARGV="$GH_ARGV_SINK" \
        ZOT_SOAK_START="2026-07-01T00:00:00" bash "$soak" 2>&1)"; rc=$?
  rm -rf "$d"
  printf '%s|%s' "$rc" "$out"
}

# Query substrings that identify each signal in the request URL (percent-encoded by the soak,
# so match on the stage NAME which survives encoding).
Q_ZOTWEB='image%3A%22web%22'
Q_ZOTING='image%3A%22inngest%22'

# A "healthy fleet" baseline: no fallbacks, sample satisfied, denominator satisfied.
HEALTHY="ghcr-fallback=0;zot-gate-degraded=0;inngest_ghcr_fallback=0;app_ghcr_fallback=0;app_ghcr_served=0;app_zot=3;$Q_ZOTWEB=5;$Q_ZOTING=5"

echo "== AC7: the arms return the right exit codes =="

# 1. Dark beacon: zero fallbacks, sample fine, but NO zot-served fresh boot.
#    MUST be exit 1 (FAIL) — never 0, never 2. This is the whole denominator.
r="$(run_soak "ghcr-fallback=0;zot-gate-degraded=0;inngest_ghcr_fallback=0;app_ghcr_fallback=0;app_ghcr_served=0;app_zot=0;$Q_ZOTWEB=5;$Q_ZOTING=5" CLOSED)"
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

# 4. A real fallback still FAILs, and the per-signal breakdown still prints (the arm the
#    denominator must not have displaced — an operator hitting a real fallback needs it).
r="$(run_soak "app_ghcr_served=2;ghcr-fallback=0;zot-gate-degraded=0;inngest_ghcr_fallback=0;app_ghcr_fallback=0;app_zot=3;$Q_ZOTWEB=5;$Q_ZOTING=5" CLOSED)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "1" && "$out" == *"app-served=2"* ]]; then
  pass "app_ghcr_served>0 -> exit 1 FAIL with per-signal breakdown incl. app-served"
else
  fail "app-served fallback must exit 1 and print the breakdown; got rc=$rc out=$out"
fi

# 4b. The insufficient-sample arm. It carries 8 lines of "MUST keep exit 1 — do NOT 'fix' it to
#     TRANSIENT" and had NO test: it is the ONLY detector for the #6437 Sentry-dark mode, so a
#     well-meaning refactor to exit 2 would silently disarm it. One run_soak proves it.
r="$(run_soak "ghcr-fallback=0;zot-gate-degraded=0;inngest_ghcr_fallback=0;app_ghcr_fallback=0;app_ghcr_served=0;app_zot=3;$Q_ZOTWEB=1;$Q_ZOTING=5" CLOSED)"
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
r="$(run_soak "$HEALTHY" CLOSED 200 'app_ghcr_served')"
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
#    against the REAL repo, where cloud-init-inngest.yml still has no zot path — so a CLOSED
#    #6500 today MUST still fail. When the host is genuinely fixed this arm flips to PASS on
#    its own, which is the point: the gate tracks the code, not the issue tracker.
r="$(run_soak "$HEALTHY" CLOSED)"
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
out10="$(PATH="$d10:$PATH" SENTRY_AUTH_TOKEN=stub GH_TOKEN=stub \
        STUB_GH_STATE=CLOSED STUB_GH_REASON=COMPLETED STUB_GH_ARGV="$GH_ARGV_SINK" \
        ZOT_SOAK_START="2026-07-01T00:00:00" bash "$d10/repo/scripts/followthroughs/$(basename "$SOAK")" 2>&1)"; rc10=$?
rm -rf "$d10"
if [[ "$rc10" == "1" && "$out10" == *"blocker-closed-but-condition-unmet"* ]]; then
  pass "comments naming zot/soleur-boot-emit do NOT satisfy the corroboration grep"
else
  fail "prose must not satisfy the corroboration grep; got rc=$rc10 out=$out10"
fi

if [[ "$fails" -gt 0 ]]; then
  printf '\nFAILED: %d assertion(s)\n' "$fails" >&2
  exit 1
fi
printf '\nOK: all soak arm exit codes correct\n'
