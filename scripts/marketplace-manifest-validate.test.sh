#!/usr/bin/env bash
# Guard 4 — pre-merge validation of the marketplace manifest SOURCE.
#
# WHY THIS EXISTS. `infra/github/soleur-marketplace-manifest.json` is the content
# Terraform publishes to `jikig-ai/soleur-marketplace`. After that publication path exists,
# whatever merges into this file reaches every installed user's `claude plugin marketplace add`
# on the next apply. Nothing else validates it: the daily drift workflow reads the PUBLISHED
# artifact, so it can only report a bad manifest AFTER it is live — and once arm C's reconcile
# dispatch exists, a bad source is REPUBLISHED every day while the published-vs-source diff
# reports in-sync, because published genuinely does match source. Guard 4 is the only gate
# between an author and every install.
#
# WHAT IT DRIVES. The real `scripts/marketplace-manifest-validate.sh`, invoked as a subprocess
# against synthesized fixtures — never a re-declaration of its logic inline. A harness that
# pastes the good idiom into a heredoc asserts that a known-good snippet is known-good.
#
# MUTATION MATRIX (plan v2 §Guard Contract → Guard 4). Every row must drive the guard RED:
#   G4.1  source gains a `version` key            -> the #7471 defect; the loop-forever case
#   G4.2  source.url / .path / .source changed    -> repoint / whole-repo-clone regressions
#   G4.3  a SECOND plugins[] entry appended       -> second-member row; positional asserts miss appends
#   G4.4  guard cannot see its input              -> own-dispatch row; must FAIL, never pass-vacuously
set -euo pipefail

# `/tmp` is a machine-global 4 GiB tmpfs shared by every parallel worktree; a direct invocation
# of this suite (the inner loop while editing the validator) inherits the bare `/tmp` because
# only test-all.sh defaults TMPDIR. Without this, verdicts become a function of another
# session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="${MARKETPLACE_VALIDATOR:-$REPO_ROOT/scripts/marketplace-manifest-validate.sh}"
CANONICAL="${MARKETPLACE_MANIFEST:-$REPO_ROOT/infra/github/soleur-marketplace-manifest.json}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ASSERTED=0
pass() { PASS=$((PASS + 1)); ASSERTED=$((ASSERTED + 1)); echo "  PASS: $1"; }
fail() {
  FAIL=$((FAIL + 1)); ASSERTED=$((ASSERTED + 1))
  echo "  FAIL: $1"
  [[ $# -lt 2 ]] || echo "        $2"
}

echo "=== marketplace-manifest-validate ==="

if [[ ! -x "$VALIDATOR" ]]; then
  fail "validator exists and is executable at $VALIDATOR"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi
if [[ ! -f "$CANONICAL" ]]; then
  fail "canonical manifest exists at $CANONICAL"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

# Run the validator and report its exit code. Never pipe into `grep -q`: under `pipefail` an
# early match closes the pipe, the producer takes SIGPIPE (141), and the pipeline reports
# non-zero even though the match succeeded — which on a NEGATIVE assertion fails OPEN.
run_validator() {
  local file="$1" out rc=0
  out="$TMP/out.$$.txt"
  "$VALIDATOR" "$file" > "$out" 2>&1 || rc=$?
  echo "$rc"
}

expect_rc() {
  local label="$1" file="$2" want="$3" got
  got="$(run_validator "$file")"
  if [[ "$got" == "$want" ]]; then
    pass "$label (exit $got)"
  else
    fail "$label" "expected exit $want, got $got"
  fi
}

# --- Positive control ------------------------------------------------------------------------
# The canonical manifest MUST pass. Without this, every RED below is satisfiable by a validator
# that rejects everything, and the suite would certify a guard that blocks all merges.
expect_rc "canonical manifest passes" "$CANONICAL" 0

# --- G4.1: a `version` key on the plugin entry ------------------------------------------------
jq '.plugins[0].version = "1.0.0"' "$CANONICAL" > "$TMP/version-key.json"
expect_rc "G4.1 rejects a version key on .plugins[0]" "$TMP/version-key.json" 1

# --- G4.2: source fields repointed ------------------------------------------------------------
jq '.plugins[0].source.url = "https://github.com/attacker/evil.git"' "$CANONICAL" > "$TMP/bad-url.json"
expect_rc "G4.2a rejects a repointed source.url" "$TMP/bad-url.json" 1

jq '.plugins[0].source.path = "plugins/evil"' "$CANONICAL" > "$TMP/bad-path.json"
expect_rc "G4.2b rejects a repointed source.path" "$TMP/bad-path.json" 1

jq '.plugins[0].source.source = "github"' "$CANONICAL" > "$TMP/bad-source-type.json"
expect_rc "G4.2c rejects source.source != git-subdir" "$TMP/bad-source-type.json" 1

jq '.plugins[0].source.ref = "v0.9.0"' "$CANONICAL" > "$TMP/pinned.json"
expect_rc "G4.2d rejects a ref/sha/commit/branch/tag pin" "$TMP/pinned.json" 1

# --- G4.3: SECOND-MEMBER ROW ------------------------------------------------------------------
# Every assertion in the drift workflow reads `.plugins[0]`, so an APPENDED entry is the shape
# positional checks miss: entry 0 stays perfectly valid while the marketplace serves a second,
# arbitrary plugin under the Soleur name.
jq '.plugins += [{"name":"evil","source":{"source":"git-subdir","url":"https://github.com/attacker/evil.git","path":"x"}}]' \
  "$CANONICAL" > "$TMP/appended.json"
expect_rc "G4.3 rejects an APPENDED second plugins[] entry" "$TMP/appended.json" 1

jq '.plugins[0].name = "not-soleur"' "$CANONICAL" > "$TMP/bad-name.json"
expect_rc "G4.3b rejects a renamed plugin entry" "$TMP/bad-name.json" 1

# --- G4.4: OWN-DISPATCH / ANTI-VACUITY ROW ----------------------------------------------------
# A validator that cannot see its input must FAIL, never report clean. "The file was not there"
# and "the file was fine" must not produce the same verdict.
expect_rc "G4.4a fails closed on a missing file" "$TMP/does-not-exist.json" 1

printf 'not json at all\n' > "$TMP/unparseable.json"
expect_rc "G4.4b fails closed on an unparseable body" "$TMP/unparseable.json" 1

printf '[]\n' > "$TMP/not-an-object.json"
expect_rc "G4.4c fails closed on a non-object top level" "$TMP/not-an-object.json" 1

printf '{"plugins":[]}\n' > "$TMP/empty-plugins.json"
expect_rc "G4.4d fails closed on an empty plugins array" "$TMP/empty-plugins.json" 1

printf '{"name":"x"}\n' > "$TMP/no-plugins.json"
expect_rc "G4.4e fails closed when .plugins is absent" "$TMP/no-plugins.json" 1

# Invoked with NO argument at all — the shape a miswired CI step produces.
rc=0
"$VALIDATOR" > /dev/null 2>&1 || rc=$?
if [[ "$rc" != "0" ]]; then
  pass "G4.4f fails closed when invoked with no argument (exit $rc)"
else
  fail "G4.4f fails closed when invoked with no argument" "expected non-zero, got 0"
fi

# --- Anti-vacuity floor -----------------------------------------------------------------------
# This suite's own dispatch. A harness that silently asserts nothing (a fixture generator that
# no-ops, an early `return`) would otherwise report a clean 0/0.
MIN_ASSERTIONS=14
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  fail "anti-vacuity floor" "only $ASSERTED assertion(s) ran, expected >= $MIN_ASSERTIONS"
fi

echo "=== Results: $PASS passed, $FAIL failed ($ASSERTED assertions) ==="
[[ "$FAIL" -eq 0 ]]
