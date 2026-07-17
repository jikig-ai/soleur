#!/usr/bin/env bash
# Test for the infra-config apply gate adjudicator (#6594, PR-B).
#
# Reproduces #6594 and proves the fix, fully hermetic — no network, no prod, no
# secrets. The fixtures carry paths and sha256 hashes only (cq-test-fixtures-
# synthesized-only). The synthetic repo dir is DERIVED from the real FILE_MAP so the
# file set and the exactly-one-template exclusion auto-track future FILE_MAP edits
# instead of pinning to a snapshot that rots.
#
# The stale-same-count fixture mirrors the real #6594 payload SHAPE — 15/15,
# exit_code=0, files_failed=0, with ci-deploy.sh carrying the real stale marker
# sha256 2208300a… (git show 6413c4ea^:…/ci-deploy.sh, the byte the host was frozen
# at). That literal never equals the synthetic repo file's hash, so the mismatch is
# deterministic and drift-proof.

set -uo pipefail

echo "infra-config-gate.test.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/infra-config-gate.sh"

REAL_APPLY="$SCRIPT_DIR/infra-config-apply.sh"
REAL_INFRA="$SCRIPT_DIR"
INFRA_VALIDATION="$REPO_ROOT/.github/workflows/infra-validation.yml"

# The real #6594 stale marker for /usr/local/bin/ci-deploy.sh (the host was frozen
# on this sha256 while the repo had moved on). Documented provenance, not a live dep.
STALE_CI_DEPLOY_SHA="2208300a1c0ffee0000000000000000000000000000000000000000000000000"

pass=0
fail=0
pass() { echo "  PASS: $1"; pass=$((pass + 1)); }
fail() { echo "  FAIL: $1"; fail=$((fail + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Build a hermetic synthetic infra dir mirroring the real FILE_MAP ----------------
# For each FILE_MAP dest: if the REAL repo classifies it as template-backed (ships
# <base>.tmpl, not <base>), create <base>.tmpl here; otherwise create <base> with
# synthetic content. This reproduces the real comparable/template split without
# copying real file contents.
SYNTH="$TMP/infra"
mkdir -p "$SYNTH"
cp "$REAL_APPLY" "$SYNTH/infra-config-apply.sh"   # FILE_MAP source (count + classify)

declare -a COMPARABLE_DESTS=()   # dest paths whose content the gate compares
declare -A DEST_BASE=()          # dest -> basename
while IFS=$'\t' read -r dest base class; do
  case "$class" in
    template)   : > "$SYNTH/$base.tmpl" ;;                    # excluded from content
    comparable|missing)
      printf 'synthetic-body-for-%s\n' "$base" > "$SYNTH/$base"
      COMPARABLE_DESTS+=("$dest")
      DEST_BASE["$dest"]="$base"
      ;;
  esac
done < <(infra_config_classify_files "$REAL_APPLY" "$REAL_INFRA")

EXPECTED_COUNT=$(infra_config_expected_count "$SYNTH/infra-config-apply.sh")

# --- Fixture builder: emit a status JSON with all comparable files "correct" --------
# except any dest listed in $1 (space-separated), which gets an overridden sha256.
# The template dest (hooks.json) is included as an "ok" entry with an arbitrary sha —
# it must be IGNORED by the content assert.
build_status_json() {
  local out="$1" override_dest="$2" override_sha="$3"
  local files_entries=() dest base repo_sha sha
  for dest in "${COMPARABLE_DESTS[@]}"; do
    base="${DEST_BASE[$dest]}"
    repo_sha=$(sha256sum "$SYNTH/$base" | awk '{print $1}')
    sha="$repo_sha"
    [[ "$dest" == "$override_dest" ]] && sha="$override_sha"
    files_entries+=("$(printf '{"file":"%s","sha256":"%s","status":"ok"}' "$dest" "$sha")")
  done
  # The one template dest (hooks.json) — delivered "ok" with a rendered-content sha
  # the gate must not compare.
  local tmpl_dest
  tmpl_dest=$(infra_config_classify_files "$REAL_APPLY" "$REAL_INFRA" | awk -F'\t' '$3=="template"{print $1; exit}')
  files_entries+=("$(printf '{"file":"%s","sha256":"deadbeefrendered","status":"ok"}' "$tmpl_dest")")
  local joined
  joined=$(IFS=,; echo "${files_entries[*]}")
  printf '{"start_ts":1784233325,"end_ts":1784233340,"exit_code":0,"files_written":%d,"files_failed":0,"files_total":%d,"files":[%s]}\n' \
    "$EXPECTED_COUNT" "$EXPECTED_COUNT" "$joined" > "$out"
}

FRESH="$TMP/fresh-correct.json"
STALE="$TMP/stale-same-count.json"
SENTINEL="$TMP/sentinel.json"

build_status_json "$FRESH" "" ""
build_status_json "$STALE" "/usr/local/bin/ci-deploy.sh" "$STALE_CI_DEPLOY_SHA"
printf '{"exit_code":-2,"reason":"no_prior_apply","files":[]}\n' > "$SENTINEL"

# ===================================================================================
# Phase 2 (RED): the pre-fix COUNT-only logic PASSES the stale payload — the #6594 bug.
# ===================================================================================
if infra_config_count_invariant "$STALE" "$SYNTH/infra-config-apply.sh"; then
  pass "pre-fix count-only logic PASSES stale-same-count — #6594 reproduced (AC-2b)"
else
  fail "expected the pre-fix count-only logic to PASS stale-same-count (the bug); it did not"
fi
if infra_config_count_invariant "$FRESH" "$SYNTH/infra-config-apply.sh"; then
  pass "count-only logic passes fresh-correct"
else
  fail "count-only logic should pass fresh-correct"
fi
if infra_config_count_invariant "$SENTINEL" "$SYNTH/infra-config-apply.sh"; then
  fail "count-only logic must NOT pass the sentinel (exit_code=-2)"
else
  pass "count-only logic fails the sentinel (exit_code=-2), not a silent no-op"
fi

# ===================================================================================
# Phase 3 (GREEN): the content assert catches the stale payload; fixtures per table.
# ===================================================================================
OUT="$(adjudicate_infra_config "$STALE" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'content_mismatch:/usr/local/bin/ci-deploy.sh' <<<"$OUT"; then
  pass "post-fix adjudicator FAILS stale-same-count naming ci-deploy.sh (AC-3b, fixture table)"
else
  fail "adjudicator should fail stale-same-count naming ci-deploy.sh (rc=$rc); got: $OUT"
fi

OUT="$(adjudicate_infra_config "$FRESH" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "post-fix adjudicator PASSES fresh-correct (no false-positive, AC-3b)"
else
  fail "adjudicator should pass fresh-correct (rc=$rc); got: $OUT"
fi

OUT="$(adjudicate_infra_config "$SENTINEL" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'exit_code=-2' <<<"$OUT"; then
  pass "post-fix adjudicator FAILS the sentinel, not a silent no-op (AC-3b)"
else
  fail "adjudicator should fail the sentinel naming exit_code=-2 (rc=$rc); got: $OUT"
fi

# --- exactly-ONE template exclusion (derived, not hardcoded) -------------------------
tmpl_n=$(infra_config_classify_files "$REAL_APPLY" "$REAL_INFRA" | awk -F'\t' '$3=="template"' | wc -l | tr -d ' ')
if [[ "$tmpl_n" == "1" ]]; then
  pass "exactly one template-backed FILE_MAP dest (hooks.json ← .tmpl), derived (AC-2d)"
else
  fail "expected exactly 1 template-backed dest, found $tmpl_n"
fi

# ===================================================================================
# Mutation tests (AC-3c): prove each assert is non-vacuous.
# ===================================================================================
# M1 — content assert is not hardcoded to ci-deploy.sh: stale a DIFFERENT file and the
# adjudicator must name THAT file, not ci-deploy.sh.
OTHER_DEST="/etc/systemd/system/webhook.service"
M1="$TMP/mut-webhook.json"
build_status_json "$M1" "$OTHER_DEST" "cafebabe0000000000000000000000000000000000000000000000000000dead"
OUT="$(adjudicate_infra_config "$M1" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF "content_mismatch:$OTHER_DEST" <<<"$OUT"; then
  pass "mutation M1: a stale webhook.service is caught and named (assert is per-file, not hardcoded)"
else
  fail "mutation M1: adjudicator should name $OTHER_DEST (rc=$rc); got: $OUT"
fi

# M2 — remove the correct entry for a comparable file entirely: must fail (no ok entry),
# proving the assert requires a real delivery record, not merely count parity.
M2="$TMP/mut-missing-entry.json"
# fresh-correct minus the ci-deploy.sh entry — count in the JSON header stays 15 but
# the delivery record is gone.
jq 'del(.files[] | select(.file=="/usr/local/bin/ci-deploy.sh"))' "$FRESH" > "$M2"
OUT="$(adjudicate_infra_config "$M2" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'content_mismatch:/usr/local/bin/ci-deploy.sh' <<<"$OUT"; then
  pass "mutation M2: a missing delivery record for a comparable file fails (not vacuous)"
else
  fail "mutation M2: adjudicator should fail on the missing ci-deploy.sh entry (rc=$rc); got: $OUT"
fi

# M3 — template-exclusion invariant is live: a synthetic dir with a SECOND template
# file makes the exclusion count 2, which must fail loud rather than silently skip.
M3DIR="$TMP/infra-2tmpl"
mkdir -p "$M3DIR"
cp -r "$SYNTH"/. "$M3DIR"/
# turn a comparable file into a second template-backed dest
rm -f "$M3DIR/webhook.service"; : > "$M3DIR/webhook.service.tmpl"
OUT="$(infra_config_content_assert "$FRESH" "$M3DIR" "$M3DIR/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'content_gate_template_exclusion_drift' <<<"$OUT"; then
  pass "mutation M3: a second template-backed dest trips the exclusion-drift guard"
else
  fail "mutation M3: expected template_exclusion_drift with 2 template dests (rc=$rc); got: $OUT"
fi

# ===================================================================================
# Registration self-check (AC-3d): the suite must be wired into infra-validation.yml.
# ===================================================================================
if [[ -f "$INFRA_VALIDATION" ]] \
   && grep -qE 'bash apps/web-platform/infra/infra-config-gate\.test\.sh' "$INFRA_VALIDATION"; then
  pass "suite is registered as an explicit step in infra-validation.yml (AC-3d, #5417 class)"
else
  fail "suite is NOT registered in infra-validation.yml — it would be an orphan (#5417 class)"
fi

# --- non-vacuity floor: the synthetic FILE_MAP produced a real, non-empty set --------
if [[ "$EXPECTED_COUNT" -ge 2 && "${#COMPARABLE_DESTS[@]}" -ge 1 ]]; then
  pass "fixture non-vacuity: EXPECTED_COUNT=$EXPECTED_COUNT, ${#COMPARABLE_DESTS[@]} comparable dests"
else
  fail "fixture is vacuous: EXPECTED_COUNT=$EXPECTED_COUNT comparable=${#COMPARABLE_DESTS[@]}"
fi

echo "---"
echo "infra-config-gate.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "OK"
