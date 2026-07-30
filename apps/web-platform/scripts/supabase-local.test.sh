#!/usr/bin/env bash
# Tests for supabase-local.sh — the loopback-binding wrapper + assertion gate
# for the local Supabase dev stack (ADR-153).
#
# Run via:  bash apps/web-platform/scripts/supabase-local.test.sh
#
# Registration: scripts/test-all.sh:560 globs apps/web-platform/scripts/*.test.sh,
# so this suite runs on every full-suite run. It MUST therefore pass with no
# Docker daemon and no stack running — every docker/ss call is PATH-shimmed.
#
# Isolation: each case prepends a mktemp dir to PATH holding a fake `docker`
# whose output is driven by env vars. No real daemon is ever contacted.

set -euo pipefail

# scripts/test-all.sh and run-registered-suites.sh default TMPDIR to /var/tmp;
# a DIRECT invocation (the inner loop while editing) inherits the machine-global
# 4 GiB /tmp tmpfs shared with sibling worktrees. Default it here so this
# suite's verdicts are not a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/supabase-local.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found or not executable" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# ---------------------------------------------------------------------------
# Fake `docker`. Behaviour is keyed on the subcommand:
#   ps      -> prints $DOCKER_PS_OUT   (one container id per line; may be empty)
#   inspect -> prints $DOCKER_INSPECT_OUT (the .NetworkSettings.Ports JSON)
#   network -> prints $DOCKER_NETWORK_OUT
# Exits $DOCKER_EXIT (default 0) so the daemon-unreachable branch is drivable.
# ---------------------------------------------------------------------------
make_fake_docker() {
  local dir="$1"
  cat > "$dir/docker" <<'FAKE'
#!/usr/bin/env bash
: "${DOCKER_PS_OUT:=}"
: "${DOCKER_INSPECT_OUT:={}}"
: "${DOCKER_NETWORK_OUT:=}"
: "${DOCKER_EXIT:=0}"
if [[ "${DOCKER_EXIT}" != "0" ]]; then
  echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock." >&2
  exit "${DOCKER_EXIT}"
fi
case "${1:-}" in
  ps)      printf '%s' "$DOCKER_PS_OUT"; [[ -n "$DOCKER_PS_OUT" ]] && printf '\n' ;;
  inspect) printf '%s\n' "$DOCKER_INSPECT_OUT" ;;
  network) printf '%s\n' "$DOCKER_NETWORK_OUT" ;;
  *)       : ;;
esac
exit 0
FAKE
  chmod +x "$dir/docker"
}

# Reset every fixture variable to its default.
#
# LOAD-BEARING: `VAR=x res=$(run_assert)` is an ASSIGNMENT-ONLY command, so bash
# makes VAR persist as a shell variable rather than scoping it to one command.
# Without this reset, T6's DOCKER_EXIT=1 leaks into T7/T8 and they report
# "docker unreachable" instead of exercising their own fixture — two tests
# silently measuring the wrong thing. Every case calls this first.
reset_fixture() {
  DOCKER_PS_OUT=""
  DOCKER_INSPECT_OUT='{}'
  DOCKER_EXIT="0"
}

# Run `supabase-local.sh assert` in an isolated env with the fake docker.
# Echoes "<exit-code>|<output>" so callers can assert on both.
run_assert() {
  local d out rc
  d="$(mktemp -d -t supabase-local-test.XXXXXXXX)" || { echo "SETUP FAILURE: mktemp" >&2; exit 2; }
  make_fake_docker "$d"
  set +e
  out=$(env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR" \
          DOCKER_PS_OUT="${DOCKER_PS_OUT:-}" \
          DOCKER_INSPECT_OUT="${DOCKER_INSPECT_OUT:-{\}}" \
          DOCKER_EXIT="${DOCKER_EXIT:-0}" \
          bash "$SCRIPT" assert 2>&1)
  rc=$?
  set -e
  rm -rf "$d"
  printf '%s|%s' "$rc" "$out"
}

# ---------------------------------------------------------------------------
# T1 — wildcard IPv4 (0.0.0.0) MUST be detected as EXPOSED (exit 1).
#      This is the exact live state that motivated ADR-153.
# ---------------------------------------------------------------------------
echo "T1: wildcard IPv4 0.0.0.0 -> EXPOSED"
reset_fixture
DOCKER_PS_OUT="c1" \
DOCKER_INSPECT_OUT='{"5432/tcp":[{"HostIp":"0.0.0.0","HostPort":"54322"}]}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 on 0.0.0.0"; else fail "expected exit 1, got $rc ($out)"; fi
if grep -Eq '0\.0\.0\.0' <<<"$out"; then pass "names the offending bind address"; else fail "output does not name 0.0.0.0: $out"; fi

# ---------------------------------------------------------------------------
# T2 — wildcard IPv6 (::) MUST be detected. The plan's measured probe showed
#      the IPv4-named docker option removes it, but the GATE must still catch
#      it — otherwise a half-fix reads as clean.
# ---------------------------------------------------------------------------
echo "T2: wildcard IPv6 :: -> EXPOSED"
reset_fixture
DOCKER_PS_OUT="c1" \
DOCKER_INSPECT_OUT='{"5432/tcp":[{"HostIp":"::","HostPort":"54322"}]}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 on ::"; else fail "expected exit 1, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T3 — loopback-only is the PASS state (exit 0).
# ---------------------------------------------------------------------------
echo "T3: 127.0.0.1 only -> OK"
reset_fixture
DOCKER_PS_OUT="c1" \
DOCKER_INSPECT_OUT='{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"54322"}]}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 on 127.0.0.1"; else fail "expected exit 0, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T4 — null port entries. 6 of 11 supabase containers report e.g.
#      "8080/tcp": null (declared but unpublished). A naive
#      `published | length` treats null as 0 and is fine, but a naive
#      iteration crashes or mis-reads. Null must be SKIPPED, not flagged.
# ---------------------------------------------------------------------------
echo "T4: null port entries are skipped, not flagged"
reset_fixture
DOCKER_PS_OUT="c1" \
DOCKER_INSPECT_OUT='{"8080/tcp":null,"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"54322"}]}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "null entry ignored, exit 0"; else fail "expected exit 0, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T5 — zero containers (no stack running) is NOT a failure. The gate is a
#      binding assertion, not a liveness check; SessionStart must stay silent.
# ---------------------------------------------------------------------------
echo "T5: zero containers -> OK, silent"
reset_fixture
DOCKER_PS_OUT="" \
DOCKER_INSPECT_OUT='{}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 with no stack"; else fail "expected exit 0, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T6 — docker unreachable MUST be its own exit code (2), never conflated with
#      "loopback-only". An unreachable daemon is UNKNOWN, not SAFE — the
#      empty-query-is-not-absence rule applied to a security gate.
# ---------------------------------------------------------------------------
echo "T6: docker unreachable -> exit 2 (UNKNOWN, not OK)"
reset_fixture
DOCKER_PS_OUT="" \
DOCKER_EXIT="1" \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "2" ]]; then pass "exit 2 on unreachable daemon"; else fail "expected exit 2, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T7 — the PROXY TRAP. HostConfig.PortBindings reports an EMPTY HostIp for
#      both the wildcard and the loopback-bound state, so a gate reading it
#      cannot tell them apart. NetworkSettings.Ports is the resolved view and
#      is what the gate must read. This fixture is the wildcard state as
#      NetworkSettings.Ports renders it (HostIp "0.0.0.0"), asserting the gate
#      does NOT read an empty-HostIp proxy as safe.
# ---------------------------------------------------------------------------
echo "T7: empty HostIp (the PortBindings proxy shape) is not treated as safe"
reset_fixture
DOCKER_PS_OUT="c1" \
DOCKER_INSPECT_OUT='{"5432/tcp":[{"HostIp":"","HostPort":"54322"}]}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "empty HostIp -> EXPOSED (fail-closed)"; else fail "expected exit 1, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T8 — multiple containers: one clean, one exposed. The verdict must be
#      EXPOSED. A gate that stops at the first clean container fails open.
# ---------------------------------------------------------------------------
echo "T8: mixed containers -> EXPOSED (no early-exit fail-open)"
reset_fixture
DOCKER_PS_OUT="c1
c2" \
DOCKER_INSPECT_OUT='{"5432/tcp":[{"HostIp":"0.0.0.0","HostPort":"54322"}]}' \
  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 with an exposed container present"; else fail "expected exit 1, got $rc ($out)"; fi

# ---------------------------------------------------------------------------
# T9 — --help must work with no docker at all (documentation path).
# ---------------------------------------------------------------------------
echo "T9: --help works without docker"
set +e
help_out=$(env -i PATH="/usr/bin:/bin" HOME="$HOME" bash "$SCRIPT" --help 2>&1)
help_rc=$?
set -e
if [[ "$help_rc" == "0" ]]; then pass "--help exits 0"; else fail "--help exit $help_rc"; fi
if grep -Eq 'assert' <<<"$help_out"; then pass "--help documents assert"; else fail "--help omits assert"; fi

# ---------------------------------------------------------------------------
# T10 — the wrapper must place --network-id BEFORE "$@" so that subcommands
#       using `--` passthrough still work. Assert on the syntactic construct.
# ---------------------------------------------------------------------------
echo "T10: --network-id precedes \"\$@\" in the exec line"
if grep -Eq -- '--network-id[^|]*"\$@"' "$SCRIPT"; then
  pass "--network-id appears before \"\$@\""
else
  fail "exec line does not place --network-id before \"\$@\""
fi

echo ""
echo "supabase-local.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
