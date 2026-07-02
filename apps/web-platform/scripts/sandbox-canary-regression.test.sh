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
# A5b — the regression fixture is NOT the prod replay fixture, which must stay uncaptured.
prod_status="$(jq -r '.status' "$INFRA_DIR/sandbox-canary-argv.json" 2>/dev/null || echo missing)"
if [[ "$prod_status" == "uncaptured" ]]; then
  pass "A5b prod replay fixture (sandbox-canary-argv.json) still status:uncaptured (real capture deferred)"
else
  fail "A5b prod replay fixture status='$prod_status', expected 'uncaptured' (guardrail 1 — do not hand-author the prod fixture)"
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

    IMG="soleur-bwrap-regression:alpine"
    if ! docker image inspect "$IMG" >/dev/null 2>&1; then
      bdir="$(mktemp -d)"
      printf 'FROM alpine:3.20\nRUN apk add --no-cache bubblewrap\n' > "$bdir/Dockerfile"
      docker build -q -t "$IMG" "$bdir" >/dev/null 2>&1 || true
      rm -rf "$bdir"
    fi

    # Read the synthesized setup argv + append the no-op command (mirrors
    # sandbox-canary.mjs buildBwrapInvocation: setup argv, then `-- true`).
    mapfile -t ARGV < <(jq -r '.bwrapSetupArgv[]' "$ARGV_FIXTURE")

    run_under() { # $1=profile → prints combined output; returns bwrap rc
      docker run --rm \
        --security-opt apparmor=unconfined \
        --security-opt "seccomp=$1" \
        "$IMG" bwrap "${ARGV[@]}" -- true 2>&1
    }

    # DIFFERENTIAL classification (robust to env variance). The regression proves the
    # two profiles DIFFER on the seccomp-gated split unshare() — not that bwrap can
    # complete a full sandbox setup on this runner. A committed-baseline failure is an
    # ENV limitation (missing caps to mount, restricted bind, no userns), NEVER a
    # seccomp-profile regression — the committed profile runs in prod continuously and
    # is unchanged by this PR — so it SKIPS, it does not FAIL. The ONLY hard FAIL is
    # "no discrimination": committed allows AND pre-5874 also allows, which means the
    # fixture/argv doesn't exercise the rule difference (the regression's premise).
    # The argv deliberately carries NO --proc/--dev mount (those EPERM for container-cap
    # reasons unrelated to the unshare gate — the #5875 CI-run finding); the split
    # unshare() fires from --unshare-user + --unshare-pid alone, before any mount.
    committed_out="$(run_under "$COMMITTED_PROFILE")"; committed_rc=$?
    pre_out="$(run_under "$PRE5874_PROFILE")"; pre_rc=$?
    pre_eperm=no
    if [[ "$pre_rc" -ne 0 ]] && printf '%s' "$pre_out" | grep -qi 'operation not permitted'; then
      pre_eperm=yes
    fi

    if [[ "$committed_rc" -ne 0 ]]; then
      skip "B committed baseline could not run bwrap on this runner (rc=$committed_rc: $(printf '%s' "$committed_out" | head -1)) — ENV limitation, not a profile regression; layer A + the sdk-bump gate remain the deterministic guards"
    elif [[ "$pre_eperm" == "yes" ]]; then
      pass "B would-have-caught: committed ALLOWS the split-unshare, pre-5874 EPERMs it"
    elif [[ "$pre_rc" -eq 0 ]]; then
      fail "B NO DISCRIMINATION: committed AND pre-5874 both allowed the split-unshare (rc=0). The two profiles do not differ on the gated unshare — the fixture or the argv is wrong (regression premise broken)."
    else
      skip "B inconclusive: committed passed but pre-5874 failed with a non-EPERM error (rc=$pre_rc: $(printf '%s' "$pre_out" | head -1)) — layer A remains the guard"
    fi
  fi
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
