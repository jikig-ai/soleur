#!/usr/bin/env bash
# Tests for supabase-local.sh — the loopback-binding wrapper + assertion gate
# for the local Supabase dev stack (ADR-153).
#
# Run via:  bash apps/web-platform/scripts/supabase-local.test.sh
#
# Registration: scripts/test-all.sh globs `apps/web-platform/scripts/*.test.sh`
# (cited by content, not line number — coordinates rot silently), so this suite
# runs on every full-suite run. It MUST therefore pass with no Docker daemon and
# no stack running — every docker/supabase call is PATH-shimmed.
#
# THE FAKE IS ARGV-AWARE ON PURPOSE. An earlier revision dispatched on $1 only
# and returned a fixture regardless of --filter/--format, which put the fixture
# seam ABOVE the code under test: changing `.NetworkSettings.Ports` to
# `.HostConfig.PortBindings` (the exact proxy trap this gate exists to avoid),
# or corrupting the project label so the gate matched zero containers and
# passed forever, both left the suite fully green. See
# `.claude/hooks/stub-argv-fidelity.test.sh` for the codified class, and
# `postgrest-reload-schema.test.sh` for the argv-recording precedent.

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

# ONE owning tempdir for the whole suite, with a single owning trap (ADR-129).
WORKROOT="$(mktemp -d -t supabase-local-test.XXXXXXXX)" || {
  echo "SETUP FAILURE: cannot allocate a work dir" >&2; exit 2; }
trap 'rm -rf "$WORKROOT"' EXIT INT TERM HUP
CASE_N=0

# ---------------------------------------------------------------------------
# Fake `docker`, argv-aware.
#
#   ps      -> REQUIRES `--filter label=com.supabase.cli.project...` and
#              `--format {{.ID}}`; exits 64 otherwise so a selector regression
#              is a loud failure, not a silent zero-container pass.
#   inspect -> REQUIRES `{{json .NetworkSettings.Ports}}`; exits 64 on any other
#              field (kills the PortBindings proxy-trap mutation). Output is
#              keyed PER CONTAINER via DOCKER_INSPECT_<id>, so a fixture can
#              make c1 clean and c2 exposed — which is what makes the
#              early-`break` mutations detectable.
#   network -> inspect/create/rm for the ensure_network path.
# ---------------------------------------------------------------------------
make_fake_docker() {
  local dir="$1"
  cat > "$dir/docker" <<'FAKE'
#!/usr/bin/env bash
: "${DOCKER_PS_OUT:=}"
: "${DOCKER_EXIT:=0}"
: "${DOCKER_INSPECT_FAIL_ID:=}"
: "${DOCKER_NET_LABEL:=}"
: "${DOCKER_NET_OPT:=}"
: "${DOCKER_NET_EXISTS:=0}"
: "${DOCKER_NET_RM_EXIT:=0}"
: "${DOCKER_ARGV_LOG:=/dev/null}"
printf '%s\n' "$*" >> "$DOCKER_ARGV_LOG"

if [[ "${DOCKER_EXIT}" != "0" ]]; then
  echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock." >&2
  exit "${DOCKER_EXIT}"
fi

case "${1:-}" in
  ps)
    [[ "$*" == *"--filter label=com.supabase.cli.project"* ]] || {
      echo "FAKE-DOCKER: ps without the project label filter: $*" >&2; exit 64; }
    [[ "$*" == *"{{.ID}}"* ]] || {
      echo "FAKE-DOCKER: ps without --format {{.ID}}: $*" >&2; exit 64; }
    printf '%s' "$DOCKER_PS_OUT"; [[ -n "$DOCKER_PS_OUT" ]] && printf '\n'
    ;;
  inspect)
    [[ "$*" == *"{{json .NetworkSettings.Ports}}"* ]] || {
      echo "FAKE-DOCKER: inspect must read .NetworkSettings.Ports, got: $*" >&2; exit 64; }
    cid="${!#}"
    [[ -n "$DOCKER_INSPECT_FAIL_ID" && "$cid" == "$DOCKER_INSPECT_FAIL_ID" ]] && {
      echo "Error: No such object: $cid" >&2; exit 1; }
    var="DOCKER_INSPECT_${cid}"
    printf '%s\n' "${!var:-{\}}"
    ;;
  network)
    case "${2:-}" in
      ls)      [[ "$DOCKER_NET_EXISTS" == "1" ]] && echo "supabase-local-loopback" ;;
      inspect) if [[ "$*" == *"Labels"* ]]; then printf '%s\n' "$DOCKER_NET_LABEL";
               else printf '%s\n' "$DOCKER_NET_OPT"; fi ;;
      rm)      exit "$DOCKER_NET_RM_EXIT" ;;
      create)  : ;;
    esac
    ;;
esac
exit 0
FAKE
  chmod +x "$dir/docker"
}

# Fake `supabase` that records its argv — this is what makes the passthrough
# path behaviourally testable instead of source-grepped.
make_fake_supabase() {
  local dir="$1"
  cat > "$dir/supabase" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${SUPABASE_ARGV_FILE:-/dev/null}"
exit 0
FAKE
  chmod +x "$dir/supabase"
}

reset_fixture() {
  # LOAD-BEARING: `VAR=x res=$(run_assert)` is an ASSIGNMENT-ONLY command, so
  # bash persists VAR as a shell variable rather than scoping it to one command.
  # Without this reset a previous case's DOCKER_EXIT leaks forward and the next
  # cases silently measure "docker unreachable" instead of their own fixture.
  DOCKER_PS_OUT=""
  DOCKER_EXIT="0"
  DOCKER_INSPECT_FAIL_ID=""
  DOCKER_INSPECT_c1='{}'
  DOCKER_INSPECT_c2='{}'
}

new_case_dir() {
  CASE_N=$((CASE_N + 1))
  local d="${WORKROOT}/case-${CASE_N}"
  mkdir -p "$d" || { echo "SETUP FAILURE: mkdir $d" >&2; exit 2; }
  make_fake_docker "$d"
  make_fake_supabase "$d"
  printf '%s' "$d"
}

run_assert() {
  local d out rc
  d="$(new_case_dir)"
  set +e
  out=$(env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR"  DOCKER_PS_OUT="${DOCKER_PS_OUT:-}"  DOCKER_EXIT="${DOCKER_EXIT:-0}"  DOCKER_INSPECT_FAIL_ID="${DOCKER_INSPECT_FAIL_ID:-}"  DOCKER_INSPECT_c1="${DOCKER_INSPECT_c1:-{\}}"  DOCKER_INSPECT_c2="${DOCKER_INSPECT_c2:-{\}}"  bash "$SCRIPT" assert 2>&1)
  rc=$?
  set -e
  printf '%s|%s' "$rc" "$out"
}

# Derived from the SAME source the SUT reads, so a project_id change moves both
# sides together instead of turning this into a restated literal that rots.
EXPECTED_PROJECT="$(sed -nE 's/^[[:space:]]*project_id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p'  "${SCRIPT_DIR}/../supabase/config.toml" | head -1)"
EXPECTED_NET="supabase-local-loopback${EXPECTED_PROJECT:+-$EXPECTED_PROJECT}"

CLEAN='{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"54322"}]}'
DIRTY='{"5432/tcp":[{"HostIp":"0.0.0.0","HostPort":"54322"}]}'

# ---------------------------------------------------------------------------
echo "T1: wildcard IPv4 0.0.0.0 -> EXPOSED"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1="$DIRTY" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 on 0.0.0.0"; else fail "expected 1, got $rc ($out)"; fi
if grep -Eq '0\.0\.0\.0' <<<"$out"; then pass "names the offending address"; else fail "does not name 0.0.0.0"; fi

echo "T2: wildcard IPv6 :: -> EXPOSED"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"::","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 on ::"; else fail "expected 1, got $rc ($out)"; fi

echo "T3: 127.0.0.1 only -> OK, and the count is reported"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1="$CLEAN" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 on 127.0.0.1"; else fail "expected 0, got $rc ($out)"; fi
# Assert the COUNT, not just rc: rc=0 is also what "no stack" returns, so an
# rc-only assertion cannot tell "verified 1 binding" from "checked nothing".
if grep -Eq 'OK — 1 published binding\(s\) across 1 container\(s\)' <<<"$out"; then pass "reports 1 binding across 1 container"; else fail "count line wrong: $out"; fi

echo "T3b: ::1 is ALSO safe (direction fixture — :: has an unsafe fixture, ::1 had none)"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"::1","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 on ::1"; else fail "expected 0, got $rc ($out)"; fi

echo "T3c: dual-stack loopback (the REAL post-fix shape) -> OK, 2 bindings"
reset_fixture
DOCKER_PS_OUT="c1"  DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"54322"},{"HostIp":"::1","HostPort":"54322"}]}'  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 on dual-stack loopback"; else fail "expected 0, got $rc ($out)"; fi
if grep -Eq '2 published binding\(s\)' <<<"$out"; then pass "counts both bindings"; else fail "count wrong: $out"; fi

echo "T3d: a concrete LAN IP is EXPOSED (every other dirty fixture is a wildcard)"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"192.168.1.142","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exit 1 on a concrete LAN bind"; else fail "expected 1, got $rc ($out)"; fi

echo "T4: null port entries are skipped, not flagged"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"8080/tcp":null,"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "null entry ignored"; else fail "expected 0, got $rc ($out)"; fi

echo "T5: zero containers -> OK and SILENT"
reset_fixture
DOCKER_PS_OUT="" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "0" ]]; then pass "exit 0 with no stack"; else fail "expected 0, got $rc ($out)"; fi
# The comment promised silence; nothing checked it before.
if [[ -z "${out//[[:space:]]/}" ]]; then pass "emits nothing (hook must not nag)"; else fail "expected silence, got: $out"; fi

echo "T6: docker unreachable -> exit 2 (UNKNOWN, not OK)"
reset_fixture
DOCKER_PS_OUT="" DOCKER_EXIT="1" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "2" ]]; then pass "exit 2 on unreachable daemon"; else fail "expected 2, got $rc ($out)"; fi

echo "T6b: inspect fails mid-loop -> exit 2, NEVER 0 (the gate's own fail-open)"
reset_fixture
DOCKER_PS_OUT="c1
c2" DOCKER_INSPECT_c1="$CLEAN" DOCKER_INSPECT_FAIL_ID="c2" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "2" ]]; then pass "uninspectable container -> UNKNOWN"; else fail "expected 2, got $rc ($out)"; fi

echo "T6c: a DEFINITE exposure outranks an UNKNOWN (1 beats 2)"
reset_fixture
DOCKER_PS_OUT="c1
c2" DOCKER_INSPECT_c1="$DIRTY" DOCKER_INSPECT_FAIL_ID="c2" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "exposure wins over unknown"; else fail "expected 1, got $rc ($out)"; fi

echo "T7: empty HostIp (the PortBindings proxy shape) is fail-closed"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "empty HostIp -> EXPOSED"; else fail "expected 1, got $rc ($out)"; fi

echo "T8: clean container FIRST, exposed SECOND -> EXPOSED (no early-break fail-open)"
reset_fixture
DOCKER_PS_OUT="c1
c2" DOCKER_INSPECT_c1="$CLEAN" DOCKER_INSPECT_c2="$DIRTY" res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
# This is the fixture the previous revision's comment CLAIMED and did not have:
# both containers were exposed, so `break` after the first survived green.
if [[ "$rc" == "1" ]]; then pass "finds the exposure behind a clean container"; else fail "expected 1, got $rc ($out)"; fi
if grep -Eq '1 of 2 published binding\(s\) across 2 container\(s\)' <<<"$out"; then pass "counts across both containers"; else fail "count wrong: $out"; fi

echo "T8b: clean binding FIRST within one container, dirty SECOND -> EXPOSED"
reset_fixture
DOCKER_PS_OUT="c1"  DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"54322"},{"HostIp":"0.0.0.0","HostPort":"54322"}]}'  res=$(run_assert)
rc="${res%%|*}"; out="${res#*|}"
if [[ "$rc" == "1" ]]; then pass "no early-break inside a container"; else fail "expected 1, got $rc ($out)"; fi

echo "T9: --help works without docker"
set +e
help_out=$(env -i PATH="/usr/bin:/bin" HOME="$HOME" bash "$SCRIPT" --help 2>&1); help_rc=$?
set -e
if [[ "$help_rc" == "0" ]]; then pass "--help exits 0"; else fail "--help exit $help_rc"; fi
if grep -Eq 'assert' <<<"$help_out"; then pass "--help documents assert"; else fail "--help omits assert"; fi

# ---------------------------------------------------------------------------
# T10 — BEHAVIOURAL passthrough probe.
#
# The previous revision grepped the SUT source for '--network-id[^|]*"$@"'.
# That regex also matches the COMMENT above the exec line, so deleting the exec
# line entirely, or inverting it to `exec supabase "$@" --network-id …` (the
# precise bug the assertion was named for), both left the suite green. Now we
# run the real thing against a fake `supabase` that records its argv.
# ---------------------------------------------------------------------------
echo "T10: --network-id precedes \"\$@\" (behavioural, not a source grep)"
reset_fixture
d="$(new_case_dir)"
argv_file="${d}/supabase-argv"
set +e
env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR"  SUPABASE_ARGV_FILE="$argv_file"  DOCKER_NET_EXISTS="1" DOCKER_NET_OPT="127.0.0.1"  bash "$SCRIPT" db lint -- --strict >/dev/null 2>&1
exec_rc=$?
set -e
recorded="$(cat "$argv_file" 2>/dev/null || true)"
if [[ "$exec_rc" == "0" ]]; then pass "passthrough exits 0"; else fail "passthrough rc=$exec_rc"; fi
if [[ "$recorded" == "--network-id ${EXPECTED_NET} db lint -- --strict" ]]; then pass "argv is exactly: --network-id <net> db lint -- --strict"; else fail "argv wrong: '$recorded'"; fi

echo "T11: ensure_network REFUSES to delete a network it does not own"
reset_fixture
d="$(new_case_dir)"
set +e
own_out=$(env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR"  SUPABASE_ARGV_FILE="${d}/argv"  DOCKER_NET_EXISTS="1" DOCKER_NET_OPT="" DOCKER_NET_LABEL=""  bash "$SCRIPT" start 2>&1)
own_rc=$?
set -e
if [[ "$own_rc" == "2" ]]; then pass "exit 2 rather than rm an unowned network"; else fail "expected 2, got $own_rc"; fi
if grep -Eq 'refusing to delete a network we do not own' <<<"$own_out"; then pass "explains the refusal"; else fail "no refusal message: $own_out"; fi

echo "T12: stop/status do NOT run ensure_network (remediation must not self-block)"
reset_fixture
d="$(new_case_dir)"
set +e
env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR"  SUPABASE_ARGV_FILE="${d}/argv"  DOCKER_NET_EXISTS="1" DOCKER_NET_OPT="" DOCKER_NET_LABEL=""  bash "$SCRIPT" stop >/dev/null 2>&1
stop_rc=$?
set -e
stop_argv="$(cat "${d}/argv" 2>/dev/null || true)"
# With a mis-configured, unowned network present, `start` exits 2 (T11). `stop`
# must still reach the CLI — it is the first half of the prescribed remediation.
if [[ "$stop_rc" == "0" ]]; then pass "stop reaches the CLI despite a bad network"; else fail "stop rc=$stop_rc"; fi
if [[ "$stop_argv" == "--network-id ${EXPECTED_NET} stop" ]]; then pass "stop argv is correct"; else fail "stop argv wrong: '$stop_argv'"; fi

# ---------------------------------------------------------------------------
# Assertion-count floor.
#
# Without this, making pass/fail no-ops printed "0 passed, 0 failed" and exited
# 0, and deleting cases T2-T10 also exited 0 — the suite could certify nothing
# while reporting success. A FLOOR (not equality) so adding a case does not
# spuriously fail; derived from a green run.
# ---------------------------------------------------------------------------
echo "T13: containers present but NOTHING parsable -> exit 2, never 0"
# The gate previously returned "OK — 0 published binding(s)" for each of these,
# all of which describe a stack published on 0.0.0.0 with inspect exiting 0.
for shape in  '{"5432/tcp": [{"HostIp": "0.0.0.0", "HostPort": "54322"}]}'  '{"5432/tcp":[{"hostIP":"0.0.0.0","hostPort":54322}]}'  '{"5432/tcp":[{"HostIp":"0.0.0.'  ''  'null'
do
  reset_fixture
  DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1="$shape" res=$(run_assert)
  rc="${res%%|*}"
  if [[ "$rc" == "1" || "$rc" == "2" ]]; then
    pass "unparsable/odd shape -> rc=$rc (not a false OK)"
  else
    fail "shape returned rc=$rc (false OK): ${shape:0:40}"
  fi
done

echo "T14: 127.0.0.53 and the expanded IPv6 loopback are SAFE (no false alarm)"
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"127.0.0.53","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"
if [[ "$rc" == "0" ]]; then pass "127.0.0.53 is loopback"; else fail "127.0.0.53 -> rc=$rc"; fi
reset_fixture
DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1='{"5432/tcp":[{"HostIp":"0:0:0:0:0:0:0:1","HostPort":"54322"}]}' res=$(run_assert)
rc="${res%%|*}"
if [[ "$rc" == "0" ]]; then pass "expanded ::1 is loopback"; else fail "expanded ::1 -> rc=$rc"; fi

echo "T15: grep FAILURE (rc>=2 / grep absent) -> exit 2, not a false OK"
# `|| true` collapsed "no match" (rc 1, legitimate) with "grep errored" (rc>=2)
# and "grep missing" (127) into "this container publishes nothing" — returning
# OK over a 0.0.0.0 stack. This shim makes grep fail the way a broken/absent
# grep would, with a fixture that IS exposed.
reset_fixture
d="$(new_case_dir)"
cat > "$d/grep" <<'GSHIM'
#!/usr/bin/env bash
exit 2
GSHIM
chmod +x "$d/grep"
set +e
gout=$(env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR"  DOCKER_PS_OUT="c1" DOCKER_INSPECT_c1="$DIRTY"  bash "$SCRIPT" assert 2>&1)
grc=$?
set -e
if [[ "$grc" == "2" ]]; then pass "grep failure -> UNKNOWN (rc=2)"; else fail "expected 2, got $grc ($gout)"; fi
# Assert the SPECIFIC diagnostic, not just rc. The positive-evidence floor also
# returns 2 for this input, so an rc-only assertion cannot tell the two guards
# apart — deleting the grep branch would leave the suite green. Safety is
# preserved by the floor either way; what this branch uniquely buys is naming
# the cause, so that is what the test pins.
if grep -Eq 'HostIp parse failed' <<<"$gout"; then pass "names grep failure specifically (not the generic floor message)"; else fail "no grep-specific diagnostic: $gout"; fi

echo "T16: --require-stack turns zero containers into an error (plan T3)"
reset_fixture
d="$(new_case_dir)"
set +e
rs_out=$(env -i PATH="$d:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR" DOCKER_PS_OUT="" \
        bash "$SCRIPT" assert --require-stack 2>&1)
rs_rc=$?
set -e
if [[ "$rs_rc" == "2" ]]; then pass "--require-stack: no containers -> 2"; else fail "expected 2, got $rs_rc ($rs_out)"; fi
if grep -Eq 'NO_CONTAINERS' <<<"$rs_out"; then pass "names NO_CONTAINERS"; else fail "no NO_CONTAINERS marker: $rs_out"; fi
# ...and the DEFAULT stays silent-0, so the SessionStart hook cannot nag.
reset_fixture
DOCKER_PS_OUT="" res=$(run_assert)
if [[ "${res%%|*}" == "0" ]]; then pass "default (hook) path still 0"; else fail "default changed: ${res%%|*}"; fi

MIN_ASSERTIONS=37
echo ""
echo "supabase-local.test.sh: $PASS passed, $FAIL failed"
if [[ "$PASS" -lt "$MIN_ASSERTIONS" ]]; then
  echo "ASSERTION FLOOR BREACHED: ran $PASS, expected >= $MIN_ASSERTIONS." >&2
  echo "Cases were dropped or the assertion helpers stopped recording." >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
