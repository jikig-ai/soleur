#!/usr/bin/env bash
# Behavioural rows for sandbox-readback-10445.sh with `curl` and `gh` stubbed on PATH (no network, no credentials).
# The property: exit 0 only when the fix PR's merge commit is contained in the deployed tag AND the canary is green;
# an unmerged PR, a tag that predates the fix, or a malformed answer is TRANSIENT, never PASS.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/sandbox-readback-10445.sh"
ROOT_TMP="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
trap 'rm -rf "$ROOT_TMP"' EXIT
STUBS="$ROOT_TMP/bin"
mkdir -p "$STUBS"
FAILURES=()
PASSES=0

# curl stub: prints $STUB_BODY then the HTTP_STATUS trailer the SUT parses.
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\nHTTP_STATUS:%s' "${STUB_BODY:-}" "${STUB_HTTP:-200}"
STUB
# gh stub: `pr view` -> $STUB_MERGE_SHA ; `api` -> $STUB_COMPARE
cat > "$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  pr) printf '%s\n' "${STUB_MERGE_SHA:-}" ;;
  api) printf '%s\n' "${STUB_COMPARE:-}" ;;
esac
STUB
chmod +x "$STUBS/curl" "$STUBS/gh"

SHA=0123456789abcdef0123456789abcdef01234567
run() { # <expected rc> <label> <body> <merge sha> <compare> [http]
  local want="$1" label="$2" body="$3" sha="$4" cmp="$5" http="${6:-200}" out rc
  out="$(PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET=s CF_ACCESS_CLIENT_ID=id CF_ACCESS_CLIENT_SECRET=sec GH_TOKEN=t \
    STUB_BODY="$body" STUB_MERGE_SHA="$sha" STUB_COMPARE="$cmp" STUB_HTTP="$http" bash "$SUT" 2>&1)"
  rc=$?
  LAST_OUT="$out"
  if [[ "$rc" == "$want" ]]; then PASSES=$((PASSES + 1)); echo "  ok: $label (rc=$rc)"; else FAILURES+=("$label: want rc=$want got rc=$rc: $out"); echo "  FAIL: $label (want $want got $rc)"; fi
}
GREEN='{"tag":"v1.2.3","sandbox_canary":{"verdict":"pass"}}'
RED='{"tag":"v1.2.3","sandbox_canary":{"verdict":"sandbox_broken"}}'

run 0 "fix contained in the deployed tag and canary green -> PASS" "$GREEN" "$SHA" behind
run 0 "merge commit IS the tag -> PASS" "$GREEN" "$SHA" identical
run 1 "fix deployed and canary broken -> FAIL" "$RED" "$SHA" behind
run 2 "PR not merged yet -> TRANSIENT even though the canary is green" "$GREEN" "" behind
run 2 "tag predates the fix (merge commit ahead of the tag) -> TRANSIENT, not PASS" "$GREEN" "$SHA" ahead
run 2 "diverged -> TRANSIENT" "$GREEN" "$SHA" diverged
run 2 "gh api returned nothing -> TRANSIENT" "$GREEN" "$SHA" ""
run 2 "deploy-status HTTP 502 -> TRANSIENT" "$GREEN" "$SHA" behind 502
run 2 "body without sandbox_canary -> TRANSIENT" '{"tag":"v1.2.3"}' "$SHA" behind
run 2 "tag that is not a release tag -> TRANSIENT" '{"tag":"main","sandbox_canary":{"verdict":"pass"}}' "$SHA" behind
run 2 "no verdict yet -> TRANSIENT" '{"tag":"v1.2.3","sandbox_canary":{"verdict":"canary_infra_error"}}' "$SHA" behind
# A forged remote value must not reach stdout with a newline or a workflow command.
run 2 "a newline/command in the verdict is reduced to a safe alphabet" '{"tag":"v1.2.3","sandbox_canary":{"verdict":"x\n::error::boom"}}' "$SHA" behind
if grep -q '::error::' <<<"$LAST_OUT" && ! grep -q "verdict='x" <<<"$LAST_OUT"; then FAILURES+=("forged workflow command reached stdout: $LAST_OUT"); fi

echo ""
echo "=== sandbox-readback-10445: $PASSES passed, ${#FAILURES[@]} failed ==="
# Floor reported directly (not through the helper it backstops): 12 rows above.
if (( PASSES + ${#FAILURES[@]} < 12 )); then printf 'FAIL: only %d rows ran (floor 12)\n' "$((PASSES + ${#FAILURES[@]}))"; exit 1; fi
if (( ${#FAILURES[@]} > 0 )); then printf 'FAIL: %s\n' "${FAILURES[@]}"; exit 1; fi
exit 0
