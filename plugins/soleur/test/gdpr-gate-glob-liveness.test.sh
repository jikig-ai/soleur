#!/usr/bin/env bash
# gdpr-gate-glob-liveness.test.sh — Guard 2's second chokepoint (#7710).
#
# The scan-completion line in gdpr-gate.sh witnesses "the scan ran and matched
# nothing". It structurally CANNOT witness "the hook never ran": a line
# emitted by the script is silent precisely when the script does not execute.
#
# If the `gdpr-gate-advisory` glob in lefthook.yml stops matching regulated
# paths, lefthook prints `(skip)`, the script is never invoked, and NO line of
# any kind is emitted. Every in-script assertion stays green. This repo has
# shipped that trap twice (2026-03-21-lefthook-gobwas-glob-double-star.md), and
# gobwas `**` semantics — `**` matches 1+ intermediate dirs, never 0+ — make it
# easy to reintroduce with an edit that reads as a simplification.
#
# So this test drives the REAL lefthook binary over the REAL lefthook.yml with
# a materialised regulated path staged, and asserts the command actually ran.
#
# Run: bash plugins/soleur/test/gdpr-gate-glob-liveness.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LEFTHOOK_YML="$REPO_ROOT/lefthook.yml"

echo "=== gdpr-gate glob-liveness tests ==="
echo ""

if ! command -v lefthook >/dev/null 2>&1; then
  # A skip here is NOT a pass. This suite is the ONLY witness of "the hook was
  # never invoked", and `lefthook` is on no CI runner's PATH — so the earlier
  # form (SKIPPED++ then a floorless `print_results`) exited 0 having asserted
  # nothing, in exactly the environment that matters. Measured during #7710
  # review: `Passed: 0 / Failed: 0 / Skipped: 1 / ALL EXECUTED TESTS PASSED`.
  #
  # Under CI this is a hard failure: the gate is declared to run there, so an
  # absent binary is a broken gate, not an unavailable convenience. Locally it
  # degrades loudly to a skip so a contributor without lefthook is not blocked.
  # Hard-fail ONLY where the caller has declared lefthook is provisioned.
  #
  # Not on bare `CI`: the required `test-scripts` shard is path-filter-free and
  # runs on every PR, and adding a package-manager install there would put a
  # registry dependency on the merge-queue critical path for the whole repo —
  # the trap #6454 documents. Real CI coverage lives in
  # `.github/workflows/gdpr-gate-self-test.yml`, which already path-filters on
  # `lefthook.yml` and the gdpr-gate scripts (exactly the change-set that can
  # break the glob) and installs lefthook for this suite. That job sets
  # SOLEUR_REQUIRE_LEFTHOOK=1, so a skip there is a failure.
  if [[ "${SOLEUR_REQUIRE_LEFTHOOK:-}" == "1" ]]; then
    printf 'FAIL: lefthook is not on PATH but SOLEUR_REQUIRE_LEFTHOOK=1.\n' >&2
    printf 'Guard 2 second chokepoint cannot run; this suite is the only witness that\n' >&2
    printf 'the gdpr-gate-advisory hook is still invoked, and a skip is indistinguishable\n' >&2
    printf 'from a dead glob. Install lefthook in the job.\n' >&2
    exit 1
  fi
  echo "  SKIP: lefthook binary not on PATH — cannot exercise the glob."
  echo "        (Set SOLEUR_REQUIRE_LEFTHOOK=1 to make this a hard failure; the"
  echo "         gdpr-gate-self-test workflow does.)"
  SKIPPED=$((SKIPPED + 1))
  print_results 1
fi

# Instrument self-test for the ONE helper this suite routes an assertion
# through. The other five assertions are raw inline if/else, which a helper
# stub cannot neuter — so neutering assert_eq/assert_contains here is an
# EQUIVALENT mutation (they are not called), not a coverage gap.
_selftest_file_exists() {
  local p0="$PASS" f0="$FAIL"
  assert_file_exists "$LEFTHOOK_YML" "instrument self-test — records a pass"
  assert_file_exists "/nonexistent/definitely-not-here" \
    "instrument self-test — records a failure (EXPECTED FAIL above)"
  if (( PASS != p0 + 1 || FAIL != f0 + 1 )); then
    printf 'INSTRUMENT SELF-TEST FAILED: assert_file_exists cannot both pass and fail.\n' >&2
    exit 1
  fi
  PASS="$p0"; FAIL="$f0"
  printf '  (instrument self-test OK)\n'
}
_selftest_file_exists

assert_file_exists "$LEFTHOOK_YML" "lefthook.yml exists"

# Build an isolated repo carrying ONLY the gdpr-gate-advisory stanza and the
# real script, so the probe cannot be perturbed by (or perturb) sibling hooks.
SANDBOX="$(mktemp -d -t gdpr-glob.XXXXXXXX)"
assert_fixture_dir "$SANDBOX"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# Extract the live glob list for `gdpr-gate-advisory` from the real
# lefthook.yml. Reading the real file is the point: a hand-copied glob list in
# this test would pass while the shipped one rotted.
GLOBS="$(awk '
  /^    gdpr-gate-advisory:/ { in_cmd=1; next }
  in_cmd && /^    [a-z]/ { in_cmd=0 }
  in_cmd && /^        - "/ { print }
' "$LEFTHOOK_YML")"

GLOB_COUNT="$(printf '%s\n' "$GLOBS" | grep -c '^        - "' || true)"
if (( GLOB_COUNT < 5 )); then
  echo "  FAIL: extracted $GLOB_COUNT globs for gdpr-gate-advisory (expected >= 5) — the awk range is broken, not the glob"
  FAIL=$((FAIL + 1))
  print_results
else
  echo "  PASS: extracted $GLOB_COUNT globs for gdpr-gate-advisory from the live lefthook.yml"
  PASS=$((PASS + 1))
fi

build_sandbox() {
  # $1 = the glob block to install (allows the mutation case to narrow it)
  rm -rf "$SANDBOX/repo"
  mkdir -p "$SANDBOX/repo"
  git -C "$SANDBOX/repo" init -q -b main
  git -C "$SANDBOX/repo" config user.email t@t
  git -C "$SANDBOX/repo" config user.name t
  git -C "$SANDBOX/repo" config commit.gpgsign false

  mkdir -p "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/scripts"
  cp "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh" \
     "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/scripts/"
  cp "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh" \
     "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/scripts/"
  cp "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/NOTICE" \
     "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/"

  # Copy the REAL lefthook.yml and keep ONLY the gdpr-gate-advisory stanza.
  #
  # An earlier revision SYNTHESISED a 5-line config from the extracted glob
  # lines plus a hardcoded `run:`. That put everything else about the shipped
  # stanza out of reach — measured during #7710 review, adding `skip: true` to
  # the real stanza, or replacing its `run:` with `/bin/true`, BOTH survived
  # while this suite printed "lefthook did not report gdpr-gate-advisory as
  # skipped". A harness that rebuilds its target cannot witness the target.
  #
  # `$1` is honoured only when it differs from the live globs, which is how
  # the negative control (TS2) narrows the glob without touching the real file.
  python3 - "$REPO_ROOT/lefthook.yml" "$SANDBOX/repo/lefthook.yml" "$1" <<'PYEOF'
import sys, re
src, dst, globs_override = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding="utf-8").read()
m = re.search(r"^    gdpr-gate-advisory:\n(?:^(?:      |\t).*\n|^\n)*", text, re.M)
if not m:
    sys.stderr.write("FATAL: gdpr-gate-advisory stanza not found in the real lefthook.yml\n")
    sys.exit(2)
stanza = m.group(0)
if globs_override.strip():
    stanza = re.sub(
        r"      glob:\n(?:^        - .*\n)+",
        "      glob:\n" + globs_override.rstrip("\n") + "\n",
        stanza,
        flags=re.M,
    )
open(dst, "w", encoding="utf-8").write(
    "pre-commit:\n  parallel: false\n  commands:\n" + stanza
)
PYEOF
}

# One path per CANONICAL_REGEX alternation.
#
# A single fixture cannot see a glob set shrinking: measured during #7710
# review, deleting 10 of the 15 declared globs — every `app/api/**` entry,
# every `server/*auth*` entry, and BOTH `.sql` entries — left this suite green,
# because the surviving `lib/auth` globs still matched the one staged file and
# the count floor still passed. The gate would have stopped firing on every SQL
# migration and every API route with nothing red.
REGULATED_PATHS=(
  "apps/web-platform/lib/auth/probe.ts"
  "apps/web-platform/app/api/probe/route.ts"
  "apps/web-platform/server/probe-auth-helper.ts"
  "apps/web-platform/supabase/migrations/999_probe.sql"
)

stage_regulated_path() {
  # Depth-1 under lib/auth/ deliberately: that is the depth a bare `**` glob
  # silently drops.
  local p
  for p in "${REGULATED_PATHS[@]}"; do
    mkdir -p "$SANDBOX/repo/$(dirname "$p")"
    printf 'probe\n' > "$SANDBOX/repo/$p"
  done
  git -C "$SANDBOX/repo" add -A
}

run_hook() {
  ( cd "$SANDBOX/repo" && LEFTHOOK_VERBOSE=0 lefthook run pre-commit 2>&1 ) || true
}

# --- TS1: the live glob matches a regulated path and the command RUNS ------
echo ""
echo "TS1: live gdpr-gate-advisory glob -> command runs on a staged regulated path"
build_sandbox "$GLOBS"
stage_regulated_path
OUT="$(run_hook)"

# Every regulated arm must actually REACH the gate.
#
# Asserted per PATH, not as a count: redundant glob entries make lefthook pass
# some files twice (`app/api/*.ts` and `app/api/**/*.ts` both match a nested
# route, because `*` crosses `/`), so the examined count is 6 for 4 fixtures
# and a count assertion would encode that accident. The stderr breadcrumb
# names each matched path, which is the per-arm signal.
UNREACHED=()
for p in "${REGULATED_PATHS[@]}"; do
  grep -qF -- "$p" <<<"$OUT" || UNREACHED+=("$p")
done
if (( ${#UNREACHED[@]} == 0 )); then
  echo "  PASS: all ${#REGULATED_PATHS[@]} CANONICAL_REGEX arms reached the gate through the live glob set"
  PASS=$((PASS + 1))
else
  echo "  FAIL: these regulated paths never reached the gate — a glob arm is missing: ${UNREACHED[*]}"
  printf '%s\n' "$OUT" | sed 's/^/          /'
  FAIL=$((FAIL + 1))
fi

if grep -q 'path scan complete' <<<"$OUT"; then
  echo "  PASS: gdpr-gate.sh executed via lefthook (scan-completion line observed)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: gdpr-gate.sh did NOT run — the glob no longer matches a regulated path"
  echo "        lefthook output was:"
  printf '%s\n' "$OUT" | sed 's/^/          /'
  FAIL=$((FAIL + 1))
fi

if grep -qE 'gdpr-gate-advisory.*\(skip\)' <<<"$OUT"; then
  echo "  FAIL: lefthook reported gdpr-gate-advisory as skipped"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: lefthook did not report gdpr-gate-advisory as skipped"
  PASS=$((PASS + 1))
fi

# --- TS2: own dispatch — a narrowed glob must be DETECTED ------------------
# Guard 2 mutation 5. This is the control that proves TS1 can fail: without
# it, TS1 passing tells you the harness works, not that the glob does.
echo ""
echo "TS2: narrowed glob (matches nothing) -> the probe reports the silence"
build_sandbox '        - "no/such/path/*.nomatch"'
stage_regulated_path
OUT_MUT="$(run_hook)"

if grep -q 'path scan complete' <<<"$OUT_MUT"; then
  echo "  FAIL: scan line appeared under a glob that matches nothing — the probe cannot detect a dead glob"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no scan line under a non-matching glob (the failure the script cannot self-report)"
  PASS=$((PASS + 1))
fi

print_results 6
