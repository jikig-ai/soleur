#!/usr/bin/env bash
# Shared test helpers for bash test suites.
# Source this file at the top of each .test.sh file.

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="$2"

  if [[ -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local path="$1"
  local msg="$2"

  if [[ ! -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file still exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

make_gh_stub() {
  # Creates a `gh` stub at "$stub_dir/gh" that handles `gh run list ...`.
  # The first arg is the stub directory (prepend to PATH); the second is the
  # literal stdout for `gh run list`. Subcommands other than `run list` exit 1.
  local stub_dir="$1" output="$2"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "run list" ]]; then
  printf '%s\n' "$output"
  exit 0
fi
echo "gh stub: unhandled subcommand '\$@'" >&2
exit 1
EOF
  chmod +x "$stub_dir/gh"
}

make_gh_stub_sleep() {
  # gh stub that sleeps to exercise the parser's timeout wrapper.
  local stub_dir="$1" seconds="$2"
  mkdir -p "$stub_dir"
  cat > "$stub_dir/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "run list" ]]; then
  sleep $seconds
  printf '2026-02-01T00:00:00Z\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$stub_dir/gh"
}

print_results() {
  echo "=== Results ==="
  echo "Passed: $PASS"
  echo "Failed: $FAIL"
  echo ""

  if [[ $FAIL -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
  else
    echo "ALL TESTS PASSED"
    exit 0
  fi
}
