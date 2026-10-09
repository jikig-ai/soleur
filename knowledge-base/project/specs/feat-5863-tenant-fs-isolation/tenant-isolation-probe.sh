#!/usr/bin/env bash
# tenant-isolation-probe.sh — founder check for #5863 (arm F outer wrap).
#
# Builds a two-tenant fixture, replays the COMMITTED outer-wrap argv
# (infra/agent-outer-wrap-argv.json — the same self-authored table the
# deploy canary replays, pinned byte-for-byte to buildOuterWrapArgv output
# by the Guard-2 test), and runs the SHARED isolation payload inside the
# resulting mount namespace (apps/web-platform/scripts/
# tenant-isolation-inner-probe.sh — the same assertion set the canary and
# the test suite run; it must not be re-implemented here or the copies can
# drift green).
#
# Deliberately jq+bwrap only — no bun/node: this probe also executes under
# soleur:preflight Check 10's Step-10.5 bwrap sandbox, where the repo's dev
# toolchains live under a tmpfs'd /home and are unreachable.
#
# Prints `isolation_ok` on success, `isolation_fail` otherwise (the shared
# payload's verdict; the plan's discoverability_test expected_output).
#
# Requires: bash, jq, coreutils, bwrap. On a host where bwrap carries the
# file caps (prod image: cap_sys_admin+ep) the fixture argv runs verbatim;
# otherwise --unshare-user is prepended (the fallback arm — the wrap itself
# stays mount-only either way).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PAYLOAD="$REPO_ROOT/apps/web-platform/scripts/tenant-isolation-inner-probe.sh"
FIXTURE="$REPO_ROOT/apps/web-platform/infra/agent-outer-wrap-argv.json"

for dep in jq bwrap; do
  command -v "$dep" >/dev/null 2>&1 || {
    printf 'isolation_fail: %s not on PATH\n' "$dep" >&2
    exit 1
  }
done

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/tip.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

# Prep the fixture's declared tree (prepDirs + prepFiles — the manifest the
# Guard-2 test keeps in lockstep with the argv bind sources).
while IFS= read -r d; do mkdir -p "$d"; done < <(
  jq -r '.prepDirs[] | gsub("\\{\\{ROOT\\}\\}"; $r)' --arg r "$FIXTURE_ROOT" "$FIXTURE"
)
while IFS= read -r f; do mkdir -p "$(dirname "$f")"; : > "$f"; done < <(
  jq -r '.prepFiles[] | gsub("\\{\\{ROOT\\}\\}"; $r)' --arg r "$FIXTURE_ROOT" "$FIXTURE"
)

mapfile -t ARGV < <(
  jq -r '.bwrapSetupArgv[] | gsub("\\{\\{ROOT\\}\\}"; $r)' --arg r "$FIXTURE_ROOT" "$FIXTURE"
)
[ "${#ARGV[@]}" -gt 0 ] || { printf 'isolation_fail: fixture argv empty\n' >&2; exit 1; }

# Own workspace = the --chdir target (the builder emits it last); the
# sibling is a probe-time addition that must never appear inside.
OWN=""
for ((i = 0; i < ${#ARGV[@]} - 1; i++)); do
  [ "${ARGV[i]}" = "--chdir" ] && OWN="${ARGV[i+1]}"
done
[ -n "$OWN" ] || { printf 'isolation_fail: no --chdir target in fixture argv\n' >&2; exit 1; }
PARENT="$(dirname "$OWN")"
SIBLING="$PARENT/ws-bbbb"
mkdir -p "$SIBLING"
printf 'sibling-secret\n' > "$SIBLING/marker.txt"

# File-cap'd bwrap (prod posture) runs the argv verbatim — zero --unshare-*.
# A capless host adds --unshare-user up front (the fixture argv is unchanged;
# bwrap's own userns fallback is what the in-image smoke uses too).
EXTRA=()
# Pin /usr/bin/bwrap, never PATH — PATH may carry the #8752 bwrap-shim
# (its NEWUSER-deny filter exists to reject the INNER sandbox's argv).
BWRAP="${BWRAP_PATH:-/usr/bin/bwrap}"
if ! getcap "$BWRAP" 2>/dev/null | grep -q 'cap_sys_admin'; then
  EXTRA=(--unshare-user)
fi

# The payload travels on stdin (`bash -s`): nothing under /app/scripts is
# bound inside the wrap, and argv-embedding the script would make the
# spawned argv carry assertion text.
"$BWRAP" "${EXTRA[@]}" "${ARGV[@]}" /bin/bash -s -- "$PARENT" "$OWN" "$SIBLING" < "$PAYLOAD"
