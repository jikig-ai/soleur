#!/usr/bin/env bash
# Exit-code guards for tenant-outer-wrap-soak-5863.sh (#5863 / #9797): the
# PASS gate must be bound to the LATEST verdict (canary_infra_error holds
# consecutive_pass, so counters alone must not promote) and to a FRESH
# checked_at (a canary that stopped reporting is stale, not proven).
#
# STUB. `curl` on PATH answers a fixture deploy-status body; env secrets are
# dummy values (the script only needs them non-empty).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/tenant-outer-wrap-soak-5863.sh"
fails=0

say() { printf '%s\n' "$*"; }
check() { # check <name> <want_rc> <got_rc>
  if [ "$3" = "$2" ]; then say "ok   $1"; else say "FAIL $1 — want rc=$2 got rc=$3"; fails=$((fails+1)); fi
}

FX="$(mktemp -d)"
trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/bin"
cat > "$FX/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Last positional arg is the URL; answer the fixture body + HTTP_STATUS line.
cat "$SOAK_FX_BODY"
printf '\nHTTP_STATUS:%s\n' "${SOAK_FX_STATUS:-200}"
STUB
chmod +x "$FX/bin/curl"

NOW=$(date +%s)

run_probe() { # run_probe <body-file> [http-status]
  local body="$1" status="${2:-200}" rc=0
  SOAK_FX_BODY="$body" SOAK_FX_STATUS="$status" \
    WEBHOOK_DEPLOY_SECRET=dummy CF_ACCESS_CLIENT_ID=dummy CF_ACCESS_CLIENT_SECRET=dummy \
    PATH="$FX/bin:$PATH" bash "$PROBE" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

write_body() { # write_body <name> <verdict> <consec> <first> <checked>
  cat > "$FX/$1.json" <<JSON
{"outer_wrap_canary":{"verdict":"$2","reason":"ok","sdk_version":"2.1.284","checked_at":$5,"consecutive_pass":$3,"first_pass_at":$4}}
JSON
}

# 1. Current-green + counters met → PASS (0).
write_body green pass 6 "$((NOW - 4*86400))" "$((NOW - 3600))"
check "green verdict + ≥5 greens + ≥3d span + fresh → PASS(0)" 0 "$(run_probe "$FX/green.json")"

# 2. Latest verdict is an infra flake but counters say soak-complete →
#    TRANSIENT(2), never PASS — the held counters must not promote.
write_body flake canary_infra_error 6 "$((NOW - 4*86400))" "$((NOW - 3600))"
check "infra-flake latest verdict + complete counters → TRANSIENT(2)" 2 "$(run_probe "$FX/flake.json")"

# 3. sandbox_broken → FAIL(1).
write_body broken sandbox_broken 6 "$((NOW - 4*86400))" "$((NOW - 3600))"
check "sandbox_broken → FAIL(1)" 1 "$(run_probe "$FX/broken.json")"

# 4. Green + complete counters but checked_at is 8 days stale → TRANSIENT(2)
#    (the canary stopped reporting; a stale ledger is not a proven one).
write_body stale pass 6 "$((NOW - 4*86400))" "$((NOW - 8*86400))"
check "stale checked_at → TRANSIENT(2)" 2 "$(run_probe "$FX/stale.json")"

# 5. Body lacks .outer_wrap_canary → TRANSIENT(2).
cat > "$FX/missing.json" <<'JSON'
{"sandbox_canary":{"verdict":"pass"}}
JSON
check "missing .outer_wrap_canary → TRANSIENT(2)" 2 "$(run_probe "$FX/missing.json")"

# 6. HTTP 500 → TRANSIENT(2).
write_body http500 pass 6 "$((NOW - 4*86400))" "$((NOW - 3600))"
check "HTTP 500 → TRANSIENT(2)" 2 "$(run_probe "$FX/http500.json" 500)"

# 7. Green verdict but counters short → TRANSIENT(2).
write_body short pass 2 "$((NOW - 86400))" "$((NOW - 3600))"
check "green but <5 greens → TRANSIENT(2)" 2 "$(run_probe "$FX/short.json")"

echo ""
echo "=== Results: $((7 - fails))/7 passed, $fails failed ==="
if [[ "$fails" -gt 0 ]]; then exit 1; fi
