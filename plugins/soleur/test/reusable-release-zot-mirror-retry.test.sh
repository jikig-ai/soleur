#!/usr/bin/env bash
# Verifies the non-blocking + bounded-retry + degraded-signal behavior of the
# "Mirror image GHCR→zot" step in .github/workflows/reusable-release.yml (#6274).
#
# Background: the zot mirror is a SECONDARY/shadow registry copy during the
# ADR-096 soak (GHCR stays primary + break-glass; the pull side does an atomic
# GHCR fallback on any zot miss). A single `connection reset by peer` mid
# blob-upload over the multi-hop CF-tunnel bridge was failing the whole
# `release / release` job even though the deploy already succeeded. The fix
# makes the mirror step non-release-blocking: `continue-on-error: true` (belt) +
# an inner `set -uo pipefail` shell whose every failure path exits 0
# (suspenders), wraps the network ops in a bounded `retry` (self-heal transient
# resets), and emits a `mirror_status` output + `::warning::` + step summary +
# Slack line so a persistent miss is loud, never silently swallowed.
#
# This test removes crane/cosign/curl/the network from the assertion path by
# executing the REAL mirror `run:` block (extracted verbatim from the workflow)
# under deterministic stubs on PATH, exactly like the sibling
# reusable-release-idempotency.test.sh convention. Run via:
#   bash plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}
assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc -> got '$got', want '$want'"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extract a step's `run:` block verbatim from the workflow (dedented to the
# block-scalar base indent). Same helper as reusable-release-idempotency.test.sh
# — index() (literal substring), not a `$0 ~` regex: the step name contains
# regex metachars ("(crane)", "→") a dynamic regex would mis-handle.
# ---------------------------------------------------------------------------
extract_run_block() {
  local step_name="$1"
  awk -v target="$step_name" '
    index($0, "- name: " target) && /^[[:space:]]*- name: / { instep=1; next }
    instep && /^[[:space:]]*- name: / { exit }
    instep && /^[[:space:]]*run: \|/ { inrun=1; next }
    inrun {
      lines[n++] = $0
      if ($0 !~ /^[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        if (base == 0 || RLENGTH < base) base = RLENGTH
      }
    }
    END { for (i = 0; i < n; i++) print substr(lines[i], base + 1) }
  ' "$WF"
}

MIRROR_BLOCK="$TMP/mirror.sh"
extract_run_block "Mirror image GHCR→zot (crane) + cosign-sign the zot digest" > "$MIRROR_BLOCK"

if [[ ! -s "$MIRROR_BLOCK" ]]; then
  fail "could not extract the mirror run block from $WF"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Deterministic stubs. The install prelude (curl/sha256sum/sudo/tar) is
# no-op'd so the test exercises only the retry + degraded-signal logic; `sleep`
# is no-op'd so the retry backoff does not add real wall-clock. `crane copy`
# behavior is driven by MOCK_CRANE_MODE (always_ok | always_fail | fail_once)
# and every `copy` invocation is counted to $MOCK_CRANE_COUNT.
# ---------------------------------------------------------------------------
STUB_DIR="$TMP/bin"
mkdir -p "$STUB_DIR"
for c in curl sha256sum sudo tar sleep cosign; do
  cat > "$STUB_DIR/$c" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_DIR/$c"
done
cat > "$STUB_DIR/crane" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "copy" ]]; then
  c=0
  [[ -f "$MOCK_CRANE_COUNT" ]] && c=$(cat "$MOCK_CRANE_COUNT")
  c=$((c + 1)); echo "$c" > "$MOCK_CRANE_COUNT"
  case "${MOCK_CRANE_MODE:-always_ok}" in
    always_fail) exit 1 ;;
    fail_once)   [[ "$c" -eq 1 ]] && exit 1 || exit 0 ;;
    *)           exit 0 ;;
  esac
fi
exit 0
STUB
chmod +x "$STUB_DIR/crane"

# Run the extracted mirror block once; echo "<rc> <mirror_status> <warn|nowarn> <crane_copies>".
run_mirror() {
  local mode="$1"
  local out="$TMP/ghout.$RANDOM" summary="$TMP/ghsum.$RANDOM"
  local log="$TMP/log.$RANDOM" count="$TMP/cranecount.$RANDOM"
  : > "$out"; : > "$summary"; : > "$count"
  local rc
  MOCK_CRANE_MODE="$mode" \
  MOCK_CRANE_COUNT="$count" \
  GITHUB_OUTPUT="$out" \
  GITHUB_STEP_SUMMARY="$summary" \
  IMAGE="ghcr.io/jikig-ai/soleur-web-platform" \
  DIGEST="sha256:deadbeef" \
  VERSION="1.2.3" \
  COMMIT_SHA="abc123def" \
  PATH="$STUB_DIR:$PATH" \
    bash "$MIRROR_BLOCK" > "$log" 2>&1
  rc=$?
  local status warn copies
  status=$(grep -E '^mirror_status=' "$out" | tail -1 | cut -d= -f2)
  if grep -q '::warning::' "$log"; then warn=warn; else warn=nowarn; fi
  copies=$(cat "$count" 2>/dev/null || echo 0)
  echo "$rc ${status:-<unset>} $warn ${copies:-0}"
}

echo "=== reusable-release zot-mirror non-blocking + retry tests ==="
echo ""

# T1 — persistent failure: every crane copy fails. The retry loop runs exactly
# 3 attempts on the first tag, then the step reports degraded and exits 0 (the
# release job must NOT red on a secondary-mirror miss).
echo "T1: persistent failure -> 3 attempts, mirror_status=degraded, ::warning::, exit 0"
assert_eq "persistent fail" "$(run_mirror always_fail)" "0 degraded warn 3"

# T2 — transient self-heal: crane fails the first attempt then succeeds. No
# degraded signal; the mirror completes clean.
echo "T2: transient self-heal -> mirror_status=ok, exit 0, no ::warning::"
out2="$(run_mirror fail_once)"
assert_eq "transient rc/status/warn" "$(echo "$out2" | cut -d' ' -f1-3)" "0 ok nowarn"

# T3 — happy path: crane succeeds first try for all three tags.
echo "T3: happy path -> mirror_status=ok, exit 0, no ::warning::"
out3="$(run_mirror always_ok)"
assert_eq "happy rc/status/warn" "$(echo "$out3" | cut -d' ' -f1-3)" "0 ok nowarn"

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
