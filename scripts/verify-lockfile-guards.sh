#!/usr/bin/env bash
# The ADR-191 discoverability probe: one command an operator can run locally to
# confirm the single-lockfile-of-record invariant still holds.
#
# Why a wrapper rather than the two guards chained with `&&` in the plan's
# `discoverability_test.command`: preflight Check 10 executes that command inside
# a bubblewrap sandbox and rejects every shell-active token BEFORE running it, so
# a chained form is refused unparsed — the probe would never execute and the
# invariant would be declared verifiable while being verified by nothing. A single
# repo-relative script is the sanctioned shape.
#
# The success marker is a FIXED token, deliberately. The guards' own summary lines
# carry live counts (tracked files, workflow files, install steps), so any probe
# expecting them goes stale the moment the tree grows — a false RED that teaches
# operators to ignore the probe. The counts are still printed for a human reading
# the output; only the marker is contracted.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

bash scripts/lint-dual-lockfile.sh
bash scripts/lint-workflow-install-sites.sh

echo "verify-lockfile-guards: OK"
