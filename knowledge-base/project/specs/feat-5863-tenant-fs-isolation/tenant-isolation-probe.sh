#!/usr/bin/env bash
# tenant-isolation-probe.sh — founder check for #5863 (ADR-275 founder_check).
#
# Realized-state proof that a session's outer bwrap namespace carries no
# sibling workspace on any observable filesystem surface: directory listing,
# stat, and mountinfo. Builds two fixture workspaces, derives the outer argv
# for tenant A via the production argv builder, runs the probe inside bwrap.
#
# /proc is deliberately NOT asserted: arm F (mountns-only, file-cap bwrap —
# spike-verified 2026-10-08) shares the container procfs, so sibling PIDs
# remain visible. That residual is tracked as #9723.
#
# Lives under knowledge-base/ deliberately: the founder-check freeze commit
# must precede the first non-knowledge-base commit on the branch, and the pin
# must resolve in the freeze tree (ADR-275).
#
# Prints "isolation_ok" on success; exits non-zero otherwise. Until the outer
# wrap lands, this script fails — that is the expected pre-work state.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d /tmp/tip.XXXXXX)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$FIXTURE_ROOT/tenant-a" "$FIXTURE_ROOT/tenant-b"
echo secret-b > "$FIXTURE_ROOT/tenant-b/marker.txt"

# Ask the production argv builder for tenant A's outer-wrap argv (one arg per
# line). Exits non-zero if the module/flag does not exist yet.
mapfile -t ARGV < <(cd "$REPO_ROOT" && bun -e '
  import { buildOuterWrapArgv } from "./apps/web-platform/server/agent-outer-wrap.ts";
  const argv = buildOuterWrapArgv({ workspacePath: process.argv[2] });
  process.stdout.write(argv.join("\n") + "\n");
' -- "$FIXTURE_ROOT/tenant-a")

bwrap "${ARGV[@]}" -- /bin/bash -c '
  set -e
  ROOT="'"$FIXTURE_ROOT"'"
  # sibling must be absent from listing and stat
  [ "$(ls "$ROOT")" = "tenant-a" ]
  ! stat "$ROOT/tenant-b" >/dev/null 2>&1
  # mount table must not name the sibling
  ! grep -q tenant-b /proc/self/mounts
' || { echo "isolation_fail" >&2; exit 1; }

echo "isolation_ok"
