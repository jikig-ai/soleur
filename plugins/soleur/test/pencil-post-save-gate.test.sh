#!/usr/bin/env bash

# #11168 / #11156 — The post-save hard gate in ux-design-lead.md step 3.2 is a
# `node -e` snippet (Node 22.19 is guaranteed on the headless path; no `stat -c`,
# no `jq`). This suite extracts the DOCUMENTED snippet from the agent body and runs
# it on fixtures, so the prose cannot drift from a gate that works:
#   - a 96-byte empty document (the #11143 collapse shape)
#   - an unchanged file after a REFUSED save (stale guard: bytes identical to pre-edit)
#   - a valid saved file (size > 128, children >= 1, hash changed)
#   - a valid file while a `REFUSED save:` was seen anywhere in the session
# pyramid-justified: none needed; unit-level shell test over documented prose.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AGENT="$REPO_ROOT/plugins/soleur/agents/product/design/ux-design-lead.md"

echo "=== pencil post-save hard gate (documented snippet) ==="
echo ""

assert_file_exists "$AGENT" "ux-design-lead agent exists"

# Extract the fenced bash block whose first line is the given marker comment.
extract_block() {
  local marker="$1"
  awk -v m="$marker" '
    /^[[:space:]]*```bash[[:space:]]*$/ { inblk=1; buf=""; first=1; keep=0; next }
    /^[[:space:]]*```[[:space:]]*$/ && inblk { if (keep) { printf "%s", buf; exit } inblk=0; next }
    inblk {
      line=$0; sub(/^   /, "", line)
      if (first) { first=0; if (line == m) keep=1; next }
      buf = buf line "\n"
    }
  ' "$AGENT"
}

PRE_BLOCK="$(extract_block '# pre-edit-sha256')"
GATE_BLOCK="$(extract_block '# post-save-gate')"

if [[ -z "$PRE_BLOCK" || -z "$GATE_BLOCK" ]]; then
  echo "  FAIL: documented snippets not found in $AGENT (markers '# pre-edit-sha256' and '# post-save-gate')"
  FAIL=$((FAIL + 1))
  print_results
  exit 1
fi
assert_contains "$GATE_BLOCK" "node -e" "gate snippet uses node -e"
if [[ "$GATE_BLOCK" == *"stat -c"* || "$GATE_BLOCK" == *"jq "* ]]; then
  echo "  FAIL: gate snippet must not use stat -c or jq"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: gate snippet uses neither stat -c nor jq"
  PASS=$((PASS + 1))
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fixtures. The empty document is exactly 96 bytes (padding inside a JSON string-free
# whitespace tail keeps it parseable).
EMPTY="$WORK/empty.pen"
printf '{"version":"2.21","children":[]}' > "$EMPTY"
while [[ "$(wc -c < "$EMPTY")" -lt 96 ]]; do printf ' ' >> "$EMPTY"; done
assert_eq "96" "$(wc -c < "$EMPTY" | tr -d ' ')" "empty fixture is 96 bytes"

VALID="$WORK/valid.pen"
node -e 'const f=require("fs");const kids=[];for(let i=0;i<3;i++)kids.push({type:"frame",id:"n"+i,name:"Frame "+i,width:320,height:200});f.writeFileSync(process.argv[1],JSON.stringify({version:"2.21",children:kids}))' "$VALID"
UNCHANGED="$WORK/unchanged.pen"
cp "$VALID" "$UNCHANGED"

# run_gate <file> <pre-sha|none> <refused 0|1> -> prints output, returns rc
run_gate() {
  PEN_FILE="$1" PRE_SHA="$2" REFUSED="$3" bash -c "$GATE_BLOCK" 2>&1
}
pre_sha_of() {
  PEN_FILE="$1" bash -c "$PRE_BLOCK" 2>&1
}

# The pre-edit block hashes (and echoes)  the file; a missing (new) file yields "none".
PRE_EMPTY="$(pre_sha_of "$EMPTY")"
assert_eq "64" "${#PRE_EMPTY}" "pre-edit block prints a 64-hex sha256"
assert_eq "none" "$(pre_sha_of "$WORK/does-not-exist.pen")" "pre-edit block prints none for a new file"

# 1. Empty 96-byte document: gate fails on size.
set +e
out="$(run_gate "$EMPTY" "none" 0)"; rc=$?
set -e
assert_eq "1" "$rc" "96-byte empty document fails the gate"
assert_contains "$out" "size" "empty document failure names the size check"

# 2. Unchanged file after a refusal: pre-edit hash equals current, REFUSED seen.
PRE_VALID="$(pre_sha_of "$UNCHANGED")"
set +e
out="$(run_gate "$UNCHANGED" "$PRE_VALID" 1)"; rc=$?
set -e
assert_eq "1" "$rc" "unchanged file after a refusal fails the gate"
assert_contains "$out" "REFUSED save:" "refusal failure tells the agent to surface the REFUSED text"

# 2b. Unchanged file with NO refusal reported still fails (hash equals pre-edit).
set +e
out="$(run_gate "$UNCHANGED" "$PRE_VALID" 0)"; rc=$?
set -e
assert_eq "1" "$rc" "file identical to the pre-edit hash fails the gate"
assert_contains "$out" "unchanged" "identical-hash failure names the unchanged check"

# 3. Valid saved file (new file: pre-edit none): passes.
set +e
out="$(run_gate "$VALID" "none" 0)"; rc=$?
set -e
assert_eq "0" "$rc" "valid saved new file passes the gate"
assert_contains "$out" "POST-SAVE GATE OK" "pass prints POST-SAVE GATE OK"

# 3b. Valid saved file differing from the pre-edit hash of another document: passes.
set +e
out="$(run_gate "$VALID" "$PRE_EMPTY" 0)"; rc=$?
set -e
assert_eq "0" "$rc" "valid saved file with a changed hash passes the gate"

# 4. Valid file but a REFUSED save: appeared in some batch_design or save result.
set +e
out="$(run_gate "$VALID" "none" 1)"; rc=$?
set -e
assert_eq "1" "$rc" "valid file with a REFUSED save: in the session fails the gate"
assert_contains "$out" "REFUSED save:" "refused-session failure names REFUSED save:"

# 5. Larger than 128 bytes but zero children fails on children.
NOKIDS="$WORK/nokids.pen"
node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({version:"2.21",children:[],pad:"x".repeat(200)}))' "$NOKIDS"
set +e
out="$(run_gate "$NOKIDS" "none" 0)"; rc=$?
set -e
assert_eq "1" "$rc" "document with no top-level children fails the gate"
assert_contains "$out" "children" "no-children failure names the children check"

# 6. Missing and unparseable files fail (never a node stack trace as the only signal).
set +e
out="$(run_gate "$WORK/missing.pen" "none" 0)"; rc=$?
set -e
assert_eq "1" "$rc" "missing file fails the gate"
printf 'not json at all %0200d' 0 > "$WORK/garbage.pen"
set +e
out="$(run_gate "$WORK/garbage.pen" "none" 0)"; rc=$?
set -e
assert_eq "1" "$rc" "unparseable file fails the gate"

print_results 21
