#!/usr/bin/env bash
# Pure resolver: web-1's known-good running image tag, derived from its /health
# `.version`. #6147.
#
# WHY THIS EXISTS: the web_2_recreate pin-gate used to read web-1's running tag
# from the shared https://deploy.<domain>/hooks/deploy-status `.tag` slot. That
# slot is a SINGLE last-write-wins object (ci-deploy.sh write_state) stamped by
# multiple independent writers — a web-platform deploy, an inngest restart, a
# git-lock sweep. When a non-web writer owns it (e.g. an inngest watchdog restart
# stamping {component:inngest,tag:latest,exit_code:0}), the gate read a non-semver
# `latest` and hard-aborted the recreate (`got 'latest'`), even though web-1 was
# perfectly healthy. `.tag` is also the state file's LAST-ATTEMPT tag, not the
# actually-running image (ADR-079 amendment #5955).
#
# THE FIX: resolve web-1's running tag from its public /health `.version` — the
# baked BUILD_VERSION of the actually-running container — which is immune to
# deploy-status writer contention because it never reads the shared slot. This is
# verbatim the pattern apply-deploy-pipeline-fix.yml:599-608 already adopted for
# the identical "`.tag`=latest wedge" (ADR-079 #5955).
#
# THIS SCRIPT IS PURE — NO NETWORK I/O. The caller (the `pin` step in
# apply-web-platform-infra.yml) does the bounded curl retry against
# https://app.<APP_DOMAIN_BASE>/health and hands us the fetched `.version` string.
# Keeping the network in the workflow and the decision logic here makes the semver
# guard fixture-testable (resolve-web1-known-good-tag.test.sh), matching the
# deploy-status-fanout-verify.{sh,test.sh} seam precedent.
#
# CONTRACT:
#   input  : the bare /health `.version` string, via $1 (preferred) or stdin.
#   output : `v<version>` on stdout + exit 0, IFF it is strict three-part semver.
#   failure: exit 1 with a `::error::` diagnostic on stderr naming the rejected
#            version + a remediation. Emits NO tag on stdout.
#
# The strict `^v[0-9]+\.[0-9]+\.[0-9]+$` guard (the shape #5955 tightened to, that
# ci-deploy.sh enforces, and that reusable-release.yml:597,686 actually pushes)
# rejects a non-released build ("dev" → "vdev"), a prerelease ("1.2.3-rc1"), and
# the `latest` wedge — never silently pinning a floating/prerelease tag.
set -euo pipefail

# Input: $1 if given, else stdin. No trimming — a bare jq -r '.version' emits a
# clean string and the anchored regex rejects any stray whitespace as malformed.
if [[ $# -ge 1 ]]; then
  RUNNING_VERSION="$1"
else
  RUNNING_VERSION="$(cat || true)"
fi

TARGET_TAG="v${RUNNING_VERSION}"

if [[ ! "$TARGET_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Cannot resolve a semver known-good tag for web-1's running container from /health (.version='${RUNNING_VERSION}'). The container is not reporting a released BUILD_VERSION (expected strict vX.Y.Z). Trigger a normal web-platform release, confirm app/health reports the new version, then re-run this recreate." >&2
  exit 1
fi

printf '%s\n' "$TARGET_TAG"
