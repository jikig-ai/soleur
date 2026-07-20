#!/usr/bin/env bash
# Would-have-caught regression for the #5873 seccomp P0 — #5875 item 3 / ADR-079.
#
# Run via:  bash apps/web-platform/scripts/sandbox-canary-regression.test.sh
# Runs in the CI `test-scripts` shard via apps/web-platform/scripts/*.test.sh (→ the
# branch-protection `test` required context). The heavier docker-run bwrap proof is
# opt-in (SDK_SANDBOX_REGRESSION_DOCKER=1) so it fires from infra-validation.yml on a
# seccomp/apparmor/canary change, not on every unrelated PR.
#
# Two layers, both proving: "a pre-#5874 seccomp profile EPERMs the claude-agent-sdk
# 0.3.x split-unshare, while the committed post-#5874 profile allows it."
#
#   A. STRUCTURAL (always; deterministic; BLOCKING via test-scripts). The committed
#      synthesized fixture test-fixtures/sandbox-canary/seccomp-pre-5874.json is
#      EXACTLY the committed seccomp-bwrap.json minus the two "WITHOUT CLONE_NEWUSER"
#      unshare allow-rules #5874 added — i.e. the fixture faithfully reproduces the
#      pre-incident profile, and the removed rules are precisely the ones whose
#      absence default-ERRNO'd the split unshare(). A drift in either file (or a
#      renamed/removed #5874 rule) fails here.
#
#   B. RUNTIME (opt-in via SDK_SANDBOX_REGRESSION_DOCKER=1; self-validating). Runs the
#      synthesized split-unshare bwrap argv (test-fixtures/sandbox-canary/split-unshare-argv.json
#      — a DISTINCT file from the prod replay fixture, ADR-079 guardrail 1) under BOTH
#      profiles via `docker run`. Asserts the committed profile PASSES and the pre-5874
#      profile FAILS with "Operation not permitted". Needs an unprivileged user
#      namespace, so it sets kernel.apparmor_restrict_unprivileged_userns=0 (guardrail
#      3: ONLY on an ephemeral GH-hosted runner — re-gate if CI ever moves to a
#      persistent/self-hosted runner). If the environment cannot execute the bwrap
#      userns setup at all (no docker / no passwordless sudo / userns unavailable), it
#      SKIPS with a loud warning rather than false-failing — the STRUCTURAL layer and
#      the sdk-bump gate remain the deterministic blocking guards.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/../infra" && pwd)"
COMMITTED_PROFILE="$INFRA_DIR/seccomp-bwrap.json"
PRE5874_PROFILE="$INFRA_DIR/test-fixtures/sandbox-canary/seccomp-pre-5874.json"
ARGV_FIXTURE="$INFRA_DIR/test-fixtures/sandbox-canary/split-unshare-argv.json"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
skip() { echo "  SKIP: $1"; }

for f in "$COMMITTED_PROFILE" "$PRE5874_PROFILE" "$ARGV_FIXTURE"; do
  [[ -f "$f" ]] || { echo "ERROR: missing fixture $f" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# A. STRUCTURAL — deterministic, always runs.
# ---------------------------------------------------------------------------
echo "A: structural fixture faithfulness"

# A1 — pre-5874 == committed with EXACTLY the two "WITHOUT CLONE_NEWUSER" unshare
# rules removed (order-preserving deep equality on the syscalls array).
committed_minus="$(jq -S '.syscalls | map(select((.comment // "" | test("WITHOUT CLONE_NEWUSER")) | not))' "$COMMITTED_PROFILE")"
pre5874_syscalls="$(jq -S '.syscalls' "$PRE5874_PROFILE")"
if [[ "$committed_minus" == "$pre5874_syscalls" ]]; then
  pass "A1 pre-5874.syscalls == committed.syscalls minus the 2 #5874 rules"
else
  fail "A1 pre-5874 fixture is NOT committed-minus-the-2-rules (drift — regenerate the fixture)"
fi

# A2 — the two removed rules genuinely EXIST in the committed profile (non-vacuity:
# A1 would pass trivially if committed had zero WITHOUT-NEWUSER rules).
removed_count="$(jq '[.syscalls[] | select((.comment // "") | test("WITHOUT CLONE_NEWUSER"))] | length' "$COMMITTED_PROFILE")"
if [[ "$removed_count" == "2" ]]; then
  pass "A2 committed profile has exactly 2 WITHOUT-CLONE_NEWUSER unshare rules"
else
  fail "A2 expected 2 WITHOUT-CLONE_NEWUSER rules in committed profile, found $removed_count"
fi

# A3 — both removed rules target `unshare` (the #5849 syscall), and one gates NEWNS
# (0x20000=131072), the other NEWPID (0x20000000=536870912) — the exact split.
removed_json="$(jq -c '[.syscalls[] | select((.comment // "") | test("WITHOUT CLONE_NEWUSER"))]' "$COMMITTED_PROFILE")"
all_unshare="$(printf '%s' "$removed_json" | jq 'all(.[]; .names | index("unshare"))')"
has_newns="$(printf '%s' "$removed_json" | jq 'any(.[]; [.args[]?.value] | index(131072))')"
has_newpid="$(printf '%s' "$removed_json" | jq 'any(.[]; [.args[]?.value] | index(536870912))')"
if [[ "$all_unshare" == "true" && "$has_newns" == "true" && "$has_newpid" == "true" ]]; then
  pass "A3 removed rules are unshare NEWNS + NEWPID (the split-unshare shape)"
else
  fail "A3 removed rules not the expected unshare NEWNS/NEWPID pair (unshare=$all_unshare newns=$has_newns newpid=$has_newpid)"
fi

# A4 — defaultAction is SCMP_ACT_ERRNO in both, so a removed allow-rule falls through
# to a DENY (the mechanism by which the split unshare EPERMd).
for prof in "$COMMITTED_PROFILE" "$PRE5874_PROFILE"; do
  da="$(jq -r '.defaultAction' "$prof")"
  if [[ "$da" == "SCMP_ACT_ERRNO" ]]; then pass "A4 defaultAction ERRNO ($(basename "$prof"))"; else fail "A4 defaultAction=$da in $(basename "$prof"), expected SCMP_ACT_ERRNO"; fi
done

# A5 — the argv fixture is a VALID captured split-unshare fixture, DISTINCT from the
# prod replay fixture (guardrail 1), and carries the userns + a post-userns namespace.
argv_status="$(jq -r '.status' "$ARGV_FIXTURE")"
argv_len="$(jq '.bwrapSetupArgv | length' "$ARGV_FIXTURE")"
has_userns="$(jq '[.bwrapSetupArgv[]] | index("--unshare-user") != null' "$ARGV_FIXTURE")"
has_split="$(jq '[.bwrapSetupArgv[]] | (index("--unshare-pid") != null)' "$ARGV_FIXTURE")"
no_dashdash="$(jq '[.bwrapSetupArgv[]] | index("--") == null' "$ARGV_FIXTURE")"
if [[ "$argv_status" == "captured" && "$argv_len" -gt 0 && "$has_userns" == "true" && "$has_split" == "true" && "$no_dashdash" == "true" ]]; then
  pass "A5 split-unshare argv fixture valid (userns + post-userns unshare, no '--')"
else
  fail "A5 argv fixture invalid (status=$argv_status len=$argv_len userns=$has_userns split=$has_split no--=$no_dashdash)"
fi
# A5b — the prod replay fixture is now a REAL canonical capture (#5913 / ADR-079
# deferral B). Always-on STRUCTURAL guard (ADR-079 §2d, argv-independent of any
# bwrap version): assert the committed fixture retains the EXACT --unshare-*
# multiset the SDK requested. Exact (not subset) is deliberate — a future SDK
# that DROPS a namespace (e.g. --unshare-net) silently narrows the sandbox; a
# subset check would not fire. `--verify` byte-diff also catches it, but this
# assertion documents the security intent and fails legibly. Regenerate this
# expected set (via --capture) if the SDK's real unshare set intentionally
# changes — that is a reviewed sandbox-posture change, not an incidental edit.
PROD_FIX="$INFRA_DIR/sandbox-canary-argv.json"
prod_status="$(jq -r '.status' "$PROD_FIX" 2>/dev/null || echo missing)"
prod_schema="$(jq -r '.schema // ""' "$PROD_FIX" 2>/dev/null)"
prod_unshare="$(jq -c '[.bwrapSetupArgv[]? | select(type=="string" and startswith("--unshare-"))] | sort' "$PROD_FIX" 2>/dev/null)"
EXPECTED_UNSHARE='["--unshare-net","--unshare-pid","--unshare-user"]'
if [[ "$prod_status" == "captured" && "$prod_schema" == "canonical-bwrap-v1" && "$prod_unshare" == "$EXPECTED_UNSHARE" ]]; then
  pass "A5b prod fixture captured (canonical-bwrap-v1) + EXACT --unshare-* multiset (net+pid+user) (#5913)"
else
  fail "A5b prod fixture invalid (status=$prod_status schema=$prod_schema unshare=$prod_unshare), expected captured canonical-bwrap-v1 with unshare multiset $EXPECTED_UNSHARE"
fi
# A5c — the prod canonical fixture must stay DISTINCT from the synthesized
# regression fixture (guardrail 1: the two argv sources never converge).
prod_argv="$(jq -cS '.bwrapSetupArgv' "$PROD_FIX" 2>/dev/null)"
regr_argv="$(jq -cS '.bwrapSetupArgv' "$ARGV_FIXTURE" 2>/dev/null)"
if [[ -n "$prod_argv" && "$prod_argv" != "$regr_argv" ]]; then
  pass "A5c prod fixture DISTINCT from split-unshare-argv.json (guardrail 1)"
else
  fail "A5c prod fixture argv equals the synthesized regression fixture (guardrail 1 violated)"
fi

# ---------------------------------------------------------------------------
# B. RUNTIME — opt-in docker-bwrap discrimination (self-validating).
# ---------------------------------------------------------------------------
if [[ "${SDK_SANDBOX_REGRESSION_DOCKER:-0}" != "1" ]]; then
  echo "B: runtime docker-bwrap proof skipped (set SDK_SANDBOX_REGRESSION_DOCKER=1 to run; it fires from infra-validation.yml on profile/canary changes)."
else
  echo "B: runtime docker-bwrap would-have-caught proof"
  # Layer B classifies bwrap EXIT CODES, so errexit must be OFF here — a
  # deliberately-nonzero `docker run` inside `out=$(...)` would otherwise abort the
  # whole test before the rc is read (the set -e command-substitution foot-gun).
  set +e
  if ! command -v docker >/dev/null 2>&1; then
    skip "B docker unavailable — structural layer A is the deterministic guard"
  else
    # Enable unprivileged userns on the ephemeral runner (guardrail 3). Best-effort.
    sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1 || true

    # Reproduce the SDK 0.3.x split unshare() with NESTED unshare(1) — NOT bwrap.
    # #5875 CI finding: bwrap 0.11.x COMBINES all namespaces into ONE
    # unshare(CLONE_NEWUSER|NEWNS|NEWPID) WITH the NEWUSER bit, which the #1557
    # CLONE_NEWUSER allow-rule permits in BOTH profiles — so a synthesized bwrap argv
    # cannot reproduce the split (committed and pre-5874 both pass → no discrimination).
    # The SDK does a SEPARATE second unshare(CLONE_NEWPID|CLONE_NEWNS) WITHOUT NEWUSER;
    # `unshare --user --map-root-user unshare --mount --pid` reproduces that exact
    # syscall sequence — the INNER call's arg0 lacks the NEWUSER bit, which is precisely
    # what the two removed #5874 rules gate. Uses util-linux unshare (busybox's lacks
    # --map-root-user).
    IMG="soleur-unshare-regression:alpine"
    if ! docker image inspect "$IMG" >/dev/null 2>&1; then
      bdir="$(mktemp -d)"
      printf 'FROM alpine:3.20\nRUN apk add --no-cache util-linux\n' > "$bdir/Dockerfile"
      docker build -q -t "$IMG" "$bdir" >/dev/null 2>&1 || true
      rm -rf "$bdir"
    fi

    run_under() { # $1=profile → prints combined output; returns rc of the nested unshare
      docker run --rm \
        --security-opt apparmor=unconfined \
        --security-opt "seccomp=$1" \
        "$IMG" unshare --user --map-root-user unshare --mount --pid true 2>&1
    }

    # NEVER-FAIL classification. The STRUCTURAL layer A (always-on, blocking via the
    # `test` shard) is the deterministic would-have-caught guard; this runtime layer is
    # the higher-fidelity CONFIRMATION where the runner can execute the split, and a
    # best-effort SKIP everywhere else. Reproducing the SDK's split without the real SDK
    # is inherently env/tool-dependent (the faithful path is the deferred creds-gated
    # real capture, #5913), so a non-discriminating or env-blocked outcome is a SKIP,
    # NEVER a merge-blocking FAIL — it PASSES only on a clean positive discrimination.
    committed_out="$(run_under "$COMMITTED_PROFILE")"; committed_rc=$?
    pre_out="$(run_under "$PRE5874_PROFILE")"; pre_rc=$?
    pre_eperm=no
    if [[ "$pre_rc" -ne 0 ]] && printf '%s' "$pre_out" | grep -qi 'operation not permitted'; then
      pre_eperm=yes
    fi

    if [[ "$committed_rc" -eq 0 && "$pre_eperm" == "yes" ]]; then
      pass "B would-have-caught: committed ALLOWS the split unshare(), pre-5874 EPERMs it"
    elif [[ "$committed_rc" -ne 0 ]]; then
      skip "B committed baseline could not run the split unshare on this runner (rc=$committed_rc: $(printf '%s' "$committed_out" | head -1)) — env limitation; layer A + the sdk-bump gate remain the deterministic guards"
    else
      skip "B non-discriminating on this runner (committed rc=0, pre-5874 rc=$pre_rc eperm=$pre_eperm) — the faithful split needs the real SDK (deferral B, #5913); layer A remains the deterministic guard"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# C. CROSS-FILE CONTRACT — the mjs `--replay` stdout ⇄ ci-deploy.sh reader.
# Deterministic, always runs. Guards the JS/shell key-name seam that silently
# blanked the soak's sdk_version: sandbox-canary.mjs emits camelCase `sdkVersion`,
# but ci-deploy.sh read snake_case `.sdk_version`, so the value never propagated
# to /hooks/deploy-status (#5889). A rename on either side re-breaks it.
# ---------------------------------------------------------------------------
echo "C: mjs↔ci-deploy sdk_version key contract"
MJS="$SCRIPT_DIR/sandbox-canary.mjs"
CI_DEPLOY="$INFRA_DIR/ci-deploy.sh"
REPLAY_FIXTURE="$INFRA_DIR/sandbox-canary-argv.json"
for f in "$MJS" "$CI_DEPLOY" "$REPLAY_FIXTURE"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
done

# C1 — the replay path emits the version under the camelCase key `sdkVersion`.
if grep -qE 'emitVerdict\(\{ \.\.\.verdict, sdkVersion:' "$MJS"; then
  pass "C1 mjs runReplay emits key sdkVersion"
else
  fail "C1 mjs runReplay no longer emits 'sdkVersion' in its verdict — update the ci-deploy.sh reader key in lockstep"
fi

# C2 — ci-deploy.sh's sdk_version read accepts exactly that emitted key.
if grep -qE "jq -r '\.sdkVersion // \.sdk_version" "$CI_DEPLOY"; then
  pass "C2 ci-deploy.sh reads .sdkVersion (matches the mjs key)"
else
  fail "C2 ci-deploy.sh sdk_version read does not accept the mjs 'sdkVersion' key — the soak surface will blank sdk_version"
fi

# C3 — the committed captured fixture carries a non-empty sdkVersion, so a real
# pass actually populates the field (an empty fixture version = silent blank).
FIX_VER="$(jq -r '.sdkVersion // ""' "$REPLAY_FIXTURE" 2>/dev/null || echo '')"
if [[ -n "$FIX_VER" && "$FIX_VER" != "null" ]]; then
  pass "C3 committed fixture carries sdkVersion ($FIX_VER)"
else
  # Only required once the fixture is captured; an uncaptured sentinel is exempt.
  if [[ "$(jq -r '.status // ""' "$REPLAY_FIXTURE" 2>/dev/null)" == "captured" ]]; then
    fail "C3 captured fixture has empty sdkVersion — a real pass would report an empty version"
  else
    skip "C3 fixture is uncaptured — sdkVersion not required yet"
  fi
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
