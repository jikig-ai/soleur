#!/usr/bin/env bash
# Verifies the stuck-draft-release deadlock fix in
# .github/workflows/reusable-release.yml (#4902).
#
# Background: the release pipeline creates GitHub Releases as `--draft` (a draft
# materializes NO git tag), then a Finalise step flips `--draft=false` to publish.
# If a transient failure orphans a draft, the OLD idempotency check
# (`gh release view "$TAG"` -> exists=true -> skip) found the orphaned draft on
# every later run and skipped re-creation FOREVER, freezing the git-tag baseline
# and the computed BUILD_VERSION. The fix makes idempotency draft-aware: a draft
# yields exists=false + draft_exists=true so the Finalise step re-publishes it
# (self-heal). The logic is prefix-agnostic (v / web-v / telegram-v).
#
# This test removes the live GitHub API from the assertion path by executing the
# REAL `Check idempotency` run-block (extracted verbatim from the workflow) under
# a deterministic `gh` stub, then statically asserts the create/finalise gating
# wiring. Run via:  bash plugins/soleur/test/reusable-release-idempotency.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/reusable-release.yml"

PASS=0
FAIL=0
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extract the `Check idempotency` step's `run:` block verbatim from the workflow.
# awk walks from the step's `- name: Check idempotency` to the next `- name:`,
# captures the lines after `run: |`, and dedents to the block-scalar base indent.
# Keeping the workflow as the single source of truth (no copy-paste of the logic)
# means this test exercises the REAL shell that ships.
# ---------------------------------------------------------------------------
extract_run_block() {
  local step_name="$1"
  awk -v target="$step_name" '
    $0 ~ "- name: " target { instep=1; next }
    instep && /^[[:space:]]*- name: / { exit }
    instep && /^[[:space:]]*run: \|/ { inrun=1; next }
    inrun {
      if (base == 0) {
        match($0, /^[[:space:]]*/); base = RLENGTH
      }
      print substr($0, base + 1)
    }
  ' "$WF"
}

IDEMPOTENCY_BLOCK="$TMP/idempotency.sh"
extract_run_block "Check idempotency" > "$IDEMPOTENCY_BLOCK"

if [[ ! -s "$IDEMPOTENCY_BLOCK" ]]; then
  fail "could not extract 'Check idempotency' run block from $WF"
  echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
  exit 1
fi

# ---------------------------------------------------------------------------
# Deterministic `gh` stub. Behavior is driven by MOCK_GH_STATE:
#   absent     -> release does not exist
#   published  -> release exists, isDraft=false
#   draft      -> release exists (orphaned), isDraft=true
# Records create/edit invocations to $GH_TRACE so callers can assert side effects.
# ---------------------------------------------------------------------------
GH_STUB_DIR="$TMP/bin"
mkdir -p "$GH_STUB_DIR"
cat > "$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
# args: release <subcmd> <tag> [flags...]
sub="${2:-}"
case "$sub" in
  view)
    has_json=0
    for a in "$@"; do [[ "$a" == "--json" ]] && has_json=1; done
    case "$MOCK_GH_STATE" in
      published)
        if [[ "$has_json" == 1 ]]; then echo '{"isDraft":false}'; fi
        exit 0 ;;
      draft)
        if [[ "$has_json" == 1 ]]; then echo '{"isDraft":true}'; fi
        exit 0 ;;
      *) exit 1 ;;  # absent
    esac ;;
  edit)
    printf 'edit %s\n' "$*" >> "$GH_TRACE"
    exit 0 ;;
  create)
    printf 'create %s\n' "$*" >> "$GH_TRACE"
    exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$GH_STUB_DIR/gh"

# Run the extracted idempotency block for one scenario; echo the resulting
# `exists` and `draft_exists` outputs as "<exists> <draft_exists>".
run_idempotency() {
  local state="$1" tag="$2"
  local out="$TMP/gho.$$.$RANDOM"
  : > "$out"
  MOCK_GH_STATE="$state" \
  GH_TRACE="$TMP/trace.$$" \
  GITHUB_OUTPUT="$out" \
  TAG="$tag" \
  PATH="$GH_STUB_DIR:$PATH" \
    bash "$IDEMPOTENCY_BLOCK" >/dev/null 2>&1
  local e d
  e=$(grep -E '^exists=' "$out" | tail -1 | cut -d= -f2)
  d=$(grep -E '^draft_exists=' "$out" | tail -1 | cut -d= -f2)
  echo "${e:-<unset>} ${d:-<unset>}"
}

echo "=== reusable-release idempotency (draft-aware self-heal) tests ==="
echo ""

# ---------------------------------------------------------------------------
# T1: decision matrix (the core of #4902). Lane-agnostic via web-v tag.
# ---------------------------------------------------------------------------
echo "T1: Check idempotency decision matrix"

r=$(run_idempotency absent "web-v0.101.100")
[[ "$r" == "false false" ]] && pass "absent  -> exists=false draft_exists=false" \
  || fail "absent  -> got '$r', want 'false false'"

r=$(run_idempotency published "web-v0.101.100")
[[ "$r" == "true false" ]] && pass "published-> exists=true  draft_exists=false" \
  || fail "published-> got '$r', want 'true false'"

r=$(run_idempotency draft "web-v0.101.100")
[[ "$r" == "false true" ]] && pass "draft   -> exists=false draft_exists=true (self-heal)" \
  || fail "draft   -> got '$r', want 'false true' (orphaned draft must NOT lock the pipeline)"

# ---------------------------------------------------------------------------
# T2: lane-agnostic (AC6) — identical decision for v / web-v / telegram-v in the
# draft scenario (no prefix-specific branch leaked into the logic).
# ---------------------------------------------------------------------------
echo "T2: lane-agnostic draft decision"
for tag in "v0.5.0" "web-v0.101.100" "telegram-v0.3.0"; do
  r=$(run_idempotency draft "$tag")
  [[ "$r" == "false true" ]] && pass "draft($tag) -> false true" \
    || fail "draft($tag) -> got '$r', want 'false true'"
done

# ---------------------------------------------------------------------------
# T3: create-step gating (AC2/AC4) — create must NOT fire when an orphaned draft
# already exists (gh release create errors on an existing tag); it is gated on
# both exists==false AND draft_exists==false.
# ---------------------------------------------------------------------------
echo "T3: Create step gated on draft_exists == 'false'"
create_if=$(awk '
  /- name: Create GitHub Release \(as draft\)/ { f=1; next }
  f && /^[[:space:]]*if:/ { print; exit }
' "$WF")
if grep -qE "idempotency\.outputs\.draft_exists == 'false'" <<<"$create_if"; then
  pass "create if: requires draft_exists == 'false'"
else
  fail "create if: must gate on draft_exists == 'false' (got: ${create_if:-<none>})"
fi

# ---------------------------------------------------------------------------
# T4: finalise-step self-heal gate (AC2) — Finalise must publish when EITHER a
# new draft was created OR an orphaned draft exists.
# ---------------------------------------------------------------------------
echo "T4: Finalise step re-publishes orphaned drafts"
finalise_if=$(awk '
  /- name: Finalise release \(publish draft\)/ { f=1; next }
  f && /^[[:space:]]*if:/ { print; got=1 }
  f && got && /draft_exists/ { print }
  f && /^[[:space:]]*env:/ { exit }
' "$WF")
if grep -qE "idempotency\.outputs\.draft_exists == 'true'" <<<"$finalise_if"; then
  pass "finalise if: includes draft_exists == 'true' disjunct (self-heal)"
else
  fail "finalise if: must publish when draft_exists == 'true' (got: ${finalise_if:-<none>})"
fi

# ---------------------------------------------------------------------------
# T5: immutable-release flow preserved (AC3) — create step still uses --draft.
# ---------------------------------------------------------------------------
echo "T5: --draft create flow preserved"
create_block=$(awk '
  /- name: Create GitHub Release \(as draft\)/ { f=1 }
  f { print }
  f && /Created draft release/ { exit }
' "$WF")
if grep -qE -- '--draft$' <<<"$create_block"; then
  pass "create step still passes --draft (immutable-upload flow intact)"
else
  fail "create step must keep --draft (immutable-release 422 mitigation)"
fi

echo ""
echo "=== Results: $PASS/$((PASS + FAIL)) passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
