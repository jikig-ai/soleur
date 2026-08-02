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
  # EVERY template dest (hooks.json, /etc/default/soleur-doppler-token) — delivered "ok" with
  # a rendered-content sha the gate must not BYTE-compare, but which it DOES require to be
  # present per-dest (#7095 R7). Emitting only the first template dest here would make the
  # fixture, not the gate, decide the outcome the moment a second one is added.
  local tmpl_dest
  while read -r tmpl_dest; do
    [[ -n "$tmpl_dest" ]] || continue
    files_entries+=("$(printf '{"file":"%s","sha256":"deadbeefrendered","status":"ok"}' "$tmpl_dest")")
  done < <(infra_config_classify_files "$REAL_APPLY" "$REAL_INFRA" | awk -F'\t' '$3=="template"{print $1}')
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

# --- exactly-TWO template exclusions (derived, not hardcoded) ------------------------
# hooks.json ← hooks.json.tmpl, and /etc/default/soleur-doppler-token ←
# soleur-doppler-token.tmpl (#7095). The count is a reviewed constant on purpose: a THIRD
# template dest must red this until someone deliberately widens the set of files excluded
# from the byte compare.
tmpl_n=$(infra_config_classify_files "$REAL_APPLY" "$REAL_INFRA" | awk -F'\t' '$3=="template"' | wc -l | tr -d ' ')
if [[ "$tmpl_n" == "2" ]]; then
  pass "exactly two template-backed FILE_MAP dests (hooks.json, soleur-doppler-token), derived (AC-2d)"
else
  fail "expected exactly 2 template-backed dests, found $tmpl_n"
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

# M3 — template-exclusion invariant is live: a synthetic dir with one MORE template
# file makes the exclusion count 3 (baseline is 2 since #7095), which must fail loud
# rather than silently skip.
M3DIR="$TMP/infra-2tmpl"
mkdir -p "$M3DIR"
cp -r "$SYNTH"/. "$M3DIR"/
# turn a comparable file into one more template-backed dest
rm -f "$M3DIR/webhook.service"; : > "$M3DIR/webhook.service.tmpl"
OUT="$(infra_config_content_assert "$FRESH" "$M3DIR" "$M3DIR/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'content_gate_template_exclusion_drift' <<<"$OUT"; then
  pass "mutation M3: an extra template-backed dest trips the exclusion-drift guard"
else
  fail "mutation M3: expected template_exclusion_drift with 3 template dests (rc=$rc); got: $OUT"
fi

# M4 — the `missing` class arm (repo/FILE_MAP drift) is live. A FILE_MAP dest whose repo
# file is absent from the checkout (nor a .tmpl) must fail loud, not certify an
# un-checkable delivery. Build a synthetic dir with one comparable file removed → that
# dest classifies `missing`. (Review test-design F2: this arm had zero prior coverage
# because the fixture builder created a real file for both comparable AND missing dests.)
M4DIR="$TMP/infra-missing"
mkdir -p "$M4DIR"
cp -r "$SYNTH"/. "$M4DIR"/
rm -f "$M4DIR/ci-deploy.sh"   # neither ci-deploy.sh nor ci-deploy.sh.tmpl → missing
OUT="$(infra_config_content_assert "$FRESH" "$M4DIR" "$M4DIR/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'content_gate_repo_file_missing:/usr/local/bin/ci-deploy.sh' <<<"$OUT"; then
  pass "mutation M4: a FILE_MAP dest with no repo file fails loud (missing-class arm live)"
else
  fail "mutation M4: expected content_gate_repo_file_missing for the removed repo file (rc=$rc); got: $OUT"
fi

# M5 — the `status != "ok"` guard is independently live. A delivery entry that is PRESENT
# and carries a MATCHING sha but reports status:"failed" must still fail — the gate's
# contract is "ok delivery", not "a sha exists". (Review test-design F3: M2 only ever hit
# the empty-sha clause via entry deletion, leaving the status clause vacuously covered.)
M5="$TMP/mut-status-failed.json"
jq '(.files[] | select(.file=="/usr/local/bin/ci-deploy.sh") | .status) = "failed"' "$FRESH" > "$M5"
OUT="$(adjudicate_infra_config "$M5" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF 'content_mismatch:/usr/local/bin/ci-deploy.sh' <<<"$OUT"; then
  pass "mutation M5: a present, sha-matching, status:failed delivery fails (status guard live)"
else
  fail "mutation M5: expected content_mismatch for the status:failed entry (rc=$rc); got: $OUT"
fi

# M6 (#7095 R7) — TIER 1 of the template assert is live: a template-backed dest whose
# delivery entry is ABSENT must fail. Before #7095 a template dest was skipped entirely, so
# a status JSON that simply never mentioned it passed on aggregate count alone — the exact
# latched false-green shape of #6594, and the one that would have hidden a non-delivered
# credential. Deleting the entry must now be caught and NAMED.
M6="$TMP/mut-template-missing.json"
TMPL_DEST_CRED="/etc/default/soleur-doppler-token"
jq --arg d "$TMPL_DEST_CRED" 'del(.files[] | select(.file==$d))' "$FRESH" > "$M6"
OUT="$(adjudicate_infra_config "$M6" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF "content_mismatch:$TMPL_DEST_CRED" <<<"$OUT"; then
  pass "mutation M6: a template-backed dest with no delivery entry fails and is named (tier-1 live)"
else
  fail "mutation M6: expected content_mismatch for the absent $TMPL_DEST_CRED entry (rc=$rc); got: $OUT"
fi

# M7 (#7095 R7) — TIER 2 is live AND is genuinely opt-in. Two halves, because a guard that
# only ever runs one way proves nothing:
#   (a) with the rendered-digest env var set to a value that does NOT match the fixture's
#       "deadbeefrendered", the assert must FAIL — otherwise the byte compare is decorative;
#   (b) with the env var UNSET, the same fixture must PASS — otherwise every caller that
#       cannot render the secret (i.e. everything except the apply workflow) is broken.
M7VAR="INFRA_CONFIG_RENDERED_SHA_$(printf '%s' "$TMPL_DEST_CRED" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]')"
OUT="$(env "$M7VAR=0000000000000000000000000000000000000000000000000000000000000000" \
  bash -c 'source "$1"; infra_config_content_assert "$2" "$3" "$4"' _ \
  "$REAL_INFRA/infra-config-gate.sh" "$FRESH" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && grep -qF "content_mismatch:$TMPL_DEST_CRED" <<<"$OUT"; then
  pass "mutation M7a: a rendered-sha mismatch on a template dest fails (tier-2 byte compare live)"
else
  fail "mutation M7a: expected content_mismatch for the rendered-sha mismatch (rc=$rc); got: $OUT"
fi
OUT="$(env -u "$M7VAR" \
  bash -c 'source "$1"; infra_config_content_assert "$2" "$3" "$4"' _ \
  "$REAL_INFRA/infra-config-gate.sh" "$FRESH" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass "mutation M7b: with no rendered-sha supplied the same fixture PASSES (tier-2 is opt-in, not a hard dependency)"
else
  fail "mutation M7b: content assert must pass without the rendered-sha env var (rc=$rc); got: $OUT"
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

# ===================================================================================
# Production call-site pin (review test-design F1): the whole point of this gate is that
# apply-deploy-pipeline-fix.yml INVOKES the content assert TERMINALLY. Testing the
# adjudicator's logic in isolation is vacuous if the workflow doesn't call it, or calls
# it inside the retry loop (any-of-3 coin flip, #6594). This test pins that wiring so
# deleting or in-loop-moving the call reds the suite — not just the workflow.
# ===================================================================================
APPLY_WF="$REPO_ROOT/.github/workflows/apply-deploy-pipeline-fix.yml"
if [[ ! -f "$APPLY_WF" ]]; then
  fail "apply-deploy-pipeline-fix.yml not found — cannot verify the gate is wired into prod"
else
  # (a) the terminal adjudication is called at all
  adj_line=$(grep -nE '(^|[^_[:alnum:]])adjudicate_infra_config[[:space:]]+/tmp/' "$APPLY_WF" | head -1 | cut -d: -f1)
  # (b) the in-loop fast-path uses count_invariant (NOT adjudicate)
  ci_line=$(grep -nE 'infra_config_count_invariant[[:space:]]+/tmp/' "$APPLY_WF" | head -1 | cut -d: -f1)
  if [[ -z "$adj_line" ]]; then
    fail "apply-deploy-pipeline-fix.yml does NOT call adjudicate_infra_config — the #6594 content assert is DEAD in production"
  elif [[ -z "$ci_line" ]]; then
    fail "apply-deploy-pipeline-fix.yml does NOT use infra_config_count_invariant as the poll-loop break"
  else
    # (c) the count_invariant call is inside a loop that CLOSES before the adjudicate call:
    #     require a `done` line strictly between them → adjudicate is terminal, outside the loop.
    between_done=$(awk -v a="$ci_line" -v b="$adj_line" 'NR>a && NR<b && $1=="done"{print NR; exit}' "$APPLY_WF")
    if [[ "$ci_line" -lt "$adj_line" && -n "$between_done" ]]; then
      pass "gate is wired into prod: count_invariant in-loop (L$ci_line), adjudicate_infra_config terminal after the loop's done (L$between_done < L$adj_line) — content assert is NOT any-of-3 (F1)"
    else
      fail "adjudicate_infra_config is not terminal: count L$ci_line, adjudicate L$adj_line, loop-done-between=${between_done:-none}. A content assert inside the retry loop is the #6594 coin flip."
    fi
  fi
fi

# ===================================================================================
# #7103 R2 3.8 — the activation contract, staged.
# ===================================================================================
# Build a v2 frame: the FRESH files payload plus a caller-supplied restarts array and
# schema_version. `changed` is set on every file entry so the "all unchanged" case below is a
# realistic frame rather than a hand-trimmed one.
build_status_json_v2() {
  local out="$1" schema="$2" restarts="$3" changed="${4:-true}"
  local files
  files=$(jq -c --argjson c "$changed" '[.files[] | . + {changed: $c}]' "$FRESH")
  jq -n --argjson sv "$schema" --argjson f "$files" --argjson r "$restarts" \
        --argjson n "$EXPECTED_COUNT" \
    '{schema_version:$sv, start_ts:1784233325, end_ts:1784233340, exit_code:0,
      files_written:$n, files_failed:0, files_total:$n, files:$f, restarts:$r}' > "$out"
}

# Every unit the handler declares, verdict-complete and healthy.
RESTARTS_OK='[]'
UNITS_ALL=$(infra_config_expected_restart_units "$SYNTH/infra-config-apply.sh")
RESTARTS_OK=$(jq -n --arg units "$UNITS_ALL" \
  '[$units | split("\n") | .[] | select(length>0) |
    {unit:., action:"restarted", reason:"stale_config", rc:0, active:"active",
     nrestarts:1, exec_main_start_ts_before:100, exec_main_start_ts_after:200}]')
N_UNITS=$(jq 'length' <<<"$RESTARTS_OK")

if [[ "$N_UNITS" -ge 1 ]]; then
  pass "activation fixture non-vacuity: derived $N_UNITS unit(s) from the handler's RESTART_MAP"
else
  fail "derived ZERO units from RESTART_MAP — every activation assertion below would be vacuous"
fi

# (a) STAGED: a handler predating the contract must WARN and PASS. Failing here would red
# adjudicate_infra_config, skipping the if:success()-gated redeploy — so files land and
# activation never happens, with the only repair route being the leg that may be dead.
V1="$TMP/v1-no-schema.json"
build_status_json_v2 "$V1" 0 '[]'
jq 'del(.schema_version) | del(.restarts)' "$V1" > "$V1.tmp" && mv "$V1.tmp" "$V1"
if out=$(adjudicate_infra_config "$V1" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1); then
  if grep -q 'infra_config_handler_predates_restarts' <<<"$out"; then
    pass "schema_version absent: warns by name and PASSES (staged rollout)"
  else
    fail "schema_version absent passed but emitted no named warning: $out"
  fi
else
  fail "schema_version absent must PASS (warn-only) — it failed: $out"
fi

# (b) A complete, healthy v2 frame passes.
V2OK="$TMP/v2-ok.json"
build_status_json_v2 "$V2OK" 2 "$RESTARTS_OK"
if adjudicate_infra_config "$V2OK" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  pass "v2 frame with every unit restarted and active PASSES"
else
  fail "a healthy v2 frame must pass: $(adjudicate_infra_config "$V2OK" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"
fi

# (c) Each activation failure enum must RED the gate. One arm per enum — they are distinct
# defects (a unit that died after fork, one that never re-exec'd, a missing grant) and a
# single representative case would let two of the three regress unnoticed.
for bad_reason in noop_not_active restart_did_not_advance sudo_denied; do
  VBAD="$TMP/v2-$bad_reason.json"
  bad_restarts=$(jq --arg r "$bad_reason" \
    '(.[0].action) = "failed" | (.[0].reason) = $r' <<<"$RESTARTS_OK")
  build_status_json_v2 "$VBAD" 2 "$bad_restarts"
  if adjudicate_infra_config "$VBAD" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
    fail "activation reason=$bad_reason must FAIL the gate — it passed"
  else
    pass "activation reason=$bad_reason REDS the gate (delivered but not running)"
  fi
done

# (d) A non-zero rc reds the gate even when the reason looks benign.
VRC="$TMP/v2-rc.json"
build_status_json_v2 "$VRC" 2 "$(jq '(.[0].rc) = 1' <<<"$RESTARTS_OK")"
if adjudicate_infra_config "$VRC" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  fail "a non-zero activation rc must FAIL the gate — it passed"
else
  pass "non-zero activation rc REDS the gate"
fi

# (e) A v2 frame MISSING a unit's verdict reds the gate. An absent entry is indistinguishable
# from a unit that was never considered, so silence must not read as success.
VMISS="$TMP/v2-missing.json"
build_status_json_v2 "$VMISS" 2 '[]'
if adjudicate_infra_config "$VMISS" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  fail "a v2 frame with no verdicts must FAIL the gate — it passed"
else
  pass "v2 frame missing unit verdicts REDS the gate"
fi

# (f) A SKIPPED, inactive unit WARNS but passes. Deliberate narrowing of the plan's
# "fail on active != active": every case where we acted and it did not take is already covered
# by (c). Failing on a unit we never attempted would permanently red the gate on a host where
# that unit legitimately does not run (inngest-heartbeat is co-location dependent). Whether a
# unit should be shipping is R3's question, answered at the sink.
VSKIP="$TMP/v2-skipped.json"
build_status_json_v2 "$VSKIP" 2 \
  "$(jq '(.[0].action) = "skipped" | (.[0].reason) = "unit_inactive" | (.[0].active) = "inactive"' <<<"$RESTARTS_OK")"
if out=$(adjudicate_infra_config "$VSKIP" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1); then
  if grep -q 'infra_config_unit_not_active' <<<"$out"; then
    pass "a skipped inactive unit warns by name and PASSES (topology, not a delivery defect)"
  else
    fail "skipped inactive unit passed with no named warning: $out"
  fi
else
  fail "a skipped inactive unit must not red the gate: $out"
fi

# (g) An apply that changed NOTHING still passes. After the mtime-preservation fix a steady-state
# re-delivery reports every file changed:false and every unit not_stale; if that combination did
# not pass, the gate would red on every apply that correctly had no work to do.
VNOOP="$TMP/v2-allunchanged.json"
build_status_json_v2 "$VNOOP" 2 \
  "$(jq '[.[] | .action = "skipped" | .reason = "not_stale" | .active = "active"]' <<<"$RESTARTS_OK")" \
  false
if adjudicate_infra_config "$VNOOP" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  pass "steady state (all files changed:false, all units not_stale) PASSES"
else
  fail "steady state must pass: $(adjudicate_infra_config "$VNOOP" "$SYNTH" "$SYNTH/infra-config-apply.sh" 2>&1)"
fi

# (h) The contract is TERMINAL-ONLY. Adding it to the poll break-condition would burn all three
# attempts on a slow-but-succeeding reconciliation and turn a retryable wait into a terminal red.
if grep -n 'schema_version' "$REAL_INFRA/infra-config-gate.sh" \
   | awk -F: -v s="$(grep -n '^infra_config_count_invariant()' "$REAL_INFRA/infra-config-gate.sh" | cut -d: -f1)" \
             -v e="$(grep -n '^infra_config_content_assert()'  "$REAL_INFRA/infra-config-gate.sh" | cut -d: -f1)" \
             '$1>s && $1<e' | grep -q .; then
  fail "the activation contract leaked into infra_config_count_invariant — the poll break-condition must stay timing-independent"
else
  pass "activation contract is absent from the poll break-condition (terminal only)"
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
