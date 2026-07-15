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
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SOAK" ]] || { echo "FATAL: soak not found at $SOAK" >&2; exit 1; }

# Build a stub dir: `curl` answers Sentry queries from a per-query count map, `gh` answers
# the blocker-state probe. Everything else resolves normally via the real PATH.
#
# COUNTS_SPEC is "<substring>=<count>" pairs; the first substring matching the request URL
# wins. HTTP_CODE lets us simulate a non-200 (the TRANSIENT sentinel path).
make_stubs() {
  local dir="$1" counts_spec="$2" gh_state="$3" http_code="${4:-200}"
  mkdir -p "$dir"
  # Mirror sentry_count's REAL contract exactly: it calls
  #   curl -sS -w '\nHTTP_STATUS:%{http_code}' ... "<url>"
  # and then splits body/status with sed. So the stub must emit the JSON body, a newline,
  # then the HTTP_STATUS: trailer — not a bare appended code.
  cat > "$dir/curl" <<STUB
#!/usr/bin/env bash
url=""
for a in "\$@"; do case "\$a" in https://*) url="\$a";; esac; done
n=0
IFS=';' read -ra pairs <<< "$counts_spec"
for p in "\${pairs[@]}"; do
  key="\${p%%=*}"; val="\${p##*=}"
  if [[ -n "\$key" && "\$url" == *"\$key"* ]]; then n="\$val"; break; fi
done
data=""
if [[ "\$n" -gt 0 ]]; then
  for ((i=0;i<n;i++)); do data="\${data}{\"title\":\"e\",\"timestamp\":\"t\"},"; done
  data="\${data%,}"
fi
printf '{"data":[%s]}\nHTTP_STATUS:%s' "\$data" "$http_code"
STUB
  cat > "$dir/gh" <<STUB
#!/usr/bin/env bash
# The soak calls: gh issue view <n> --json state --jq .state
if [[ "$gh_state" == "__UNREADABLE__" ]]; then exit 1; fi
printf '%s\n' "$gh_state"
STUB
  chmod 0755 "$dir/curl" "$dir/gh"
}

# Run the soak with stubs prepended to PATH. Echoes "<exit>|<stdout+stderr>".
run_soak() {
  local counts_spec="$1" gh_state="$2" http_code="${3:-200}"
  local d out rc
  d="$(mktemp -d)"
  make_stubs "$d" "$counts_spec" "$gh_state" "$http_code"
  out="$(PATH="$d:$PATH" SENTRY_AUTH_TOKEN=stub GH_TOKEN=stub \
        ZOT_SOAK_START="2026-07-01T00:00:00" bash "$SOAK" 2>&1)"; rc=$?
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

# 3. The only PASS: criteria hold AND the blocker is closed.
r="$(run_soak "$HEALTHY" CLOSED)"
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

echo "== AC9: no arithmetic on an unguarded count (the TRANSIENT sentinel) =="

# 5. THE HAZARD THIS PR'S OWN PLAN DOCUMENTS THREE TIMES: sentry_count echoes the bare word
#    TRANSIENT on a non-200. Arithmetic coerces that unset word to 0 — which for the
#    denominator reads as "no evidence" (a FAIL that is really a probe failure) and for a
#    counter reads as "no fallbacks" (a FALSE PASS -> PAT revoked). MUST be exit 2, never 0.
r="$(run_soak "$HEALTHY" CLOSED 500)"
rc="${r%%|*}"; out="${r#*|}"
if [[ "$rc" == "2" && "$out" == *"TRANSIENT"* ]]; then
  pass "HTTP 500 -> sentry_count yields TRANSIENT -> exit 2, never 0"
else
  fail "HTTP 500 must exit 2 TRANSIENT (never 0); got rc=$rc out=$out"
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

if [[ "$fails" -gt 0 ]]; then
  printf '\nFAILED: %d assertion(s)\n' "$fails" >&2
  exit 1
fi
printf '\nOK: all soak arm exit codes correct\n'
