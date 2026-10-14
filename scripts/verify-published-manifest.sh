#!/usr/bin/env bash
# Discoverability test for the marketplace manifest (#7493, AC17).
#
# Answers ONE question an operator can ask from their own machine, with no SSH and no
# credentials: does the manifest published to jikig-ai/soleur-marketplace still equal the source
# that Terraform publishes from?
#
# WHY THIS IS A SCRIPT RATHER THAN A ONE-LINER IN THE PLAN.
# The plan's original `discoverability_test.command` was a folded YAML scalar that joined to
#   curl … > /tmp/pub.json && diff … && echo MANIFEST_IN_SYNC
# `preflight` Check 10 rejects any command carrying a shell-active token (`&&`, `>`, `|`, `;`,
# `$(`), so that command was never executed by the gate that exists to execute it — a
# discoverability test that could not be discovered. Check 10's own documented remedy for this
# shape is "wrap it in a repo-relative script", which is what this is.
#
# Runs inside Check 10's bwrap sandbox: network egress is retained, the repo is bound read-only,
# and /tmp is a tmpfs. It therefore reads the source from the repo, writes only under $TMPDIR,
# and needs no credentials.
set -uo pipefail

RAW_URL="${MARKETPLACE_RAW_URL:-https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${MARKETPLACE_SOURCE:-${HERE}/../infra/github/soleur-marketplace-manifest.json}"

if [[ ! -s "$SRC" ]]; then
  echo "MANIFEST_SOURCE_MISSING: no readable source at '${SRC}'" >&2
  exit 1
fi

PUB="$(mktemp)"
trap 'rm -f "$PUB"' EXIT

# Cache-busted: raw.githubusercontent.com serves cache-control max-age=300 through Fastly, so an
# uncached fetch is what makes this a check on the PUBLISHED bytes rather than on a CDN copy that
# may predate the last apply.
if ! curl -fsS --proto '=https' --max-time 10 \
      -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \
      "$RAW_URL" -o "$PUB"; then
  echo "MANIFEST_FETCH_FAILED: could not read ${RAW_URL}" >&2
  exit 1
fi

# Raw diff, never `jq -S`. Byte identity is the stated property and it is achievable, because
# github_repository_file writes `content` verbatim. Key-order normalisation would quietly weaken
# this to canonical-JSON equality.
if diff -u "$SRC" "$PUB" >&2; then
  echo "MANIFEST_IN_SYNC"
  exit 0
fi

echo "MANIFEST_DIVERGED: the published manifest does not match ${SRC} (diff above)" >&2
exit 1
