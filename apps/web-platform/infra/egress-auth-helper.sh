#!/usr/bin/env bash
# Squid basic_auth helper for the egress gateway (#9534).
#
# Protocol: Squid writes `username password` pairs on stdin, expects OK/ERR.
# The password is a PER-SESSION token minted by the app-side dispatch layer;
# it is valid iff a file of that name exists in the token dir (mounted ro).
# There is no static secret anywhere — a harvested token is scoped to one
# session's lifetime. Revocation is the forwarder's death — Squid caches the
# helper's OK for `credentialsttl` (pinned 30s in squid.conf), so file
# deletion is the bounded fail-safe, not instant revocation. The
# username passes through untouched: it carries workspaceId for %un log
# attribution and is never a credential.
#
# argv[1] = token dir (wired by auth_param basic program in squid.conf).
set -euo pipefail

TOKDIR="${1:-/etc/squid/session-tokens}"

while IFS=' ' read -r user pass; do
  # Token charset is restricted BEFORE the path join — `../` traversal and
  # slash-containing names can never leave the token dir.
  if [[ "$pass" =~ ^[A-Za-z0-9_-]{16,128}$ && -f "$TOKDIR/$pass" ]]; then
    echo OK
  else
    echo ERR
  fi
done
