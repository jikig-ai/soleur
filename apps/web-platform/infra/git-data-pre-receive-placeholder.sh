#!/usr/bin/env bash
#
# FAIL-CLOSED placeholder pre-receive — epic #5274 Phase 2 PR B / ADR-068 §3.
#
# Ships in cloud-init as the git-data fence hook UNTIL the real CAS fence
# (git-data-pre-receive.sh) is delivered by a host replace (cloud-init) or the
# operator root path the cutover uses. NOT by a git-uid channel: the hook directory is
# root:git 0750 and this file root:root (#8043 F9), and the "web-platform deploy
# pipeline" this header once named was never built (ADR-149, F9 disposition).
#
# Rejects EVERY push: a write admitted here would bypass the monotonic-gen CAS
# guarantee the real hook enforces, so until the real hook lands the only safe
# answer is "no". At replicas=1 nothing pushes to git-data before cutover, so
# this placeholder never blocks legitimate traffic.
set -euo pipefail

# Drain stdin (the <old> <new> <ref> lines) to avoid a SIGPIPE on the sender,
# exactly as the real hook does (git-data-pre-receive.sh).
cat >/dev/null 2>&1 || true

echo "remote: git-data fence: pre-receive fence hook not yet delivered (placeholder) — push rejected (fail-closed)" >&2
exit 1
