#!/usr/bin/env bash
#
# Tests for the git-data writer-side CAS fence (git-data-pre-receive.sh).
# Exercises AC3 of epic #5274 Phase 2 PR B: a write presented at gen=N is rejected
# after any gen>N has been observed for that worktree, even with one host (no two
# real hosts required); plus the fail-closed contract (missing/unparseable inputs).
#
# Run: bash apps/web-platform/infra/git-data-pre-receive.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/git-data-pre-receive.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# Run the hook against a given GIT_DIR with the supplied lease-gen / worktree-id
# push-options. Echoes the hook's exit code. stdin is the (drained) ref list.
# Deliberately runs WITHOUT `set -e` propagation: the hook is EXPECTED to exit 1
# in reject cases, so we capture rc explicitly (test-footgun (a): an expected
# non-zero inside a naive `set -e` body aborts before the assertion).
run_hook() {
  local git_dir="$1" lease_gen="$2" worktree_id="$3"
  local -a env_args=()
  local count=0
  if [ "$lease_gen" != "__OMIT__" ]; then
    env_args+=("GIT_PUSH_OPTION_${count}=lease-gen=${lease_gen}")
    count=$((count + 1))
  fi
  if [ "$worktree_id" != "__OMIT__" ]; then
    env_args+=("GIT_PUSH_OPTION_${count}=worktree-id=${worktree_id}")
    count=$((count + 1))
  fi
  env -i PATH="$PATH" GIT_DIR="$git_dir" GIT_PUSH_OPTION_COUNT="$count" \
    "${env_args[@]}" bash "$HOOK" </dev/null >/dev/null 2>&1
  echo $?
}

# Like run_hook, but pipes newline-separated `<old> <new> <ref>` lines on stdin
# (the D0-ref namespace-ownership check reads them). Fourth arg is the ref block.
run_hook_refs() {
  local git_dir="$1" lease_gen="$2" worktree_id="$3" refs="$4"
  local -a env_args=()
  local count=0
  if [ "$lease_gen" != "__OMIT__" ]; then
    env_args+=("GIT_PUSH_OPTION_${count}=lease-gen=${lease_gen}")
    count=$((count + 1))
  fi
  if [ "$worktree_id" != "__OMIT__" ]; then
    env_args+=("GIT_PUSH_OPTION_${count}=worktree-id=${worktree_id}")
    count=$((count + 1))
  fi
  printf '%s\n' "$refs" | env -i PATH="$PATH" GIT_DIR="$git_dir" \
    GIT_PUSH_OPTION_COUNT="$count" "${env_args[@]}" bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# Read the sidecar gen for a worktree id (echoes "" if absent).
sidecar_gen() {
  local git_dir="$1" wt="$2"
  cat "${git_dir}/fence/${wt}.gen" 2>/dev/null | tr -d '[:space:]' || true
}

fresh_gitdir() {
  mktemp -d "${TMPDIR:-/tmp}/fence-gitdir.XXXXXX"
}

# --- T1: accept the FIRST push at gen=1 against an absent sidecar (stored_max=0) ---
g=$(fresh_gitdir)
rc=$(run_hook "$g" 1 primary)
if [ "$rc" = "0" ]; then pass; else fail "T1 first push gen=1 absent sidecar: expected accept (0), got $rc"; fi
if [ "$(sidecar_gen "$g" primary)" = "1" ]; then pass; else fail "T1 sidecar should be 1, got '$(sidecar_gen "$g" primary)'"; fi
rm -rf "$g"

# --- T2: accept an EQUAL-gen retry (N == stored_max), idempotent partial-push recovery ---
g=$(fresh_gitdir)
run_hook "$g" 5 primary >/dev/null   # establish stored_max=5
rc=$(run_hook "$g" 5 primary)
if [ "$rc" = "0" ]; then pass; else fail "T2 equal-gen retry: expected accept (0), got $rc"; fi
if [ "$(sidecar_gen "$g" primary)" = "5" ]; then pass; else fail "T2 sidecar should stay 5, got '$(sidecar_gen "$g" primary)'"; fi
rm -rf "$g"

# --- T3 (THE load-bearing AC3): write at N, observe N+1, attempt write at N -> REJECTED ---
g=$(fresh_gitdir)
run_hook "$g" 1 primary >/dev/null   # write at gen=1
run_hook "$g" 2 primary >/dev/null   # observe gen=2 (reclaim by a newer holder)
rc=$(run_hook "$g" 1 primary)        # stale writer still believes it holds gen=1
if [ "$rc" = "1" ]; then pass; else fail "T3 stale gen=1 after observing gen=2: expected reject (1), got $rc"; fi
# The stale push must NOT have rewound the sidecar.
if [ "$(sidecar_gen "$g" primary)" = "2" ]; then pass; else fail "T3 sidecar must stay 2 after stale reject, got '$(sidecar_gen "$g" primary)'"; fi
rm -rf "$g"

# --- T4: a higher gen advances the monotonic max ---
g=$(fresh_gitdir)
run_hook "$g" 3 primary >/dev/null
rc=$(run_hook "$g" 7 primary)
if [ "$rc" = "0" ]; then pass; else fail "T4 higher gen=7: expected accept (0), got $rc"; fi
if [ "$(sidecar_gen "$g" primary)" = "7" ]; then pass; else fail "T4 sidecar should advance to 7, got '$(sidecar_gen "$g" primary)'"; fi
rm -rf "$g"

# --- T5: missing lease-gen push-option -> REJECTED (fail-closed, never gen 0) ---
g=$(fresh_gitdir)
rc=$(run_hook "$g" __OMIT__ primary)
if [ "$rc" = "1" ]; then pass; else fail "T5 missing lease-gen: expected reject (1), got $rc"; fi
rm -rf "$g"

# --- T6: missing worktree-id push-option -> REJECTED (fail-closed) ---
g=$(fresh_gitdir)
rc=$(run_hook "$g" 1 __OMIT__)
if [ "$rc" = "1" ]; then pass; else fail "T6 missing worktree-id: expected reject (1), got $rc"; fi
rm -rf "$g"

# --- T7: unparseable sidecar -> REJECTED (fail-closed) ---
g=$(fresh_gitdir)
mkdir -p "${g}/fence"
printf 'not-a-number\n' >"${g}/fence/primary.gen"
rc=$(run_hook "$g" 5 primary)
if [ "$rc" = "1" ]; then pass; else fail "T7 unparseable sidecar: expected reject (1), got $rc"; fi
rm -rf "$g"

# --- T8: non-integer lease-gen -> REJECTED ---
g=$(fresh_gitdir)
rc=$(run_hook "$g" "1abc" primary)
if [ "$rc" = "1" ]; then pass; else fail "T8 non-integer lease-gen: expected reject (1), got $rc"; fi
rm -rf "$g"

# --- T9: path-traversal worktree-id -> REJECTED (CWE-22 defense-in-depth) ---
g=$(fresh_gitdir)
rc=$(run_hook "$g" 1 "../../etc/passwd")
if [ "$rc" = "1" ]; then pass; else fail "T9 path-traversal worktree-id: expected reject (1), got $rc"; fi
# Confirm no sidecar escaped the fence dir.
if [ ! -e "${g}/fence/../../etc/passwd.gen" ]; then pass; else fail "T9 traversal wrote outside fence dir"; fi
rm -rf "$g"

# --- T10: two distinct worktrees of one workspace keep independent gens ---
g=$(fresh_gitdir)
run_hook "$g" 4 wt-a >/dev/null
run_hook "$g" 9 wt-b >/dev/null
# wt-a at gen 4 is unaffected by wt-b advancing to 9; a gen=4 re-push on wt-a still accepts.
rc=$(run_hook "$g" 4 wt-a)
if [ "$rc" = "0" ]; then pass; else fail "T10 per-worktree isolation: wt-a gen=4 should accept, got $rc"; fi
if [ "$(sidecar_gen "$g" wt-a)" = "4" ] && [ "$(sidecar_gen "$g" wt-b)" = "9" ]; then pass; else fail "T10 sidecars: wt-a='$(sidecar_gen "$g" wt-a)' wt-b='$(sidecar_gen "$g" wt-b)' (expected 4 / 9)"; fi
rm -rf "$g"

# --- T11 (D0 namespace-ownership): worktree W writing ITS OWN namespace -> accept ---
g=$(fresh_gitdir)
rc=$(run_hook_refs "$g" 1 wt-a $'0000 1111 refs/soleur/worktrees/wt-a/heads/main\n0000 2222 refs/soleur/worktrees/wt-a/tags/v1')
if [ "$rc" = "0" ]; then pass; else fail "T11 in-namespace push (wt-a → refs/soleur/worktrees/wt-a/*): expected accept (0), got $rc"; fi
rm -rf "$g"

# --- T12 (D0 namespace-ownership): worktree W writing the CANONICAL refs/heads/* -> REJECTED ---
g=$(fresh_gitdir)
rc=$(run_hook_refs "$g" 1 wt-a $'0000 1111 refs/heads/main')
if [ "$rc" = "1" ]; then pass; else fail "T12 out-of-namespace push (wt-a → refs/heads/main, the pre-3.B clobbering refspec): expected reject (1), got $rc"; fi
# The rejected push must not have advanced wt-a's sidecar.
if [ "$(sidecar_gen "$g" wt-a)" = "" ]; then pass; else fail "T12 sidecar must be unwritten after namespace reject, got '$(sidecar_gen "$g" wt-a)'"; fi
rm -rf "$g"

# --- T13 (D0 namespace-ownership, the cross-tenant-write boundary): worktree W
#     writing a PEER worktree's namespace -> REJECTED (a compromised/buggy writer
#     cannot clobber another user even sharing the cluster-wide transport key). ---
g=$(fresh_gitdir)
rc=$(run_hook_refs "$g" 1 wt-a $'0000 1111 refs/soleur/worktrees/wt-b/heads/main')
if [ "$rc" = "1" ]; then pass; else fail "T13 peer-namespace push (wt-a → refs/soleur/worktrees/wt-b/*): expected reject (1), got $rc"; fi
rm -rf "$g"

# --- T14 (non-vacuity for the namespace check): a MIXED push (one in-namespace ref
#     + one peer-namespace ref) is rejected WHOLE — proves the loop inspects every
#     ref, not just the first. ---
g=$(fresh_gitdir)
rc=$(run_hook_refs "$g" 1 wt-a $'0000 1111 refs/soleur/worktrees/wt-a/heads/main\n0000 2222 refs/soleur/worktrees/wt-b/heads/main')
if [ "$rc" = "1" ]; then pass; else fail "T14 mixed in+peer namespace push: expected reject (1), got $rc"; fi
rm -rf "$g"

# --- Verify-the-verifier (non-vacuity guard): a hook that ALWAYS exits 0 must fail
#     the stale-reject assertion T3 — proves the suite distinguishes fence-present
#     from fence-absent, not just that the real hook happens to pass. ---
stub=$(mktemp "${TMPDIR:-/tmp}/fence-stub.XXXXXX.sh")
printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 || true\nexit 0\n' >"$stub"
g=$(fresh_gitdir)
stub_rc=$(env -i PATH="$PATH" GIT_DIR="$g" GIT_PUSH_OPTION_COUNT=2 \
  GIT_PUSH_OPTION_0=lease-gen=1 GIT_PUSH_OPTION_1=worktree-id=primary \
  bash "$stub" </dev/null >/dev/null 2>&1; echo $?)
if [ "$stub_rc" = "0" ]; then pass; else fail "verify-the-verifier: always-accept stub should exit 0 on a would-be-stale push (got $stub_rc) — the test harness is broken"; fi
rm -rf "$g" "$stub"

# --- Minimum-cardinality guard: if zero assertions ran, the suite is malformed
#     (a silent set-e abort / empty loop would otherwise exit 0 with no coverage). ---
total=$((passes + fails))
if [ "$total" -lt 22 ]; then
  echo "FAIL: ran only ${total} assertions (<22) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-pre-receive: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
