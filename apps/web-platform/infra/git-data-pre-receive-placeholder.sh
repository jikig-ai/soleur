#!/usr/bin/env bash
#
# FAIL-CLOSED placeholder pre-receive — epic #5274 Phase 2 PR B / ADR-068 §3.
#
# Ships in cloud-init as the git-data fence hook UNTIL the real CAS fence
# (git-data-pre-receive.sh) is delivered via the web-platform deploy pipeline
# (the safety-critical, most-likely-to-iterate artifact stays pipeline-iterable;
# CI cannot SSH either host — ci-ssh-key.tf header).
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
