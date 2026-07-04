#!/usr/bin/env bash
# Tests for scripts/lint-infra-no-human-steps.py.
#
# Sentinel model = human-actor + infra-imperative CO-OCCURRENCE. Enforcement
# teeth for hr-no-ssh-fallback-in-runbooks. Cases (assert on EXIT CODES, not
# summary literals):
#   T1: a human-step line              -> exit 1 (FAILS)
#   T2: an orchestrator-defers line    -> exit 0 (PASSES)
#   T3: an ignore-region line          -> exit 0 (PASSES)
#   T4: a fenced/backtick line         -> exit 0 (PASSES)
#   T5: `tofu apply` by operator (paraphrase) -> exit 1 (FAILS)
#   T6: a bare imperative w/o an actor -> exit 0 (bare-token denylist would FP)
#   T7: a Resolved-section human step  -> exit 0 (section carve-out)
#   T8: an adjacent actor/imperative split -> exit 1 (FAILS)
#
# Isolation: each case writes a throwaway .md via `mktemp` and runs the linter
# with an explicit positional path (bypasses scan-dir discovery + git).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/lint-infra-no-human-steps.py"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

# run_case <name> <expected_exit> <file>
run_case() {
  local name="$1" expected="$2" file="$3"
  local actual=0
  python3 "$SUT" "$file" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit=$expected actual=$actual"
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# T1 — a human-step line FAILS.
f1="$TMPDIR_TEST/t1.md"
cat > "$f1" <<'EOF'
# Cutover runbook

The operator SSHs into web-1 and runs terraform apply during the window.
EOF
run_case "human-step line FAILS" 1 "$f1"

# T2 — an orchestrator-defers line PASSES (no human actor).
f2="$TMPDIR_TEST/t2.md"
cat > "$f2" <<'EOF'
# Cutover runbook

The dispatch workflow runs terraform apply through the R2 concurrency serializer.
EOF
run_case "orchestrator-defers line PASSES" 0 "$f2"

# T3 — an ignore-region line PASSES.
f3="$TMPDIR_TEST/t3.md"
cat > "$f3" <<'EOF'
# Cutover runbook

<!-- lint-infra-ignore -->
The operator reboots the drained host by hand, then runs terraform apply.
<!-- lint-infra-ignore end -->
EOF
run_case "ignore-region line PASSES" 0 "$f3"

# T4 — a fenced/backtick line PASSES.
f4="$TMPDIR_TEST/t4.md"
cat > "$f4" <<'EOF'
# Cutover runbook

The operator triggers the dispatch, which internally invokes `terraform apply`.

```bash
# operator-facing example only
terraform apply -target=hcloud_volume.workspaces
```
EOF
run_case "fenced/backtick line PASSES" 0 "$f4"

# T5 — a `tofu apply` by operator paraphrase FAILS.
f5="$TMPDIR_TEST/t5.md"
cat > "$f5" <<'EOF'
# Cutover runbook

Then the operator applies the change by hand with tofu apply on the box.
EOF
run_case "tofu-apply-by-operator paraphrase FAILS" 1 "$f5"

# T6 — a bare imperative with NO actor PASSES (proves it is not a denylist).
f6="$TMPDIR_TEST/t6.md"
cat > "$f6" <<'EOF'
# Notes

The placement-group reboot is deferred to the orchestrator; terraform apply is
serialized through R2.
EOF
run_case "bare imperative without actor PASSES" 0 "$f6"

# T7 — a human step under a Resolved section PASSES (section carve-out).
f7="$TMPDIR_TEST/t7.md"
cat > "$f7" <<'EOF'
# Incident

## Resolved

Historically the operator had to reboot web-1 by hand; superseded by dispatch.
EOF
run_case "Resolved-section human step PASSES" 0 "$f7"

# T8 — adjacent actor/imperative split FAILS.
f8="$TMPDIR_TEST/t8.md"
cat > "$f8" <<'EOF'
# Cutover runbook

The operator, once the window opens, must then
reboot the sole live origin and restore weight.
EOF
run_case "adjacent actor/imperative split FAILS" 1 "$f8"

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ "$FAIL" -eq 0 ]]
