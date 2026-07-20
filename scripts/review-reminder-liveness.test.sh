#!/usr/bin/env bash
# Tests the review-reminder.yml liveness guard (#5999, ADR-094, AC9):
#   - the repo-root AGENTS.core.md is appended to the scan feed;
#   - the run FAILS loudly (::error:: + exit 1) when a required constitutional
#     path is NOT evaluated (frontmatter/cadence removed, or feed drop);
#   - the run passes (exit 0, no ::error::) when it IS evaluated.
# Extracts the embedded `run:` block and exercises it in a scratch repo with a
# mocked `gh` (so no network / no real issue creation). Mirrors GHA's default
# `bash -eo pipefail` shell.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF="$REPO_ROOT/.github/workflows/review-reminder.yml"

PASS=0; FAIL=0; TOTAL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo "FAIL: $1"; echo "  detail: ${2:-}"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 missing"; exit 0; }

# Extract the "Scan for due reviews" step's run: script from the workflow.
SCRIPT=$(python3 - "$WF" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
for step in wf["jobs"]["check-reviews"]["steps"]:
    if step.get("name") == "Scan for due reviews":
        sys.stdout.write(step["run"])
        break
PY
)
if [[ -z "$SCRIPT" ]]; then
  echo "FAIL: could not extract 'Scan for due reviews' run block from $WF"
  exit 1
fi

# AC9 (static): the feed includes AGENTS.core.md via required_paths + append.
if printf '%s' "$SCRIPT" | grep -q 'required_paths=("AGENTS.core.md")' \
   && printf '%s' "$SCRIPT" | grep -qF 'printf' \
   && printf '%s' "$SCRIPT" | grep -qF '${required_paths[@]}'; then
  pass "AC9 scan feed appends repo-root AGENTS.core.md"
else
  fail "AC9 feed inclusion" "required_paths / feed-append pattern not found"
fi

# Run the extracted script in a scratch repo with a mock gh. Sets RC + OUT.
run_scan() {
  local d="$1" bin; bin=$(mktemp -d)
  cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
exit 0
GH
  chmod +x "$bin/gh"
  OUT=$(cd "$d" && PATH="$bin:$PATH" GH_TOKEN=x SERVER_URL=https://github.com \
        REPO_NAME=o/r DATE_OVERRIDE="" bash -eo pipefail -c "$SCRIPT" 2>&1)
  RC=$?
  rm -rf "$bin"
}

# Case A: AGENTS.core.md WITH frontmatter → evaluated → exit 0, no ::error::.
dA=$(mktemp -d); mkdir -p "$dA/knowledge-base"
cat > "$dA/AGENTS.core.md" <<'EOF'
---
last_reviewed: 2026-07-05
review_cadence: monthly
owner: founder
---
# core
EOF
run_scan "$dA"
if [[ "$RC" == "0" ]] && ! grep -q '::error::' <<<"$OUT"; then
  pass "liveness: core WITH frontmatter → evaluated, exit 0"
else
  fail "liveness present" "rc=$RC out=${OUT:0:400}"
fi
rm -rf "$dA"

# Case B: AGENTS.core.md WITHOUT frontmatter → not evaluated → ::error:: + exit 1.
dB=$(mktemp -d); mkdir -p "$dB/knowledge-base"
printf '# core, frontmatter removed\n' > "$dB/AGENTS.core.md"
run_scan "$dB"
if [[ "$RC" == "1" ]] && grep -q '::error::Required constitutional path' <<<"$OUT"; then
  pass "liveness: core WITHOUT frontmatter → ::error:: + exit 1 (AC9)"
else
  fail "liveness missing" "rc=$RC out=${OUT:0:400}"
fi
rm -rf "$dB"

# Case C: last_reviewed present but review_cadence REMOVED → the empty-cadence
# `continue` skips the evaluated-marking → ::error:: + exit 1. Distinguishes
# "cadence removed" from "whole frontmatter removed" (Case B) — the run must fail
# loudly on either, not just the total wipe.
dC=$(mktemp -d); mkdir -p "$dC/knowledge-base"
cat > "$dC/AGENTS.core.md" <<'EOF'
---
last_reviewed: 2026-07-05
owner: founder
---
# core
EOF
run_scan "$dC"
if [[ "$RC" == "1" ]] && grep -q '::error::Required constitutional path' <<<"$OUT"; then
  pass "liveness: core with last_reviewed but NO review_cadence → ::error:: + exit 1"
else
  fail "liveness cadence-removed" "rc=$RC out=${OUT:0:400}"
fi
rm -rf "$dC"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]]
