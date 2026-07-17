#!/usr/bin/env bash
# Structure + control-flow anchor tests for grok-gpu-bootstrap.sh — no live GPU required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/dogfood/grok-gpu-bootstrap.sh"
ASSERT_LIB="${ROOT}/scripts/dogfood/assert-ollama-loopback.sh"
fails=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SCRIPT" ]] || { echo "missing $SCRIPT" >&2; exit 1; }
[[ -f "$ASSERT_LIB" ]] || { echo "missing $ASSERT_LIB" >&2; exit 1; }

# Syntax
if bash -n "$SCRIPT" && bash -n "$ASSERT_LIB"; then
  pass "bash -n clean (bootstrap + assert lib)"
else
  fail "bash -n"
fi

# Loopback bind required
if grep -qE 'OLLAMA_HOST_BIND="127\.0\.0\.1:11434"' "$SCRIPT"; then
  pass "loopback bind string present"
else
  fail "missing loopback OLLAMA_HOST_BIND=127.0.0.1:11434"
fi

# Public bind is a hard die (call-form anchors comments cannot satisfy)
if grep -qE 'die[[:space:]]+"[^"]*public interface' "$SCRIPT" \
  || grep -qE 'die "public or non-loopback' "$SCRIPT"; then
  pass "public bind die path present"
else
  fail "must die on public bind (call-form die anchor)"
fi

# ss required fail-closed
if grep -qE 'ss \(iproute2\) required|ss required for Approach A' "$SCRIPT" \
  && grep -qE 'command -v ss' "$ASSERT_LIB"; then
  pass "ss required fail-closed"
else
  fail "missing fail-closed ss requirement"
fi

# License gate is real control flow (not header prose alone)
# shellcheck disable=SC2016  # intentional: match literal $LICENSE_OK in source
if grep -qE '\[\[\s*"\$LICENSE_OK"\s+-eq\s+1\s*\]\]\s*\|\|\s*die' "$SCRIPT"; then
  pass "license-ok control-flow gate"
else
  fail "missing LICENSE_OK control-flow die before pull"
fi

if grep -qE -- '--license-ok' "$SCRIPT"; then
  pass "license-ok flag parse"
else
  fail "missing --license-ok flag"
fi

# Co-location / base_url loopback in config seed
if grep -qE 'base_url = "http://127\.0\.0\.1:11434/v1"' "$SCRIPT"; then
  pass "config.toml base_url is loopback"
else
  fail "config seed must use loopback base_url"
fi

# MODEL charset validation
if grep -qE 'MODEL_SAFE_RE=' "$SCRIPT"; then
  pass "MODEL charset validation present"
else
  fail "missing MODEL safe charset guard"
fi

# No hcloud host birth
if ! grep -qE 'hcloud server create|hcloud_server' "$SCRIPT"; then
  pass "no hcloud create"
else
  fail "must not call hcloud create"
fi

# Workspace clone for measure cwd
if grep -qE 'git clone --depth 1 https://github.com/jikig-ai/soleur.git' "$SCRIPT"; then
  pass "workspace clone path present"
else
  fail "missing concrete workspace clone"
fi

# Shared assert lib: allowlist fail on 0.0.0.0
# shellcheck disable=SC1090
source "$ASSERT_LIB"
if ! command -v ss >/dev/null 2>&1; then
  pass "ss absent here — skip live assert_ollama_loopback_listen smoke (CI hosts usually have ss)"
else
  # Live call with real ss: should not die solely because nothing listens on 11434
  if assert_ollama_loopback_listen; then
    pass "assert_ollama_loopback_listen runs (no public 11434 or empty)"
  else
    fail "assert_ollama_loopback_listen unexpected fail on clean host"
  fi
fi

# Non-loopback base_url refuse
tmpcfg="$(mktemp)"
printf 'base_url = "http://203.0.113.9:11434/v1"\n' >"$tmpcfg"
if ! assert_config_base_url_loopback "$tmpcfg" 2>/dev/null; then
  pass "assert_config_base_url_loopback refuses public host"
else
  fail "base_url public host should fail"
fi
printf 'base_url = "http://127.0.0.1:11434/v1"\n' >"$tmpcfg"
if assert_config_base_url_loopback "$tmpcfg"; then
  pass "assert_config_base_url_loopback accepts loopback"
else
  fail "loopback base_url should pass"
fi
rm -f "$tmpcfg"

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails" >&2
  exit 1
fi
echo "OK: grok-gpu-bootstrap structure tests"
exit 0
