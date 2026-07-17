#!/usr/bin/env bash
# Structure tests for grok-gpu-bootstrap.sh — no live GPU required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/dogfood/grok-gpu-bootstrap.sh"
fails=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SCRIPT" ]] || { echo "missing $SCRIPT" >&2; exit 1; }

# Syntax
if bash -n "$SCRIPT"; then
  pass "bash -n clean"
else
  fail "bash -n"
fi

# Loopback bind required
if grep -qE 'OLLAMA_HOST.*127\.0\.0\.1:11434|127\.0\.0\.1:11434' "$SCRIPT"; then
  pass "loopback bind string present"
else
  fail "missing loopback OLLAMA_HOST / 127.0.0.1:11434"
fi

# Refuse public bind (ss regex or die text)
if grep -qE "0\\.0\\.0\\.0|0\.0\.0\.0" "$SCRIPT" && grep -qE "public interface|requires loopback" "$SCRIPT"; then
  pass "public bind is a hard fail"
else
  fail "must detect and die on 0.0.0.0:11434"
fi

# License gate on pull
if grep -qE -- '--license-ok' "$SCRIPT" && grep -qE 'refuse.*license-ok|without --license-ok' "$SCRIPT"; then
  pass "license-ok gate on pull"
else
  fail "missing --license-ok refuse path"
fi

# Co-location / base_url loopback in config seed
if grep -qE 'base_url = "http://127\.0\.0\.1:11434/v1"' "$SCRIPT"; then
  pass "config.toml base_url is loopback"
else
  fail "config seed must use loopback base_url"
fi

# No hcloud host birth
if ! grep -qE 'hcloud server create|hcloud_server' "$SCRIPT"; then
  pass "no hcloud create"
else
  fail "must not call hcloud create"
fi

# Workspace clone for measure cwd
if grep -qE 'git clone|WORKSPACE' "$SCRIPT"; then
  pass "workspace clone path present"
else
  fail "missing workspace clone for measure --cwd"
fi

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails" >&2
  exit 1
fi
echo "OK: grok-gpu-bootstrap structure tests"
exit 0
