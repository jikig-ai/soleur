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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
# A SECOND, INDEPENDENT PRODUCER FOR THE TALLY (#7104 PR-B review).
#
# `$pass` is a counter incremented by one function, so the assertion-count floor below had
# exactly ONE producer and two one-line mutations defeated it:
#
#   pass=$((pass + 2))         -> the suite reported 260 passed against a floor of 130, so the
#                                 floor passed while HALF the arms could have been deleted.
#   GATE_MIN_ASSERTIONS=$pass  -> the floor compares the counter against itself. Tautology; it
#                                 can never fail, at any count.
#
# The emitted PASS: lines are the second producer. `pass()` prints one line per assertion and
# appends one line here, so the counter and the log can only agree if each increment
# corresponds to a real assertion. `pass=$((pass + 2))` desynchronises them immediately.
#
# THE TWO PRODUCERS WERE ONE FUNCTION (#7104 PR-B review, D2).
#
# The paragraph above claims "the emitted PASS: lines are the second producer". They were not:
# both the counter and the log were written by the SAME one-line `pass()`, so one edit moved
# both and the reconciliation compared a value against itself by a longer route. Measured:
#
#     pass() { echo "  PASS: $1"; printf 'PASS\nPASS\n' >> "$PASSLOG"; pass=$((pass + 2)); }
#
# reported 264 passed, 0 failed, OK, rc=0 — reconciliation clean, source-literal check clean,
# floor of 132 cleared with 66 real assertions deletable. The test for independence is: can one
# edit move both? It could.
#
# The genuinely independent producer is this suite's OWN STDOUT, captured OUTSIDE `pass()` by
# the redirection below. `pass=$((pass + 2))` cannot touch it, so the counter and the printed
# output diverge and the teardown says so. A mutation that instead prints each line TWICE keeps
# all three in sync — and is caught by the consecutive-duplicate check at teardown, because it
# doubles the output a human reads.
#
# fd 3 holds the real stdout so the tee can be shut down deterministically at teardown: closing
# fd 1 gives tee EOF, which is what makes the capture flushed and complete before it is counted.
PASSLOG="$TMP/pass.log"
: > "$PASSLOG"
STDOUT_LOG="$TMP/stdout.log"
: > "$STDOUT_LOG"
exec 3>&1
exec 1> >(tee -a "$STDOUT_LOG" >&3)

pass() { echo "  PASS: $1"; printf 'PASS\n' >> "$PASSLOG"; pass=$((pass + 1)); }
fail() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Shut the capture down and wait for tee to flush. Called once, at teardown, before anything
# reads $STDOUT_LOG. Without the settle the count is a race against a subprocess.
close_stdout_capture() {
  exec 1>&3 3>&-
  local i=0 prev=-1 now
  while [[ "$i" -lt 50 ]]; do
    now=$(wc -c < "$STDOUT_LOG" 2>/dev/null || echo 0)
    [[ "$now" == "$prev" && "$now" != "0" ]] && return 0
    prev="$now"; i=$((i + 1)); sleep 0.02
  done
  return 0
}

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
# #7104 PR-B: the ~240-line gate body moved verbatim out of the workflow into
# infra-config-verify.sh (plan R22.2, ADR-150 shape). The pin therefore has TWO
# clauses now, and BOTH are load-bearing: clause (1) proves production still
# reaches this code at all, clause (2) proves the code it reaches still wires
# count_invariant in-loop and adjudicate terminally. Asserting only (2) would
# certify a script no step invokes — the exact vacuity F1 exists to prevent,
# one indirection deeper.
VERIFY_SH="$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh"
if [[ ! -f "$APPLY_WF" ]]; then
  fail "apply-deploy-pipeline-fix.yml not found — cannot verify the gate is wired into prod"
elif [[ ! -f "$VERIFY_SH" ]]; then
  fail "infra-config-verify.sh not found — the extracted gate body is missing, so production runs nothing"
else
  # (1) production INVOKES the extracted body. Anchored on the `run:` command
  #     shape, not a bare basename: a bare grep would match a comment naming
  #     the file (cq-assert-anchor-not-bare-token).
  invoke_line=$(grep -nE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+.*infra-config-verify\.sh' "$APPLY_WF" | head -1 | cut -d: -f1)
  # (2) the terminal adjudication is called at all, inside the extracted body
  adj_line=$(grep -nE '(^|[^_[:alnum:]])adjudicate_infra_config[[:space:]]+"\$STATUS_RESPONSE"' "$VERIFY_SH" | head -1 | cut -d: -f1)
  # (3) the in-loop fast-path uses count_invariant (NOT adjudicate)
  ci_line=$(grep -nE 'infra_config_count_invariant[[:space:]]+"\$STATUS_RESPONSE"' "$VERIFY_SH" | head -1 | cut -d: -f1)
  if [[ -z "$invoke_line" ]]; then
    fail "apply-deploy-pipeline-fix.yml does NOT invoke infra-config-verify.sh — the extracted gate is DEAD in production"
  elif [[ -z "$adj_line" ]]; then
    fail "infra-config-verify.sh does NOT call adjudicate_infra_config — the #6594 content assert is DEAD in production"
  elif [[ -z "$ci_line" ]]; then
    fail "infra-config-verify.sh does NOT use infra_config_count_invariant as the poll-loop break"
  else
    # (4) the count_invariant call is inside a loop that CLOSES before the adjudicate call:
    #     require a `done` line strictly between them → adjudicate is terminal, outside the loop.
    #
    #     COUNTING, not first-match (plan R19.2, measured — task 8.1). The original scan was
    #     `awk '… $1=="done" {print NR; exit}'`: first match, first FIELD, so indentation is
    #     irrelevant and ANY nested `for`/`while`/`until` (or a `done < <(…)`) between the two
    #     anchors satisfies it. Measured against the pre-split design: with
    #     adjudicate_infra_config moved INTO the loop and a nested `done` above it, the pin
    #     still reported PASS (`ci=2 adj=6 between_done=5`) — #6594's coin-flip mutation stayed
    #     green and AC21 failed at implementation time. Asserting EXACTLY ONE `done` strictly
    #     between the anchors also makes "this region contains no nested loop" enforced rather
    #     than hoped for, which is what row 5 of Guard 2's matrix mutates.
    between_done=$(awk -v a="$ci_line" -v b="$adj_line" 'NR>a && NR<b && $1=="done"{print NR; exit}' "$VERIFY_SH")
    done_count=$(awk -v a="$ci_line" -v b="$adj_line" 'NR>a && NR<b && $1=="done"{n++} END{print n+0}' "$VERIFY_SH")
    if [[ "$ci_line" -lt "$adj_line" && "$done_count" -eq 1 ]]; then
      pass "gate is wired into prod: workflow invokes infra-config-verify.sh (L$invoke_line); inside it count_invariant is in-loop (L$ci_line) and adjudicate_infra_config is terminal after the loop's SINGLE done (L$between_done < L$adj_line) — content assert is NOT any-of-3 (F1)"
    else
      fail "adjudicate_infra_config is not terminal in infra-config-verify.sh: count L$ci_line, adjudicate L$adj_line, done-lines-strictly-between=$done_count (expected exactly 1). A content assert inside the retry loop is the #6594 coin flip; a SECOND done means a nested loop the first-match scan was structurally unable to see (R19.2)."
    fi

    # ---------------------------------------------------------------------------------------
    # THE SAME PROPERTY, MEASURED STRUCTURALLY (#7104 PR-B review) — because the count above
    # CANCELS under composition.
    #
    # `done_count == 1` is a scalar over a window, and two mutations that each break it can be
    # applied together so that it comes back to 1: move adjudicate_infra_config INTO the poll
    # loop (row G2-1, which removes the real closing `done` from the window) and add a nested
    # loop above it (row G2-5, which puts a different `done` back). Measured: the composite
    # scored done_count=1 and the suite stayed green, with the content assert restored to the
    # any-of-3 coin flip #6594 exists to prevent. Neither row alone survives; together they do.
    #
    # A count cannot express "outside every loop". Nesting DEPTH can, and it does not cancel:
    # adjudicate must sit at depth 0 and count_invariant at depth >= 1, and no arrangement of
    # extra loops makes an in-loop call read as depth 0.
    #
    # The scanner carries a POSITIVE CONTROL. If its tokenizer silently stopped matching, every
    # line would measure depth 0 and the adjudicate assertion would pass vacuously — so it also
    # requires having SEEN at least one loop, which is the same failure the count's own
    # cardinality floor guards against one level up.
    LOOPDEPTH=$(python3 - "$VERIFY_SH" "$adj_line" "$ci_line" "$SCRIPT_DIR/infra-config-shellscan.py" <<'PYEOF'
import importlib.util, sys

path, adj, ci, scanner = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]

# THE SHARED SCANNER (#7104 PR-B review, D1). This block used to carry its OWN three-line
# stripper — comments and quotes, but NOT `[[ ]]` test spans — while the allow-list sweep 300
# lines below stripped all three. That divergence IS D1, and the panel executed it: two balanced
# phantom lines
#
#     for _n in 1; do :; done          # restores done_count == 1
#     [[ $PHASE == done ]] || :        # depth 1 -> 0
#     adjudicate_infra_config ... && break
#     [[ $PHASE == do ]] || :          # rebalance
#
# zero the depth at the assert and rebalance the file, restoring #6594's any-of-3 coin flip with
# this suite reporting 132 passed, 0 failed. Neither the positive control nor the balance check
# protects — maxdepth reads 2, HIGHER than baseline, and the phantoms balance by construction.
#
# Both halves of the fix live in the shared module: `[[ ]]` spans are stripped like quotes are
# (a test span holds values, not commands), and `do`/`done` are counted only in COMMAND
# position, so `echo done` no longer decrements the counter either.
_spec = importlib.util.spec_from_file_location('shellscan', scanner)
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)

src = open(path, encoding='utf-8').read()
depth_at, maxdepth, depth = _m.loop_depth_map(src)

problems = []
if maxdepth < 1:
    problems.append("the loop scanner saw no loop at all (maxdepth=0) — its verdict is vacuous")
if depth != 0:
    problems.append("loop tokens do not balance over the file (ends at depth %d)" % depth)
if depth_at.get(adj, -1) != 0:
    problems.append("adjudicate_infra_config (L%d) sits at loop depth %d, expected 0 — a content "
                    "assert inside the retry loop is the #6594 any-of-N coin flip"
                    % (adj, depth_at.get(adj, -1)))
if depth_at.get(ci, 0) < 1:
    problems.append("infra_config_count_invariant (L%d) sits at loop depth %d, expected >= 1 — the "
                    "poll-loop fast path is no longer inside the poll loop"
                    % (ci, depth_at.get(ci, 0)))
print("MAXDEPTH=%d ADJ=%d CI=%d" % (maxdepth, depth_at.get(adj, -1), depth_at.get(ci, -1)))
for p in problems:
    print("PROBLEM=%s" % p)
PYEOF
) || LOOPDEPTH="PROBLEM=the loop-depth scanner could not run"
    ld_problems=$(printf '%s\n' "$LOOPDEPTH" | grep -c '^PROBLEM=' || true)
    if [[ "$ld_problems" -eq 0 ]]; then
      pass "adjudicate_infra_config is at loop depth 0 and count_invariant is inside the loop ($(printf '%s\n' "$LOOPDEPTH" | sed -n 's/^MAXDEPTH=/maxdepth=/p')) — terminal-ness is structural, so G2-1 and G2-5 cannot cancel"
    else
      fail "loop-structure check failed ($ld_problems problem(s)):"
      printf '%s\n' "$LOOPDEPTH" | sed -n 's/^PROBLEM=/      - /p' >&2
    fi
  fi
fi

# ===================================================================================
# #7104 PR-B — GUARD 2: the production call-site pin, EXTENDED to the re-push (task 8.1)
# ===================================================================================
# PROPERTY. Production invokes the TERMINAL content assert — not an any-of-N variant polled
# inside a retry loop (clauses 1-4 above) — invokes the TESTED predicate rather than an
# inline reimplementation of its decision, and re-pushes AT MOST ONCE per run.
#
# Boundedness is asserted HERE and nowhere else, because it is a property of the CALLER and
# this is the only guard that quantifies over the caller (plan R18.3). A pure predicate has
# no notion of how often its caller acts on it, which is why Guard 1's matrix cannot carry it.
#
# WHAT DEVIATES FROM THE PLAN'S LITERAL MATRIX, AND WHY. `## Guard Contract` §Guard 2 was
# written under R18.3 — an inline latched block inside a widened poll loop — so its rows 3, 4
# and 5 quantify over a latch, a per-iteration re-push and a duplicated verify block. Plan R22
# ruled BOTH forks TAKEN and R22.6 PRUNES R18.3 outright, replacing "the block appears once
# plus a latch" with: exactly one step in the job invokes `terraform apply` against
# `tfplan-repush`. There is no latch to delete and no loop to widen, so those rows have no
# referent as written; row 6 (the function wrapper) is the one R22.6 says to KEEP, and it
# survives as clause (6) below. The re-derived rows and their detectors are executable in
# `infra-config-repush-mutation.test.sh`.
#
# ASSEMBLY — TWO members, because the one-member claim was measurably false (R20.7 §1):
#   (i)  every statement in this job's inline `run:` bodies plus the extracted verify body,
#        quantified by the greps below;
#   (ii) the SOURCED library `infra-config-gate.sh` — production-reachable via
#        `source ./infra-config-gate.sh`, invisible to any grep over the workflow, a pure
#        adjudicator by CONVENTION only (no `set` directives, no gate enforcing
#        write-freedom), and the very file this PR adds a function to. Clause (7) converts
#        that convention into a contract.
# The `cf-tunnel-ssh-bridge` composite action is the third production-reachable path and is
# deliberately OUT of scope: pre-existing, unmodified by this PR, and pinning it would assert
# something this PR has not measured.

# (5)/(6) the predicate is invoked, exactly once, DIRECTLY as the re-push condition.
#
# (5) is the "assertion adjacent to the property" row: if the workflow inlines an equivalent
# condition instead of calling the predicate, Guard 1's whole matrix certifies a function
# production does not run. Anchored on the `if` condition shape rather than a bare token —
# infra-config-verify.sh names the predicate in two comments and in its own `declare -F`
# anti-vacuity check, so a bare grep would pass against a body that had inlined the decision
# (cq-assert-anchor-not-bare-token).
#
# (6) is the function-wrapper row R22.6 keeps from R18.2, and it is not stylistic: bash
# suspends `errexit` for a CONDITION context and the suspension PROPAGATES INTO THE FUNCTION
# BODY (R16.1). `if ! repush_once; then` is therefore how a production `terraform apply` ends
# up running with `-e` off. Requiring the total command-position count to equal the
# direct-condition count is what rules a wrapper out — and it also catches the second
# producer, a re-push decision evaluated in two places.
REPUSH_IF_SITES=$(grep -cE '^[[:space:]]*if[[:space:]]+infra_config_should_repush[[:space:]]' "$VERIFY_SH" || true)
# Command position = line start, or immediately after a separator / opener / if-family
# keyword / negation. `declare -F infra_config_should_repush` is a builtin's ARGUMENT and is
# correctly excluded; comment lines are dropped before matching.
REPUSH_CMD_SITES=$(grep -vE '^[[:space:]]*#' "$VERIFY_SH" \
  | grep -cE '(^[[:space:]]*|[;&|][[:space:]]*|[({][[:space:]]*|\b(if|elif|then|else|do|while|until)[[:space:]]+|![[:space:]]*)infra_config_should_repush[[:space:]]' || true)
# SPLIT INTO ITS TWO INDEPENDENT CLAIMS (#7104 PR-B review).
#
# These were one assertion over a conjunction, and the two mutations that target them —
# inlining the decision (row G2-2) and wrapping it in a function (row G2-4) — therefore tripped
# the SAME check and shared a marker. A shared marker means neither row proves its own clause
# works: either could have been detected by the other's, and deleting one clause would leave
# both rows still reporting RED off the surviving one.
#
# (5) is the "assertion adjacent to the property" claim: exactly one DIRECT `if` condition.
if [[ "$REPUSH_IF_SITES" -eq 1 ]]; then
  pass "#7104 Guard 2 (5): infra-config-verify.sh calls infra_config_should_repush directly as an if condition exactly once — the decision is not inlined"
else
  fail "#7104 Guard 2 (5): infra-config-verify.sh has $REPUSH_IF_SITES direct 'if infra_config_should_repush' condition(s), expected exactly 1. Zero means the decision was reimplemented inline, and Guard 1's entire matrix then certifies a predicate production does not run; more than one means the re-push decision has two producers."
fi
# (6) is the wrapper claim, and it is a DIFFERENT property: bash suspends `errexit` for a
# CONDITION context and the suspension PROPAGATES INTO THE FUNCTION BODY (R16.1), so
# `if ! repush_once; then` is how a production `terraform apply` ends up running with -e off.
# Requiring the total command-position count to equal the direct-condition count is what rules
# a wrapper out.
if [[ "$REPUSH_CMD_SITES" -eq "$REPUSH_IF_SITES" ]]; then
  pass "#7104 Guard 2 (6): every command-position call to infra_config_should_repush IS the direct if condition ($REPUSH_CMD_SITES = $REPUSH_IF_SITES) — no function wrapper, so errexit is not suspended around a production write"
else
  fail "#7104 Guard 2 (6): infra-config-verify.sh has $REPUSH_CMD_SITES command-position call(s) to infra_config_should_repush but $REPUSH_IF_SITES direct if condition(s). The excess is a wrapper or a second evaluation site; bash suspends errexit into a wrapper body (R16.1), which is how a production terraform apply downstream runs with -e off."
fi

# (5b) THE VERDICT MUST NOT BE DISCARDED ON THE CONDITION LINE (#7104 PR-B review).
#
# The count above pins that the predicate is CALLED exactly once, directly, as an `if`
# condition. It says nothing about what happens to the value it returns. Appending `|| true`
# (or `|| :`) to that line keeps every count at 1 — one direct condition, one command-position
# call, no wrapper — while making the condition unconditionally TRUE, so the re-push fires on
# every run regardless of what the predicate decided. Measured: the whole Guard 1 matrix stayed
# green, because Guard 1 grades the predicate and this mutation does not touch the predicate.
#
# It is the cheapest possible way to neutralise a safety decision while leaving every structural
# assertion satisfied, so it gets its own row rather than being folded into the counts.
REPUSH_SWALLOWED=$(grep -nE '^[[:space:]]*if[[:space:]]+infra_config_should_repush[[:space:]].*\|\|[[:space:]]*(true|:)([[:space:]]|;|$)' "$VERIFY_SH" || true)
if [[ -z "$REPUSH_SWALLOWED" ]]; then
  pass "#7104 Guard 2 (5b): the predicate's verdict is not swallowed by '|| true' / '|| :' on its own condition line"
else
  fail "#7104 Guard 2 (5b): the re-push condition discards the predicate's verdict — '${REPUSH_SWALLOWED}'. Every count-based clause above still reads 1, but the condition is now unconditionally true and the bounded re-push fires on runs the predicate refused."
fi

# (7) BOUNDEDNESS. Exactly ONE step in the job writes production from the re-push plan.
#
# This is R22.6's replacement for R18.3's latch: under the step split the honest statement of
# "at most one re-push per run" is a COUNT over apply sites, and each extra site is an
# unbounded production write against a host this repo treats as unreplaceable.
#
# TWO INDEPENDENT PRODUCERS must agree, because neither is sufficient alone: a line grep
# cannot see two applies inside ONE step, and a step-level count cannot see an apply in a
# step whose body it mis-parses.
REPUSH_APPLY_LINES=$(grep -cE '(^|[[:space:]])terraform[[:space:]]+apply[[:space:]].*tfplan-repush' "$APPLY_WF" || true)
REPUSH_APPLY_STEPS=$(python3 - "$APPLY_WF" <<'PYEOF'
import sys, re, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
pat = re.compile(r'(?:^|\s)terraform\s+apply\s[^\n]*tfplan-repush')
n = 0
for job in (wf.get('jobs') or {}).values():
    for s in (job.get('steps') or []):
        body = s.get('run')
        if isinstance(body, str) and pat.search(body):
            n += 1
print(n)
PYEOF
) || REPUSH_APPLY_STEPS="ERR"
if [[ "$REPUSH_APPLY_LINES" -eq 1 && "$REPUSH_APPLY_STEPS" == "1" ]]; then
  pass "#7104 Guard 2 (7): exactly one site writes production from tfplan-repush (1 line, 1 step) — the re-push is bounded to one attempt per run"
else
  fail "#7104 Guard 2 (7): re-push apply sites measured as $REPUSH_APPLY_LINES line(s) across $REPUSH_APPLY_STEPS step(s); both must be 1. More than one is an unbounded production write; zero means the recovery cannot fire at all and every Guard 1 row is decoration."
fi

# (8) THE SOURCED LIBRARY IS PART OF THE ASSEMBLY (R20.7 §1).
#
# COMMAND POSITION, not bare token: infra-config-gate.sh carries 20+ occurrences of these
# verbs inside the prose that explains the very traps they name, so a bare-token assert would
# fail on correct code (cq-assert-anchor-not-bare-token). Measured on the as-written file: 0.
#
# The detector carries its own POSITIVE CONTROL. A sweep that matches nothing is
# indistinguishable from a sweep whose regex silently stopped matching — and this sweep
# exists precisely to report an empty set, so it must prove it can report a non-empty one.
#
# INVERTED TO AN ALLOW-LIST (#7104 PR-B review). THIS IS THE IMPORTANT PART OF THIS GUARD.
#
# The previous sweep was a DENY-LIST of write verbs (terraform|curl|ssh|systemctl|gh issue|
# doppler secrets set). A deny-list over a shell file enumerates the ways you thought of, and
# a shell has unboundedly many ways to say the same thing. Measured against it, 11 of 12
# write-shaped inputs evaded detection:
#
#   `terraform apply`            caught (the one the single control tested)
#   doppler run -- terraform apply   EVADED  <-- and this is the shape THIS WORKFLOW USES TWICE
#   `terraform apply` in backticks   EVADED
#   xargs terraform apply            EVADED
#   env TF_LOG=1 terraform apply     EVADED
#   bash -c 'terraform apply'        EVADED
#   sh -c ...                        EVADED
#   eval "$cmd"                      EVADED
#   ssh -o ... host terraform apply  EVADED (leading flags broke the anchor)
#   command terraform apply          EVADED
#   nohup terraform apply            EVADED
#   timeout 60 terraform apply       EVADED
#
# The property this guard actually wants is "this library is a PURE ADJUDICATOR", and that is
# naturally expressed as: the only things it may run are text tools and its own functions.
# Anything else is a hit, including a wrapper whose name nobody predicted. Measured on the
# as-written library, the complete command-position set is six external binaries plus
# `infra_config_*` self-calls.
#
# The control is now a BATTERY, not a single case: a sweep that exists to report an empty set
# must prove it can report a non-empty one for every evasion shape above, or its silence is a
# statement about the regex rather than about the file.
LIB_SWEEP=$(python3 - "$SCRIPT_DIR/infra-config-gate.sh" "$SCRIPT_DIR/infra-config-shellscan.py" <<'PYEOF'
import importlib.util, sys

_spec = importlib.util.spec_from_file_location('shellscan', sys.argv[2])
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)
strip_noise = _m.strip_noise
raw_command_tokens = _m.raw_command_tokens
find_trampolines = _m.find_trampolines

# The six external binaries the library legitimately runs, derived from the as-written file.
# All six are pure text/JSON transforms — with two enormous exceptions that D3 measured and
# this comment used to omit: `awk` has system() and pipe-to-shell, and GNU `sed` has `-i` and
# the `e` flag. Both are arbitrary-command trampolines sitting INSIDE the allow list, and the
# old sweep was structurally blind to them because it blanked quoted spans first, which is
# exactly where an awk program body lives. find_trampolines() below looks for them in
# comment-stripped, quote-PRESERVING text.
ALLOWED_EXTERNAL = {'jq', 'sed', 'grep', 'awk', 'basename', 'sha256sum'}

KEYWORDS = {'if','elif','then','else','fi','for','while','until','do','done','case','esac',
            'in','function','time','coproc','return','break','continue'}
# Shell builtins run in-process and cannot reach infrastructure. `eval`, `source`, `.` and
# `command` are DELIBERATELY ABSENT: each is an arbitrary-command trampoline, which is exactly
# what an allow-list exists to stop.
# `trap` REMOVED (#7546 review). The comment above says builtins "run in-process and cannot
# reach infrastructure" -- true of `echo` and `printf`, false of `trap`, whose payload is
# arbitrary code that runs later. Measured: `trap 'terraform apply' EXIT` was MISSED in both
# quoting forms, because the payload lives in a quoted span that strip_noise blanks. Neither
# scanned file uses `trap` today, so this costs nothing and closes a trampoline that sat on
# the allow-list under a false premise -- the same shape as `eval`/`source`/`.`/`command`,
# which this set already omits deliberately.
BUILTINS = {'echo','printf','local','declare','typeset','readonly','export','unset','set',
            'shift','exit','true','false','test','read','shopt','let','pwd',
            'type','hash','umask',':','['}

def sweep(text):
    """Every escape class D3 measured, in one pass.

    The token half now sees three shapes that previously captured NOTHING AT ALL — which for an
    allow-list is the worst failure available, because no token means no hit means silence that
    reads as approval:

      /usr/bin/terraform apply      the old regex required a leading [A-Za-z_]
      ./push-infra-config.sh        same
      TF=terraform ; $TF apply      a variable in command position

    Path forms are compared on their basename; the indirect form cannot be resolved statically
    and is therefore REPORTED, not skipped. The trampoline half covers awk/sed execution and
    shell redirection, neither of which any command-position allow list can see.
    """
    hits = []
    clean = strip_noise(text)
    for line, tok, raw in raw_command_tokens(clean):
        if tok in KEYWORDS or tok in BUILTINS or tok in ALLOWED_EXTERNAL:
            continue
        if tok.startswith('infra_config_'):
            continue          # the library's own functions
        if tok == '$INDIRECT':
            hits.append((line, '%s (indirect: a variable in command position names a command '
                               'this sweep cannot resolve, so it is reported rather than '
                               'assumed benign)' % raw))
            continue
        hits.append((line, raw))
    for line, kind, detail in find_trampolines(text):
        # A PURE ADJUDICATOR WRITES NOTHING, so every redirect class is a hit here. The verify
        # gate's own sweep permits `redirect-variable` (it legitimately writes $GITHUB_OUTPUT);
        # sharing one verdict between the two would have to permit the union, and the union
        # permits the escape.
        hits.append((line, '%s: %s' % (kind, detail)))
    hits.sort()
    return hits

# POSITIVE-CONTROL BATTERY.
#
# THE FIRST TWELVE ARE ALL ONE SHAPE (#7104 PR-B review, F5 / anti-pattern 1): a bare binary in
# command position, varying only the WRAPPER in front of it. Twelve rows crossing one axis is
# one row, and it is precisely why the sweep scored 12/12 while D3 measured EIGHT evasions —
# every one of them a different shape, and none of them sampled here. The controls agreed with
# the detector because they were drawn from the same assumption.
#
# The rows below the divider each instantiate a DIFFERENT shape, and each was measured EVADING
# the pre-fix sweep. They are the controls that would have caught D3.
CONTROLS = [
    # (shape, snippet). shape A — a binary in command position, twelve wrappers
    ('A', 'f() {\n  terraform apply -auto-approve\n}\n'),
    ('A', 'f() {\n  doppler run --name-transformer tf-var -- terraform apply\n}\n'),
    ('A', 'f() {\n  x=`terraform apply`\n}\n'),
    ('A', 'f() {\n  echo a | xargs terraform apply\n}\n'),
    ('A', 'f() {\n  env TF_LOG=1 terraform apply\n}\n'),
    ('A', 'f() {\n  bash -c "terraform apply"\n}\n'),
    ('A', 'f() {\n  sh -c "terraform apply"\n}\n'),
    ('A', 'f() {\n  eval "$cmd"\n}\n'),
    ('A', 'f() {\n  ssh -o StrictHostKeyChecking=no host terraform apply\n}\n'),
    ('A', 'f() {\n  command terraform apply\n}\n'),
    ('A', 'f() {\n  nohup terraform apply\n}\n'),
    ('A', 'f() {\n  timeout 60 terraform apply\n}\n'),
    # ---- shapes the twelve above cannot reach (D3, each EVADED before this change) ----
    # shape B — a PATH, so the old token regex captured nothing at all
    ('B', 'f() {\n  /usr/bin/terraform apply -auto-approve\n}\n'),
    ('B', 'f() {\n  ./push-infra-config.sh\n}\n'),
    # shape C — the command name in a variable
    ('C', 'f() {\n  TF=terraform ; $TF apply -auto-approve\n}\n'),
    # shape D — a trampoline INSIDE the allow list, hidden in a quoted span
    ('D', 'f() {\n  awk \'BEGIN{system("terraform apply -auto-approve")}\'\n}\n'),
    ('D', 'f() {\n  awk \'BEGIN{print "terraform apply" | "sh"}\'\n}\n'),
    ('D', 'f() {\n  sed -e "s/x/terraform apply/e" file\n}\n'),
    ('D', 'f() {\n  sed -i "s/old/new/" ../../../.github/workflows/apply-deploy-pipeline-fix.yml\n}\n'),
    # shape D (cont.) — the four awk/sed trampolines the ORIGINAL detector missed (#7546 review).
    # Each was measured evading it: the program body coming from an unread FILE, the reverse pipe
    # direction (execution, not output), and awk's OWN redirect, which no shell-redirect detector
    # can see because the awk body lives inside a quoted span.
    ('D', 'f() {\n  awk -f /tmp/evil.awk\n}\n'),
    ('D', 'f() {\n  awk \'BEGIN{print "x" > "/etc/default/soleur-doppler-token"}\'\n}\n'),
    ('D', 'f() {\n  awk \'BEGIN{"terraform apply -auto-approve" | getline r}\'\n}\n'),
    ('D', 'f() {\n  sed \'w /etc/default/soleur-doppler-token\' file\n}\n'),
    # shape E — a write that invokes no command at all
    ('E', 'f() {\n  echo pwned > /etc/default/soleur-doppler-token\n}\n'),
]
missed = [i for i, (_s, c) in enumerate(CONTROLS, 1) if not sweep(c)]
if missed:
    print('CONTROL-FAILED (the detector missed control(s) %s, so its verdict on the real file '
          'would be a statement about the regex rather than about the file)'
          % ','.join(str(m) for m in missed))
    sys.exit(0)
# The controls must also cross more than one shape, or the battery degenerates back to the
# twelve-rows-one-axis state that made D3 invisible.
#
# SHAPES, NOT ROWS (#7546 review). This said "Counted structurally rather than trusted" and then
# counted ROWS -- which is precisely "trusted". Twelve rows of shape A satisfy `len(CONTROLS)
# >= 20` just as well as five shapes do, and twelve of the twenty rows here ARE that one axis:
# the block's own comment calls them "twelve rows crossing one axis is one row". So the floor
# was propped up by the very rows it was written to make unnecessary, and deleting the eight
# shape-crossing rows while adding eight more wrappers would have kept it green while restoring
# exactly the state D3 exploited. Each control now carries its shape and BOTH are floored.
_shapes = sorted({sh for sh, _c in CONTROLS})
if len(CONTROLS) < 20 or len(_shapes) < 5:
    print('CONTROL-FAILED (%d controls across %d shape(s) %s; need >= 20 rows AND >= 5 shapes -- '
          'a row count cannot tell twelve wrappers of one shape from five distinct evasions)'
          % (len(CONTROLS), len(_shapes), ''.join(_shapes)))
    sys.exit(0)

hits = sweep(open(sys.argv[1], encoding='utf-8').read())
print('OK' if not hits else 'HITS=' + '; '.join('L%d %s' % h for h in hits))
PYEOF
) || LIB_SWEEP="SWEEP-ERROR (python3/regex unavailable)"
if [[ "$LIB_SWEEP" == "OK" ]]; then
  pass "#7104 Guard 2 (8): the sourced library runs ONLY six allow-listed text tools (jq/sed/grep/awk/basename/sha256sum) and its own infra_config_* functions — pure-adjudicator is enforced by allow-list, so an unpredicted wrapper (doppler run --, xargs, env, backticks, bash -c) is a hit rather than an escape"
else
  fail "#7104 Guard 2 (8): infra-config-gate.sh is production-reachable via 'source' and invisible to every grep over the workflow. Sweep: $LIB_SWEEP"
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
for bad_reason in noop_not_active restart_did_not_advance sudo_denied \
                  restart_invocation_failed probe_unavailable timestamp_absent timestamp_unparseable; do
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

# (c2) THE DENY-LIST ITSELF. The arms above enumerate reasons the gate knows; these pin what it
# does with ones it does NOT. This was an allow-list of three reason strings that never keyed on
# `action`, so every verdict outside those three passed silently — measured against the shipped
# function, `action=failed` with an unrecognised reason returned rc=0 with no output at all.
# An allow-list classifies every fault named in future as inert, so the fixtures below are the
# ones that would go red if anyone reverted to one.
for unknown_reason in brand_new_reason_added_next_year ''; do
  VUNK="$TMP/v2-unknown-reason-${unknown_reason:-empty}.json"
  unk_restarts=$(jq --arg r "$unknown_reason" \
    '(.[0].action) = "skipped" | (.[0].reason) = $r' <<<"$RESTARTS_OK")
  build_status_json_v2 "$VUNK" 2 "$unk_restarts"
  if adjudicate_infra_config "$VUNK" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
    fail "an UNRECOGNISED skip reason ('${unknown_reason:-<empty>}') must FAIL the gate — it passed"
  else
    pass "unrecognised skip reason ('${unknown_reason:-<empty>}') REDS the gate (fails closed)"
  fi
done

# action=failed is a failure whatever the reason says — including a reason from the inert list.
VFAILINERT="$TMP/v2-failed-but-inert-reason.json"
build_status_json_v2 "$VFAILINERT" 2 \
  "$(jq '(.[0].action) = "failed" | (.[0].reason) = "not_stale"' <<<"$RESTARTS_OK")"
if adjudicate_infra_config "$VFAILINERT" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  fail "action=failed must FAIL the gate even with an inert-looking reason — it passed"
else
  pass "action=failed REDS the gate regardless of the reason string"
fi

# An action outside the vocabulary is not evidence of anything either.
VUNKACT="$TMP/v2-unknown-action.json"
build_status_json_v2 "$VUNKACT" 2 \
  "$(jq '(.[0].action) = "reconciled" | (.[0].reason) = "not_stale"' <<<"$RESTARTS_OK")"
if adjudicate_infra_config "$VUNKACT" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  fail "an UNRECOGNISED action must FAIL the gate — it passed"
else
  pass "unrecognised action REDS the gate (fails closed)"
fi

# (c3) THE OTHER DIRECTION. A deny-list that reds everything is as useless as an allow-list that
# reds nothing, and no fixture above would notice. Every known-inert verdict must still PASS.
for ok_reason in not_stale unit_inactive unit_absent; do
  VOK="$TMP/v2-inert-$ok_reason.json"
  build_status_json_v2 "$VOK" 2 \
    "$(jq --arg r "$ok_reason" '(.[0].action) = "skipped" | (.[0].reason) = $r | (.[0].active) = "inactive"' <<<"$RESTARTS_OK")"
  if adjudicate_infra_config "$VOK" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
    pass "known-inert skip reason=$ok_reason PASSES the gate (warn, not fail)"
  else
    fail "known-inert skip reason=$ok_reason must NOT fail the gate — it red"
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

# ===================================================================================
# #7220 — the fatal annotation. Asserted by RENDERED TEXT, never by `grep -c fatal_line`
# (which a comment satisfies — cq-assert-anchor-not-bare-token).
#
# The fixture is the REAL incident frame, byte-for-byte from the failing run
# (30811367645): the handler died at :415 on an ungranted `systemctl daemon-reload`, and the
# frame's hardcoded zeros made the gate report `files_total=0` about an apply that had written
# 19 of 19. Every assertion below is a line the operator would have needed that day.
# ===================================================================================
FATAL="$TMP/7220-fatal.json"
printf '{"schema_version":2,"start_ts":1785758310,"end_ts":1785758311,"exit_code":1,"reason":"unhandled","files_written":0,"files_failed":0,"files_total":0,"fatal_rc":1,"fatal_line":415,"fatal_cmd":"systemctl daemon-reload","files":[],"restarts":[]}\n' > "$FATAL"

FATAL_OUT="$TMP/7220-fatal.out"
adjudicate_infra_config "$FATAL" "$SYNTH" "$SYNTH/infra-config-apply.sh" > "$FATAL_OUT" 2>&1
FATAL_RC=$?

# (1) FAIL-OPEN GUARD — the highest-stakes assertion here. This block SILENCES gate branches,
# which is exactly the shape that turns a safety gate into a bypass. fatal_line must never be a
# path to a zero return.
if [[ "$FATAL_RC" -ne 0 ]]; then
  pass "#7220 fail-open guard: a frame carrying fatal_line still FAILS the gate (rc=$FATAL_RC)"
else
  fail "#7220 FAIL-OPEN: a fatal frame returned 0 — the suppression changed the VERDICT, not just the message"
fi

# (2) The five elements AC15 requires, each by its rendered text.
if grep -qF 'line 415' "$FATAL_OUT"; then
  pass "#7220 annotation names the exact line the handler died at"
else
  fail "#7220 annotation does not render this frame's fatal_line (415)"
fi
# The line is a coordinate into the DEPLOYED handler, which can lag this checkout by one apply.
# Rendering it bare invites the operator to open the repo at a line that means something else —
# #7220's own fix moved the reload 415 -> 520 within one PR. The qualifier is the fix.
if grep -qF 'AS DEPLOYED' "$FATAL_OUT"; then
  pass "#7220 annotation qualifies the line as a deployed-handler coordinate, not a repo one"
else
  fail "#7220 annotation renders fatal_line as if it were a repo coordinate"
fi
if grep -qF 'systemctl daemon-reload' "$FATAL_OUT"; then
  pass "#7220 annotation names the failing command"
else
  fail "#7220 annotation does not name the failing command"
fi
if grep -qF 'every step after this line did not run' "$FATAL_OUT"; then
  pass "#7220 annotation turns a line number into a mental model"
else
  fail "#7220 annotation omits 'every step after this line did not run'"
fi
if grep -qF 'files_written=0 of ' "$FATAL_OUT"; then
  pass "#7220 annotation states what is STILL TRUE, so a red gate is not misread as total loss"
else
  fail "#7220 annotation omits the files_written=N of M statement"
fi
if grep -qF -- '--since 1h' "$FATAL_OUT"; then
  pass "#7220 annotation carries a copy-pasteable next command with a relative window"
else
  fail "#7220 annotation omits the --since 1h query"
fi
# The single highest-value line in this change. The previous incident's annotation was
# two-thirds false and the issue written from it pointed the operator at destroying a host with
# 0/6 datacentre stock. The next incident reads THIS, not the plan.
if grep -qF 'Do NOT run' "$FATAL_OUT" && grep -qF 'cx33' "$FATAL_OUT" && grep -qF '000/502/503' "$FATAL_OUT"; then
  pass "#7220 annotation carries the -replace guardrail with its scope and the stock reality"
else
  fail "#7220 annotation is missing the -replace guardrail — the failure mode that produced this issue"
fi
# A prohibition on a bare command PREFIX is uncheckable and self-contradicting: this same
# workflow prescribes -replace=terraform_data.infra_config_handler_bootstrap for the 000/502/503
# shape. The guardrail must name the target that destroys the host, and clear the one that does not.
if grep -qF 'hcloud_server.web' "$FATAL_OUT"; then
  pass "#7220 guardrail names the FORBIDDEN target, not just the command"
else
  fail "#7220 guardrail forbids a command prefix without naming a target — unactionable and self-contradicting"
fi
if grep -qF 'terraform_data.infra_config_handler_bootstrap' "$FATAL_OUT"; then
  pass "#7220 guardrail clears the SAFE replace target so the operator is not stranded"
else
  fail "#7220 guardrail does not distinguish the safe replace target from the forbidden one"
fi

# (3) Suppression: MESSAGE only, and only the two branches fatal_line already explains.
if grep -qF 'UNDER-DELIVERED: host reported files_total=' "$FATAL_OUT"; then
  fail "#7220: the UNDER-DELIVERED line still fires in fatal mode — it said files_total=0 about a 19/19 apply"
else
  pass "#7220 suppresses the UNDER-DELIVERED count line when fatal_line explains the shortfall"
fi
if grep -qF 'no verdict for' "$FATAL_OUT"; then
  fail "#7220: the per-unit 'no verdict for' line still fires in fatal mode"
else
  pass "#7220 suppresses the per-unit activation line when fatal_line explains the absence"
fi
# KEPT, deliberately — it is accurate, and it is what the gate adjudicates on first.
if grep -qF 'reported exit_code=1' "$FATAL_OUT"; then
  pass "#7220 KEEPS the exit_code line (verified against the real frame: it is accurate)"
else
  fail "#7220 suppressed the exit_code line, which is accurate and must survive"
fi

# (4) ANTI-VACUITY / mutation guard. The two suppressions above are conditional, not deletions.
# Without this, replacing the branches with nothing at all would pass every assertion in (3).
NOFATAL="$TMP/7220-nofatal.json"
printf '{"schema_version":2,"start_ts":1785758310,"end_ts":1785758311,"exit_code":1,"reason":"unhandled","files_written":0,"files_failed":0,"files_total":0,"fatal_rc":0,"fatal_line":0,"fatal_cmd":"","files":[],"restarts":[]}\n' > "$NOFATAL"
NOFATAL_OUT="$TMP/7220-nofatal.out"
adjudicate_infra_config "$NOFATAL" "$SYNTH" "$SYNTH/infra-config-apply.sh" > "$NOFATAL_OUT" 2>&1 || true
if grep -qF 'UNDER-DELIVERED: host reported files_total=' "$NOFATAL_OUT"; then
  pass "#7220 non-vacuity: without fatal_line the UNDER-DELIVERED line still fires (suppression is conditional)"
else
  fail "#7220 VACUOUS: the UNDER-DELIVERED branch never fires at all — it was deleted, not suppressed"
fi
if grep -qF 'no verdict for' "$NOFATAL_OUT"; then
  pass "#7220 non-vacuity: without fatal_line the per-unit activation line still fires"
else
  fail "#7220 VACUOUS: the per-unit activation branch never fires at all"
fi
# And a clean frame must not acquire a fatal annotation.
if grep -qF 'DIED at infra-config-apply.sh' "$NOFATAL_OUT"; then
  fail "#7220: a frame with fatal_line=0 rendered a fatal annotation — false attribution"
else
  pass "#7220 no false attribution on a frame that carries no fatal_line"
fi

# --- #7220 review: a SECOND fatal fixture, with different values in every field -------------
# Mutation-proven necessary. With only the frozen incident fixture, every assertion greps that
# fixture's own literals, so replacing the whole annotation with a hardcoded string passed 53/0.
# One fixture cannot distinguish "renders the frame" from "prints a constant". This one also
# carries files_written == files_total, the state the "what is still true" line exists for and
# which the incident fixture (0 of 19) never exercised.
FATAL2="$TMP/7220-fatal2.json"
printf '{"schema_version":2,"start_ts":1785758400,"end_ts":1785758409,"exit_code":203,"reason":"fatal_after_publish","files_written":%d,"files_failed":0,"files_total":%d,"fatal_rc":203,"fatal_line":772,"fatal_cmd":"sudo /usr/bin/systemd-run --on-active=3s","files":[],"restarts":[]}\n' "$EXPECTED_COUNT" "$EXPECTED_COUNT" > "$FATAL2"
FATAL2_OUT="$TMP/7220-fatal2.out"
adjudicate_infra_config "$FATAL2" "$SYNTH" "$SYNTH/infra-config-apply.sh" > "$FATAL2_OUT" 2>&1
FATAL2_RC=$?

if [[ "$FATAL2_RC" -ne 0 ]]; then
  pass "#7220 fixture-2: a post-publish fatal frame still FAILS the gate"
else
  fail "#7220 fixture-2 FAIL-OPEN: a post-publish fatal frame returned 0"
fi
if grep -qF 'line 772' "$FATAL2_OUT" && grep -qF 'rc=203' "$FATAL2_OUT"; then
  pass "#7220 fixture-2: annotation renders THIS frame's line and rc (not a constant)"
else
  fail "#7220 fixture-2: annotation did not render line=772/rc=203 — values may be hardcoded"
fi
if grep -qF 'systemd-run' "$FATAL2_OUT"; then
  pass "#7220 fixture-2: annotation renders THIS frame's failing command"
else
  fail "#7220 fixture-2: annotation did not render this frame's fatal_cmd"
fi
# The number that tells the operator delivery SUCCEEDED. Never exercised non-zero before.
if grep -qF "files_written=${EXPECTED_COUNT} of ${EXPECTED_COUNT}" "$FATAL2_OUT"; then
  pass "#7220 fixture-2: 'what is still true' reports a FULL delivery, not a hardcoded 0"
else
  fail "#7220 fixture-2: files_written line did not render ${EXPECTED_COUNT} of ${EXPECTED_COUNT}"
fi
# Suppression must stay scoped to the two branches it was authorised for.
if grep -qF 'landed-files mismatch' "$FATAL2_OUT"; then
  fail "#7220 fixture-2: landed-files mismatch fired on an equal-count frame (unexpected)"
else
  pass "#7220 fixture-2: no spurious landed-files mismatch on an equal-count frame"
fi

# --- non-vacuity floor: the synthetic FILE_MAP produced a real, non-empty set --------
if [[ "$EXPECTED_COUNT" -ge 2 && "${#COMPARABLE_DESTS[@]}" -ge 1 ]]; then
  pass "fixture non-vacuity: EXPECTED_COUNT=$EXPECTED_COUNT, ${#COMPARABLE_DESTS[@]} comparable dests"
else
  fail "fixture is vacuous: EXPECTED_COUNT=$EXPECTED_COUNT comparable=${#COMPARABLE_DESTS[@]}"
fi

# --- #7220 review: the FATAL-ONLY-RED fixture (isolates the fatal branch's own verdict) -----
# Mutation-proven necessary. Deleting `rc=1` from the gate's fatal branch left the suite green,
# because every fatal fixture ALSO trips exit_code!=0 — so the branch's verdict was carried by a
# neighbour and pinned by nothing. This frame passes every other check (clean exit_code, correct
# counts, full restarts, matching shas); only the fatal branch can red it.
#
# Defence in depth: with the producer's `died` fix a post-publish death now carries a non-zero
# exit_code, so this exact frame should no longer arise — which is precisely why the gate must
# still refuse it. A frame asserting "clean apply" AND "died at line N" is self-contradictory,
# and a gate that passes a self-contradictory frame is a gate that trusts the wrong field.
FATALONLY="$TMP/7220-fatal-only.json"
jq -c '. + {fatal_rc:1, fatal_line:661, fatal_cmd:"sudo /usr/bin/systemctl daemon-reload"}' "$VNOOP" > "$FATALONLY"
FATALONLY_OUT="$TMP/7220-fatal-only.out"
adjudicate_infra_config "$FATALONLY" "$SYNTH" "$SYNTH/infra-config-apply.sh" > "$FATALONLY_OUT" 2>&1
FATALONLY_RC=$?

# Sanity: the SAME frame without the fatal fields must PASS, or this arm proves nothing.
if adjudicate_infra_config "$VNOOP" "$SYNTH" "$SYNTH/infra-config-apply.sh" >/dev/null 2>&1; then
  pass "#7220 fatal-only: the base frame passes, so the fatal fields are the only variable"
else
  fail "#7220 fatal-only: base frame does not pass — this arm is vacuous"
fi
if [[ "$FATALONLY_RC" -ne 0 ]]; then
  pass "#7220 fatal-only: fatal_line alone is enough to RED an otherwise-clean frame"
else
  fail "#7220 FAIL-OPEN: a frame carrying fatal_line=661 PASSED because every other check was clean"
fi
if grep -qF 'line 661' "$FATALONLY_OUT"; then
  pass "#7220 fatal-only: the annotation still names the line"
else
  fail "#7220 fatal-only: no attribution rendered"
fi

# --- #7104 PR-A: infra_config_dpf_replaced (the SENSOR) -------------------------------------
#
# Was terraform_data.deploy_pipeline_fix REPLACED by the plan this apply consumed? If it was
# not, no push fired, no frame was published, and the #7220 freshness pin reds a run that did
# nothing wrong. Measured on run 31636951749 (2026-08-12, main @ 0d644396): `Plan: No changes`
# / `Apply complete! Resources: 0 added, 0 changed, 0 destroyed` — and the gate red with
# STALE FRAME naming the 2026-08-06 frame. That is a live false-red, not a hypothetical.
#
# The function is a PURE ADJUDICATOR over a `terraform show -json` plan file, matching this
# file's six existing siblings: it echoes exactly "true" or "false" and returns non-zero on
# anything it cannot classify. Polarity is therefore guaranteed BY CONSTRUCTION rather than by
# a downstream `^(true|false)$` regex (R17.1 asked for the regex; a function that can only emit
# those two strings is strictly stronger, and the caller still validates).
#
# The `jq -r` null trap the workflow documents ~200 lines above the call site applies here too:
# `jq -r '.resource_changes'` on a missing key yields the STRING "null", and `null | length` is
# 0 — so a degraded plan file would read as "no changes found" == false == skip the pin,
# silently and permanently restoring #7220's blind spot. Every arm below that returns non-zero
# exists to make that impossible.

DPF_ADDR="terraform_data.deploy_pipeline_fix"
mkplan() { printf '%s\n' "$1" > "$TMP/plan-$2.json"; echo "$TMP/plan-$2.json"; }

# 1. Replaced (delete+create) — the healthy push path.
P_REPL=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["delete","create"]}}]}' repl)
DPF_OUT=$(infra_config_dpf_replaced "$P_REPL" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "true" ]]; then
  pass "#7104 dpf: delete+create classifies as replaced (true)"
else
  fail "#7104 dpf: delete+create gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 true"
fi

# 2. no-op — THE case this PR exists for. Must be a clean false, not an error.
P_NOOP=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["no-op"]}}]}' noop)
DPF_OUT=$(infra_config_dpf_replaced "$P_NOOP" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "false" ]]; then
  pass "#7104 dpf: no-op classifies as NOT replaced (false)"
else
  fail "#7104 dpf: no-op gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 false"
fi

# 3. POSITIVE CONTROL (R17.1). The address is absent from resource_changes[] entirely — an
#    address rename, a module move, a -target that no longer selects it. Without this arm that
#    reads as a permanent, silent "false" and the pin is disabled forever.
P_ABSENT=$(mkplan '{"resource_changes":[{"address":"terraform_data.something_else","change":{"actions":["no-op"]}}]}' absent)
DPF_OUT=$(infra_config_dpf_replaced "$P_ABSENT" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: address absent from resource_changes[] fails CLOSED (address drift)"
else
  fail "#7104 dpf FAIL-OPEN: absent address returned rc=0 out='$DPF_OUT' — drift reads as a permanent false"
fi

# 4. `resource_changes` key missing — the `jq -r` -> "null" -> length 0 trap, explicitly.
P_NOKEY=$(mkplan '{"format_version":"1.2"}' nokey)
DPF_OUT=$(infra_config_dpf_replaced "$P_NOKEY" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: missing resource_changes key fails CLOSED (not 'false')"
else
  fail "#7104 dpf FAIL-OPEN: missing resource_changes returned rc=0 out='$DPF_OUT'"
fi

# 5. `resource_changes: null` — same trap, different shape.
P_NULL=$(mkplan '{"resource_changes":null}' null)
DPF_OUT=$(infra_config_dpf_replaced "$P_NULL" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: resource_changes:null fails CLOSED"
else
  fail "#7104 dpf FAIL-OPEN: resource_changes:null returned rc=0 out='$DPF_OUT'"
fi

# 6. Not an array: an OBJECT map whose values are well-formed change records. The fixture shape
#    matters — a naive `{"resource_changes":{"address":...}}` errors downstream anyway (jq
#    cannot index a string), so it would pass with the type guard REMOVED and the arm would be
#    vacuous. Measured: mutation M2 (delete the type guard) survived against that shape. This
#    shape does not survive it, because `.resource_changes[]` over an object iterates its VALUES
#    and would classify this as a clean "true" with no guard in place.
P_OBJ=$(mkplan '{"resource_changes":{"r0":{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["create"]}}}}' obj)
DPF_OUT=$(infra_config_dpf_replaced "$P_OBJ" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: resource_changes of the wrong type fails CLOSED"
else
  fail "#7104 dpf FAIL-OPEN: object resource_changes returned rc=0 out='$DPF_OUT'"
fi

# 7. Malformed JSON.
P_BAD=$(mkplan '{this is not json' bad)
DPF_OUT=$(infra_config_dpf_replaced "$P_BAD" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: unparseable plan JSON fails CLOSED"
else
  fail "#7104 dpf FAIL-OPEN: malformed JSON returned rc=0 out='$DPF_OUT'"
fi

# 8. Unreadable / absent plan file.
DPF_OUT=$(infra_config_dpf_replaced "$TMP/does-not-exist.json" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: missing plan file fails CLOSED"
else
  fail "#7104 dpf FAIL-OPEN: missing plan file returned rc=0 out='$DPF_OUT'"
fi

# 9. create-only (first birth of the resource).
P_CREATE=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["create"]}}]}' create)
DPF_OUT=$(infra_config_dpf_replaced "$P_CREATE" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "true" ]]; then
  pass "#7104 dpf: create-only classifies as replaced (true)"
else
  fail "#7104 dpf: create-only gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 true"
fi

# 10. create_before_destroy orders the actions the other way. Order must not matter.
P_CBD=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["create","delete"]}}]}' cbd)
DPF_OUT=$(infra_config_dpf_replaced "$P_CBD" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "true" ]]; then
  pass "#7104 dpf: create+delete (create_before_destroy) is order-insensitive"
else
  fail "#7104 dpf: create+delete gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 true"
fi

# 11. ALLOW-LIST semantics: an action token terraform does not currently emit must fail closed
#     rather than fall through to "false". A future action verb that means "this was rebuilt"
#     would otherwise silently disable the pin.
P_UNK=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["teleport"]}}]}' unk)
DPF_OUT=$(infra_config_dpf_replaced "$P_UNK" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: an unknown action verb fails CLOSED (allow-list, not deny-list)"
else
  fail "#7104 dpf FAIL-OPEN: unknown action 'teleport' returned rc=0 out='$DPF_OUT'"
fi

# 12. Empty actions array.
P_EMPTY=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":[]}}]}' empty)
DPF_OUT=$(infra_config_dpf_replaced "$P_EMPTY" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: empty actions[] fails CLOSED"
else
  fail "#7104 dpf FAIL-OPEN: empty actions[] returned rc=0 out='$DPF_OUT'"
fi

# 13. `forget` (a `removed {}` block drops the resource from state without destroying it).
#     No push fires, so the sensor must say false — and the pin must therefore still run.
#     R13.5 records that PR-B's exact-cardinality assert is what ABORTS on this shape; the
#     sensor's job is only to report that nothing was pushed.
P_FORGET=$(mkplan '{"resource_changes":[{"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["forget"]}}]}' forget)
DPF_OUT=$(infra_config_dpf_replaced "$P_FORGET" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "false" ]]; then
  pass "#7104 dpf: forget classifies as NOT replaced (no push fired)"
else
  fail "#7104 dpf: forget gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 false"
fi

# 14. The real multi-resource shape: this workflow -targets four resources, so DPF must be
#     selected by ADDRESS and not by position. A sibling being replaced must not leak into
#     DPF's verdict.
P_MULTI=$(mkplan '{"resource_changes":[
  {"address":"terraform_data.docker_seccomp_config","change":{"actions":["delete","create"]}},
  {"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["no-op"]}},
  {"address":"terraform_data.apparmor_bwrap_profile","change":{"actions":["delete","create"]}}
]}' multi)
DPF_OUT=$(infra_config_dpf_replaced "$P_MULTI" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "false" ]]; then
  pass "#7104 dpf: DPF is selected by address, not by a sibling's replacement"
else
  fail "#7104 dpf: multi-resource plan gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 false"
fi

# 14b. `update` and `read` are in the allow-list and had NO fixture, so both narrowing the list
#      (a false-red on the workflow whose false-reds are this PR's subject) and widening the
#      create-detector to include them (wrong polarity) survived. Both directions pinned here.
for verb in update read; do
  P_VERB=$(mkplan "{\"resource_changes\":[{\"address\":\"terraform_data.deploy_pipeline_fix\",\"change\":{\"actions\":[\"$verb\"]}}]}" "verb$verb")
  DPF_OUT=$(infra_config_dpf_replaced "$P_VERB" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
  if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "false" ]]; then
    pass "#7104 dpf: '$verb' is accepted by the allow-list and is NOT a push (false)"
  else
    fail "#7104 dpf: '$verb' gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 false"
  fi
done

# 15. Two entries carrying the SAME address. A well-formed `terraform show -json` should never
#     emit this, which is exactly why it must not be adjudicated silently: without the guard the
#     function classifies on $matched[0] and a second, contradicting entry is discarded unseen.
#     Added because mutation M8 (delete the duplicate-address guard) SURVIVED the suite — the
#     arm had no fixture at all, so the guard was unfalsifiable rather than equivalent.
P_DUP=$(mkplan '{"resource_changes":[
  {"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["no-op"]}},
  {"address":"terraform_data.deploy_pipeline_fix","change":{"actions":["delete","create"]}}
]}' dup)
DPF_OUT=$(infra_config_dpf_replaced "$P_DUP" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -ne 0 ]]; then
  pass "#7104 dpf: a duplicated address fails CLOSED (never adjudicate on the first of two)"
else
  fail "#7104 dpf FAIL-OPEN: duplicated address returned rc=0 out='$DPF_OUT' — the contradicting entry was discarded"
fi

# --- #7104 PR-A: infra_config_frame_stability (the no-push arm's verdict) -------------------
#
# Runs only when DPF_REPLACED == false: no push was expected, so no NEW frame should exist and
# the #7220 freshness pin (FRAME_START_TS >= APPLY_START_EPOCH) would red a correct run.
#
# WHAT THIS ESTABLISHES, precisely — the plan review (R17.1) overclaimed it and the CTO ruling
# corrected it, so the narrow version is pinned here rather than the flattering one:
#   * IT DOES prove frame STABILITY across this run: the endpoint answered, the frame parses,
#     and it is the same frame it was before the apply — i.e. no unexpected push occurred.
#   * IT DOES NOT detect a wiped handler. A wiped handler leaves the last frame IN PLACE, so
#     PRE == POST and this passes.
#   * IT DOES NOT detect a post-push tamper of hooks.json or the Doppler token. The frame
#     records the LAST WRITE; it is not a re-read of the bytes on disk.
# Those two holes stay open and are tracked separately. A test that asserted otherwise would be
# pinning a claim nobody measured.
#
# ASYMMETRY, deliberately: the sentinel (no pre-reading) arm DEGRADES rather than failing closed.
# It is reachable only when the pre-poll failed AND the post-poll returned 200 — so the channel
# is demonstrably reachable now, and the missing evidence bears only on an anomaly detector, not
# on the dying-handler shape the gate exists to catch (that lives on the DPF_REPLACED == true
# arm, where APPLY_START_EPOCH still applies). Failing closed here would red correct runs on a
# network blip, on the very workflow whose false-reds are this PR's subject.
#
# NO LOWER BOUND ON FRAME AGE. On a no-push run the frame is legitimately ancient — the
# 2026-08-06 frame was CORRECT on 2026-08-12. Any max-age assert re-introduces the exact
# false-red this PR removes. The upper bound is different: a frame claiming to start in the
# FUTURE is a host-clock anomaly or a fabricated frame, and it reds on BOTH sub-arms.

FS_NOW=1786600000
FS_SKEW=300   # tolerance shared with the implementation

# ok + equal -> stable, pass.
FS_OUT=$(infra_config_frame_stability 1786001951 1786001951 ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -eq 0 && "$FS_OUT" == "stable" ]]; then
  pass "#7104 stability: an unchanged frame on a no-push run is stable (the live 31636951749 shape)"
else
  fail "#7104 stability: equal pre/post gave rc=$FS_RC out='$FS_OUT', expected rc=0 stable"
fi

# ok + post > pre -> a push landed on a run whose plan said none would.
FS_OUT=$(infra_config_frame_stability 1786001999 1786001951 ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && "$FS_OUT" == "unexpected_push" ]]; then
  pass "#7104 stability: a NEWER frame with no push expected fails CLOSED (plan/apply divergence)"
else
  fail "#7104 stability: post>pre gave rc=$FS_RC out='$FS_OUT', expected non-zero unexpected_push"
fi

# ok + post < pre -> the frame went backwards. State rollback or a host clock jump.
FS_OUT=$(infra_config_frame_stability 1786001900 1786001951 ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && "$FS_OUT" == "frame_regressed" ]]; then
  pass "#7104 stability: a frame that moved BACKWARDS fails CLOSED"
else
  fail "#7104 stability: post<pre gave rc=$FS_RC out='$FS_OUT', expected non-zero frame_regressed"
fi

# Future-dated frame reds on the ok arm...
FS_OUT=$(infra_config_frame_stability $((FS_NOW + FS_SKEW + 60)) 1786001951 ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && "$FS_OUT" == "future_frame" ]]; then
  pass "#7104 stability: a future-dated frame fails CLOSED on the ok arm"
else
  fail "#7104 stability: future frame (ok) gave rc=$FS_RC out='$FS_OUT', expected non-zero future_frame"
fi

# ...and on the degraded arm too, where it is the ONLY freshness evidence left.
FS_OUT=$(infra_config_frame_stability $((FS_NOW + FS_SKEW + 60)) "" unreachable "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && "$FS_OUT" == "future_frame" ]]; then
  pass "#7104 stability: a future-dated frame fails CLOSED on the DEGRADED arm as well"
else
  fail "#7104 stability: future frame (degraded) gave rc=$FS_RC out='$FS_OUT', expected non-zero future_frame"
fi

# The skew boundary is INCLUSIVE: future means strictly greater than now+skew. Isolate it by
# making pre == post, so the ok arm would return `stable` and any non-zero result can only be
# the future check firing. (A fixture with pre != post here would red as `unexpected_push` and
# the assertion would pass for the wrong reason — it would not test the boundary at all.)
FS_OUT=$(infra_config_frame_stability $((FS_NOW + FS_SKEW)) $((FS_NOW + FS_SKEW)) ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -eq 0 && "$FS_OUT" == "stable" ]]; then
  pass "#7104 stability: exactly now+skew is NOT future (inclusive boundary)"
else
  fail "#7104 stability: boundary gave rc=$FS_RC out='$FS_OUT', expected rc=0 stable"
fi

# One second past the boundary IS future — the pair above and below pins the comparison
# operator, which a single-sided fixture cannot do.
FS_OUT=$(infra_config_frame_stability $((FS_NOW + FS_SKEW + 1)) $((FS_NOW + FS_SKEW + 1)) ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && "$FS_OUT" == "future_frame" ]]; then
  pass "#7104 stability: one second past now+skew IS future (pins the operator, not just the side)"
else
  fail "#7104 stability: boundary+1 gave rc=$FS_RC out='$FS_OUT', expected non-zero future_frame"
fi

# Each degraded status echoes its OWN token. A generic token would let the workflow print a
# message naming a cause it did not measure (AP-021).
for st in http404 unreachable malformed error; do
  FS_OUT=$(infra_config_frame_stability 1786001951 "" "$st" "$FS_NOW" 2>/dev/null); FS_RC=$?
  if [[ "$FS_RC" -eq 0 && "$FS_OUT" == "degraded:$st" ]]; then
    pass "#7104 stability: pre_status=$st degrades and passes, carrying its own token"
  else
    fail "#7104 stability: pre_status=$st gave rc=$FS_RC out='$FS_OUT', expected rc=0 degraded:$st"
  fi
done

# An unrecognised status fails CLOSED — allow-list, so a typo'd or newly-added status can never
# fall through to a silent pass.
FS_OUT=$(infra_config_frame_stability 1786001951 "" weird "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 ]]; then
  pass "#7104 stability: an unknown pre_status fails CLOSED (allow-list)"
else
  fail "#7104 stability FAIL-OPEN: unknown pre_status returned rc=0 out='$FS_OUT'"
fi

# ok status with a non-numeric or absent pre timestamp is INCOHERENT — the step claimed a
# reading it did not supply. Fail closed rather than silently degrading, or a bug in the
# pre-capture step would present as a routine degrade forever.
# Assert the VERDICT, not just the return code. Without the guard bash coerces the empty
# pre_ts to 0, the comparison yields `unexpected_push`, and the function still returns
# non-zero -- so an rc-only assertion cannot tell a guard rejection from a bogus verdict.
# That distinction is the whole point: `unexpected_push` drives an operator message claiming
# a push landed, which is a cause nobody measured (AP-021). A guard rejection emits its
# reason on stderr and NOTHING on stdout.
FS_OUT=$(infra_config_frame_stability 1786001951 "" ok "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && -z "$FS_OUT" ]]; then
  pass "#7104 stability: pre_status=ok with no pre timestamp is REJECTED, not misverdicted"
else
  fail "#7104 stability: ok+empty pre_ts gave rc=$FS_RC out='$FS_OUT', expected non-zero with empty stdout"
fi

# A non-numeric POST timestamp must never be compared as a string.
# A non-numeric post timestamp must be REJECTED BY NAME, and the assertion has to be on the
# DIAGNOSTIC rather than on the return code. Measured: deleting this guard does not change the
# return code or stdout at all, because callers run under `set -u` (this harness and the
# workflow step both do) and bash's arithmetic evaluation of `not-a-number` dereferences three
# unset names, so the shell aborts. Same rc, same empty stdout -- the mutation is invisible to
# any rc-or-stdout assertion.
#
# What the guard actually buys under `set -u` is therefore the MESSAGE: without it the function
# dies mute mid-comparison, and in the workflow that kills the step before the ::error:: branches
# that would explain why. A gate that fails closed but silently is the failure shape this whole
# change exists to remove, so the guard is load-bearing and this is what pins it.
# The now_epoch guard is the sibling of the post_ts one and had no fixture at all. Deleting it
# makes an empty now_epoch evaluate arithmetically to 0, so post_ts > 0+skew and the function
# emits `future_frame` — driving an operator ::error:: about a "host-clock anomaly or fabricated
# frame" on a cause nobody measured. Assert the diagnostic, for the same reason as post_ts.
FS_NOWERR="$TMP/fs-nownonnumeric.err"
FS_OUT=$(infra_config_frame_stability 1786001951 1786001951 ok "not-a-number" 2>"$FS_NOWERR"); FS_RC=$?
if [[ "$FS_RC" -ne 0 && -z "$FS_OUT" ]] && grep -qF 'now_epoch' "$FS_NOWERR"; then
  pass "#7104 stability: a non-numeric now_epoch is rejected with a diagnostic naming now_epoch"
else
  fail "#7104 stability: non-numeric now_epoch gave rc=$FS_RC out='$FS_OUT' err='$(cat "$FS_NOWERR" 2>/dev/null)'"
fi

FS_ERR="$TMP/fs-nonnumeric.err"
FS_OUT=$(infra_config_frame_stability "not-a-number" 1786001951 ok "$FS_NOW" 2>"$FS_ERR"); FS_RC=$?
if [[ "$FS_RC" -ne 0 && -z "$FS_OUT" ]] && grep -qF 'post_ts' "$FS_ERR"; then
  pass "#7104 stability: a non-numeric post timestamp is rejected with a diagnostic naming post_ts"
else
  fail "#7104 stability: non-numeric post_ts gave rc=$FS_RC out='$FS_OUT' stderr='$(cat "$FS_ERR" 2>/dev/null)'; expected non-zero, empty stdout, and a message naming post_ts"
fi

# --- #7104 review round: arms added because the panel found them missing --------------------

# A plan with an EMPTY resource_changes is a genuine zero-change plan. It must classify as
# "no push expected", NOT abort: aborting means the plan step exits 1, the apply never runs and
# the gate is skipped — strictly worse than the false-red this change removes, on the sole
# no-SSH remediation channel. The repo's own synthesized no-changes fixture has exactly this
# shape, so this is the case a real no-op dispatch is most likely to produce.
P_EMPTYRC=$(mkplan '{"format_version":"1.2","resource_changes":[]}' emptyrc)
DPF_OUT=$(infra_config_dpf_replaced "$P_EMPTYRC" "$DPF_ADDR" 2>/dev/null); DPF_RC=$?
if [[ "$DPF_RC" -eq 0 && "$DPF_OUT" == "false" ]]; then
  pass "#7104 dpf: an empty resource_changes[] is a zero-change plan (false), never an abort"
else
  fail "#7104 dpf: empty resource_changes gave rc=$DPF_RC out='$DPF_OUT', expected rc=0 false"
fi

# The degraded arm is SELECTED BY THE HOST BEING VERIFIED (it picks the pre_status by how it
# answers), so it must still carry one assertion the host cannot choose. APPLY_START_EPOCH is a
# runner-side timestamp: a frame postdating the apply on a no-push run is an unexpected push
# regardless of what the pre-reading said.
FS_OUT=$(infra_config_frame_stability $((FS_NOW - 100)) "" unreachable "$FS_NOW" $((FS_NOW - 100 - FS_SKEW)) 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && "$FS_OUT" == "unexpected_push" ]]; then
  pass "#7104 stability: degraded arm still reds a frame that postdates the apply (host cannot opt out)"
else
  fail "#7104 stability: degraded+postdating gave rc=$FS_RC out='$FS_OUT', expected non-zero unexpected_push"
fi

# ...and the same arm must NOT red an ordinary stale frame, or it re-creates the false-red.
FS_OUT=$(infra_config_frame_stability 1786001951 "" unreachable "$FS_NOW" $((FS_NOW - 60)) 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -eq 0 && "$FS_OUT" == "degraded:unreachable" ]]; then
  pass "#7104 stability: degraded arm passes a stale frame (no lower bound on frame age)"
else
  fail "#7104 stability: degraded+stale gave rc=$FS_RC out='$FS_OUT', expected rc=0 degraded:unreachable"
fi

# secret_unavailable is its own token: the step RAN and measured a specific cause (Doppler read
# failed), which is a different incident from "no reading was recorded".
FS_OUT=$(infra_config_frame_stability 1786001951 "" secret_unavailable "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -eq 0 && "$FS_OUT" == "degraded:secret_unavailable" ]]; then
  pass "#7104 stability: a Doppler read failure carries its own token, not the generic error"
else
  fail "#7104 stability: secret_unavailable gave rc=$FS_RC out='$FS_OUT', expected rc=0 degraded:secret_unavailable"
fi

# An EMPTY pre_status means the producing STEP did not run. A missing step is not the same thing
# as missing evidence, and the asymmetry rule covers only the latter — so it fails closed, the
# same way the sibling carrier DPF_REPLACED does on unset.
FS_OUT=$(infra_config_frame_stability 1786001951 "" "" "$FS_NOW" 2>/dev/null); FS_RC=$?
if [[ "$FS_RC" -ne 0 && -z "$FS_OUT" ]]; then
  pass "#7104 stability: an EMPTY pre_status (step never ran) fails CLOSED, not degrade-and-pass"
else
  fail "#7104 stability: empty pre_status gave rc=$FS_RC out='$FS_OUT', expected non-zero, empty stdout"
fi

# --- #7104: PRODUCTION CALL-SITE PIN for the two new sensors --------------------------------
#
# The F1 pin above exists because testing an adjudicator in isolation is vacuous if production
# does not call it. That reasoning was not carried to the new code, and the gap was live:
# replacing `DPF_REPLACED=$(infra_config_dpf_replaced ...)` with `DPF_REPLACED=false` left this
# suite at 100 passed / 0 failed — while pinning EVERY run onto the no-push arm, permanently
# disabling #7220's freshness pin. That is the precise blind spot this PR exists not to restore,
# and it was deletable at full green.
# PR-B: the two sensors now sit on OPPOSITE sides of the extraction boundary, and
# conflating them is what makes this pin easy to get wrong. `infra_config_dpf_replaced`
# is read in the `Terraform plan` step, which stays inline in the workflow;
# `infra_config_frame_stability` ran in the ~240-line gate body, which moved to
# infra-config-verify.sh. So each clause is pinned against its REAL producer.
#
# The ordering property is unchanged in substance — the sensor is still read before
# the verdict that branches on it — but it is now a STEP ordering rather than a
# line ordering within one body: the step that reads the sensor must precede the
# step that invokes the verification body. Comparing line numbers across two files
# would be meaningless.
VERIFY_SH="$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh"
if [[ ! -r "$APPLY_WF" ]]; then
  fail "#7104 call-site: cannot read $APPLY_WF — the production pin cannot be evaluated"
elif [[ ! -r "$VERIFY_SH" ]]; then
  fail "#7104 call-site: cannot read $VERIFY_SH — the production pin cannot be evaluated"
else
  if grep -qE '\$\(infra_config_dpf_replaced[[:space:]]' "$APPLY_WF"; then
    pass "#7104 call-site: production INVOKES infra_config_dpf_replaced (not a hardcoded verdict)"
  else
    fail "#7104 call-site: the workflow does not call infra_config_dpf_replaced — the sensor's tests certify a function production does not run"
  fi
  if grep -qE '\$\(infra_config_frame_stability[[:space:]]' "$VERIFY_SH"; then
    pass "#7104 call-site: production INVOKES infra_config_frame_stability"
  else
    fail "#7104 call-site: infra-config-verify.sh does not call infra_config_frame_stability"
  fi
  # Ordering across the boundary: the sensor read must precede the step that runs
  # the verification body.
  DPF_LINE=$(grep -nE '\$\(infra_config_dpf_replaced[[:space:]]' "$APPLY_WF" | head -1 | cut -d: -f1)
  INVOKE_LINE=$(grep -nE '^[[:space:]]*run:[[:space:]]+bash[[:space:]]+.*infra-config-verify\.sh' "$APPLY_WF" | head -1 | cut -d: -f1)
  if [[ -n "$DPF_LINE" && -n "$INVOKE_LINE" && "$DPF_LINE" -lt "$INVOKE_LINE" ]]; then
    pass "#7104 call-site: the sensor is read (L$DPF_LINE) before the step that runs the verification body (L$INVOKE_LINE)"
  else
    fail "#7104 call-site: sensor/verdict ordering not established (dpf=$DPF_LINE invoke=$INVOKE_LINE)"
  fi
fi

if declare -F infra_config_frame_stability >/dev/null; then
  pass "#7104 stability: the adjudicator is defined (anti-vacuity for the fail-closed arms above)"
else
  fail "#7104 stability: infra_config_frame_stability is NOT defined — arms above are vacuous"
fi

# 16. NON-VACUITY of the whole block: the function must actually exist. Without this, renaming
#     it would make every arm above collapse to "command not found" -> non-zero -> and the six
#     fail-CLOSED arms would all still PASS while the four positive arms failed. Assert the
#     dispatch itself, mirroring the workflow's own `declare -F infra_config_red_alert` pattern.
if declare -F infra_config_dpf_replaced >/dev/null; then
  pass "#7104 dpf: the adjudicator is defined (anti-vacuity for the fail-closed arms above)"
else
  fail "#7104 dpf: infra_config_dpf_replaced is NOT defined — the fail-closed arms above are vacuous"
fi

# --- #7104 PR-B: infra_config_should_repush ------------------------------------------------
#
# The pure predicate that decides whether the documented webhook-restart race happened
# and a bounded re-push is warranted. Allow-list semantics: it returns 0 on exactly one
# shape and non-zero on everything else, including everything it cannot classify.
#
# THE BASELINE IS AN ARGUMENT, AND THAT IS THE WHOLE POINT (plan R19.3). The design as
# first written passed both a pre-frame timestamp AND an apply-start epoch, then
# described a third notion as the pass-2 baseline; under that reading pass 1 always sees
# start_ts == baseline, P4 says equality is fresh, and THE PREDICATE CAN NEVER RETURN 0
# ON ANY INPUT — a re-push that is unreachable by construction, which is the same defect
# class R19.1 found in the loop design. So there is ONE baseline parameter and ONE rule
# (`start_ts -lt baseline` — strictly older), and the CALLER supplies the right value:
#
#   pass 1  baseline = APPLY_START_EPOCH        "the frame predates this apply"
#   pass 2  baseline = the start_ts observed on pass 1, passed in as a step output
#                                               "the frame still has not moved"
#
# Equality is FRESH in both readings, matching the `-lt` the verification body already
# uses. On pass 2 that means the predicate declines a second re-push, which is the
# boundedness property — pass 2's terminal verdict is rendered by adjudicate_infra_config,
# not by this predicate.
mkresp() { # $1 = file, $2 = start_ts value (raw; may be non-numeric or the literal ABSENT)
  if [[ "$2" == "ABSENT" ]]; then
    printf '{"exit_code":0}\n' > "$1"
  else
    printf '{"exit_code":0,"start_ts":%s}\n' "$2" > "$1"
  fi
}

# THE BUILDER MUST VARY WITH ITS ARGUMENT (#7104 PR-B review).
#
# Every Guard 1 case below distinguishes verdicts by the start_ts mkresp() writes. If the
# builder ever stops reading $2 — the battery's G1-6 mutation makes it print a constant — then
# each case feeds the predicate the SAME frame, several cases return the same verdict under two
# different decision rules, and the matrix measures nothing while staying green.
#
# This is asserted directly, and it is also what gives G1-6 its own marker: before, G1-6 was
# detected only because the constant frame happened to break the P4 equality case, so it shared
# a marker with G1-3 and the two rows could not be told apart. A row that is detected by another
# row's assertion is not evidence that its own assertion works.
_b1="$TMP/_builder_probe_1.json"; _b2="$TMP/_builder_probe_2.json"
mkresp "$_b1" 1000
mkresp "$_b2" 2000
if [[ -s "$_b1" && -s "$_b2" ]] && ! cmp -s "$_b1" "$_b2"; then
  pass "#7104 P0 (builder fidelity): mkresp varies its output with its start_ts argument, so the Guard 1 cases below are distinguishable"
else
  fail "#7104 P0 (builder fidelity): mkresp produced identical frames for start_ts=1000 and start_ts=2000. Every Guard 1 case below feeds the predicate the same input, so the whole matrix is vacuous regardless of what it reports."
fi
rm -f "$_b1" "$_b2"

if ! declare -F infra_config_should_repush >/dev/null; then
  fail "#7104 should_repush: the predicate is not defined — every case below is vacuous"
else
  pass "#7104 should_repush: the predicate is defined (anti-vacuity for the arms below)"

  R="$TMP/repush-response.json"

  # P3 — the ONE arm that re-pushes. Asserted first so a predicate that simply
  # returns non-zero always (the R19.3 failure) cannot look correct on P1/P2/P4-P7.
  mkresp "$R" 1000
  if infra_config_should_repush "$R" true 2000 2>/dev/null; then
    pass "#7104 P3: dpf-replaced=true + frame strictly older than baseline -> re-push (exit 0)"
  else
    fail "#7104 P3: the one re-pushing arm did not return 0 — the recovery is unreachable"
  fi

  # P1 — dpf-replaced=false must refuse regardless of frame shape (R1(A), tasks 4.2).
  p1=0
  for ts in 1 1000 1999 3000; do
    mkresp "$R" "$ts"
    infra_config_should_repush "$R" false 2000 2>/dev/null && p1=1
  done
  if [[ "$p1" -eq 0 ]]; then
    pass "#7104 P1: dpf-replaced=false refuses for every frame shape tried (4 shapes)"
  else
    fail "#7104 P1: dpf-replaced=false returned 0 — no push was expected, so no frame can be stale"
  fi

  # P2 — the ^(true|false)$ polarity guard (R17.1). Anything that is not exactly
  # `true` or `false` is unclassifiable, NOT a synonym for false.
  p2=0
  p2n=0
  for v in "" null TRUE True yes 1 0 "true "; do
    mkresp "$R" 1000
    p2n=$((p2n + 1))
    infra_config_should_repush "$R" "$v" 2000 2>/dev/null && p2=1
  done
  if [[ "$p2" -eq 0 && "$p2n" -eq 8 ]]; then
    pass "#7104 P2: non-canonical dpf-replaced values all refuse ($p2n shapes)"
  else
    fail "#7104 P2: a non-canonical dpf-replaced value returned 0 (tried=$p2n) — the polarity guard is not allow-list"
  fi

  # P4 — equality is FRESH, matching the existing `-lt`.
  mkresp "$R" 2000
  if infra_config_should_repush "$R" true 2000 2>/dev/null; then
    fail "#7104 P4: start_ts == baseline returned 0 — equality must read as fresh, not stale"
  else
    pass "#7104 P4: start_ts == baseline refuses (equality is fresh)"
  fi

  # P5 — an unparseable / absent / non-numeric frame is unclassifiable. A missing
  # frame must NOT read as "unchanged" (R19.4 §5).
  p5=0
  p5n=0
  for ts in ABSENT '"notanumber"' 'null' '-5' '1.5'; do
    mkresp "$R" "$ts"
    p5n=$((p5n + 1))
    infra_config_should_repush "$R" true 2000 2>/dev/null && p5=1
  done
  printf 'not json at all\n' > "$R"
  p5n=$((p5n + 1))
  infra_config_should_repush "$R" true 2000 2>/dev/null && p5=1
  rm -f "$R"
  p5n=$((p5n + 1))
  infra_config_should_repush "$R" true 2000 2>/dev/null && p5=1
  if [[ "$p5" -eq 0 && "$p5n" -eq 7 ]]; then
    pass "#7104 P5: unparseable/absent/non-numeric frames all refuse ($p5n shapes)"
  else
    fail "#7104 P5: an unclassifiable frame returned 0 (tried=$p5n) — a frame that cannot be read is not a stale frame"
  fi

  # P6 — a baseline that cannot be trusted is not a baseline.
  p6=0
  p6n=0
  for base in "" abc null -1 2.5; do
    mkresp "$R" 1000
    p6n=$((p6n + 1))
    infra_config_should_repush "$R" true "$base" 2>/dev/null && p6=1
  done
  if [[ "$p6" -eq 0 && "$p6n" -eq 5 ]]; then
    pass "#7104 P6: non-numeric baseline refuses ($p6n shapes)"
  else
    fail "#7104 P6: a non-numeric baseline returned 0 (tried=$p6n)"
  fi

  # P8/R19.3 — THE SEQUENCE. One fixture, driven through both passes, with each
  # pass's verdict asserted INDEPENDENTLY so no case can pass by "the last attempt
  # succeeded" (tasks 4.7). This is the assertion the conflated-baseline design
  # could not satisfy.
  mkresp "$R" 1000                       # frame published before the apply began
  seq1=1; infra_config_should_repush "$R" true 2000 2>/dev/null && seq1=0
  # ... the re-push fires and the handler publishes a NEW frame ...
  mkresp "$R" 2500
  seq2=1; infra_config_should_repush "$R" true 1000 2>/dev/null && seq2=0
  if [[ "$seq1" -eq 0 && "$seq2" -eq 1 ]]; then
    pass "#7104 P8: sequence — stale frame re-pushes (pass 1 = 0), moved frame declines a second re-push (pass 2 != 0)"
  else
    fail "#7104 P8: sequence wrong (pass1=$seq1 expected 0; pass2=$seq2 expected non-zero)"
  fi

  # ... and the frame that did NOT move must still decline a second re-push
  # (boundedness), even though it is genuinely still stale.
  mkresp "$R" 1000
  if infra_config_should_repush "$R" true 1000 2>/dev/null; then
    fail "#7104 P8b: an unmoved frame authorised a SECOND re-push — boundedness is broken"
  else
    pass "#7104 P8b: an unmoved frame declines a second re-push (bounded to one attempt)"
  fi

  # The two input guards must DISCRIMINATE, not merely refuse (R19.4 §5). Mutation
  # measured: deleting either guard leaves every P2/P6 exit status unchanged — the
  # later `== "true"` allow-list check refuses non-canonical values on its own, and
  # bash coerces a non-numeric baseline to 0 inside `[[ -lt ]]`, which also refuses.
  # So an exit-status fixture cannot see these guards at all, and asserting only
  # exit status would certify two guards that could be deleted silently. What they
  # actually buy is a message that tells an operator WHICH input was unreadable,
  # instead of a run that looks like a routine no-push.
  mkresp "$R" 1000
  err_unclass=$(infra_config_should_repush "$R" TRUE 2000 2>&1 >/dev/null || true)
  err_false=$(infra_config_should_repush "$R" false 2000 2>&1 >/dev/null || true)
  if [[ "$err_unclass" == *"dpf-replaced"* && "$err_unclass" == *"not exactly true|false"* ]]; then
    pass "#7104 P2b: an unclassifiable dpf-replaced names itself on stderr"
  else
    fail "#7104 P2b: unclassifiable dpf-replaced produced no discriminating message (got: '${err_unclass:-<silence>}')"
  fi
  if [[ -z "$err_false" ]]; then
    pass "#7104 P2c: a plain dpf-replaced=false is SILENT — the ordinary no-push arm is not an anomaly"
  else
    fail "#7104 P2c: dpf-replaced=false emitted '$err_false'; it must be indistinguishable from a routine run"
  fi
  err_base=$(infra_config_should_repush "$R" true abc 2>&1 >/dev/null || true)
  if [[ "$err_base" == *"baseline"* && "$err_base" == *"not numeric"* ]]; then
    pass "#7104 P6b: a non-numeric baseline names itself on stderr"
  else
    fail "#7104 P6b: non-numeric baseline produced no discriminating message (got: '${err_base:-<silence>}')"
  fi
  err_frame=$(infra_config_should_repush "$R" true 2000 2>&1 >/dev/null || true)
  mkresp "$R" ABSENT
  err_noframe=$(infra_config_should_repush "$R" true 2000 2>&1 >/dev/null || true)
  if [[ "$err_noframe" == *"no numeric start_ts"* && "$err_noframe" != "$err_frame" ]]; then
    pass "#7104 P5b: a host that published NO frame is reported distinctly from a stale one"
  else
    fail "#7104 P5b: a missing frame does not discriminate itself (got: '${err_noframe:-<silence>}')"
  fi

  # Quiet on the success path: the exit status is the verdict (R18.1 convention).
  mkresp "$R" 1000
  out=$(infra_config_should_repush "$R" true 2000 2>/dev/null || true)
  if [[ -z "$out" ]]; then
    pass "#7104 should_repush: emits nothing on stdout — the exit status is the verdict"
  else
    fail "#7104 should_repush: wrote '$out' to stdout; the convention is quiet"
  fi
fi

# --- #7104 GUARD 1: workflow `if:` literals vs the shell that produces them -----------------
#
# A mis-keyed `if:` skips every re-push step, pass 2 never runs, and the five
# success()-gated steps downstream re-arm — one closes the founder's GitHub issues, one
# swaps the running container. The job greens having verified nothing: #6594's latched
# false-green, reintroduced by its own remedy.
#
# MEASURED at actionlint 1.7.7: a mistyped STEP ID is caught, but a mistyped OUTPUT NAME
# produces NO finding at all, because `outputs` types as {string => string} so every name
# is valid. And CI's actionlint job treats rc=1 as acceptable and is absent from
# scripts/required-checks.txt — so nothing in CI can fail a PR for this today. This guard
# is therefore the only thing standing between a typo and a silent false-green.
#
# Not hypothetical: while writing the pass-2 step, `DPF_REPLACED: ${{ steps.terraform_plan
# .outputs.dpf_replaced }}` was added against a step that carries no `id:`. It would have
# resolved to the empty string and OVERRIDDEN the working job-level env var.
GUARD1=$(python3 - "$APPLY_WF" "$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh" <<'PYEOF'
import sys, re, yaml

wf = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
sh = open(sys.argv[2], encoding='utf-8').read()

steps = []
for job in (wf.get('jobs') or {}).values():
    steps.extend(job.get('steps') or [])
ids = {s.get('id') for s in steps if s.get('id')}

# What the SCRIPT can emit, per output name. A value containing a shell expansion is
# recorded as dynamic (its literal set is unbounded, so a literal comparison against it
# cannot be validated this way).
emitted = {}
for m in re.finditer(r'echo\s+"([a-z_]+)=([^"]*)"\s*>>\s*"\$GITHUB_OUTPUT"', sh):
    name, val = m.group(1), m.group(2)
    emitted.setdefault(name, set()).add('<dynamic>' if '$' in val else val)

# Outputs produced by the workflow's own inline run: bodies (not by the script).
wf_emitted = {}
for s in steps:
    body = s.get('run')
    if not isinstance(body, str) or not s.get('id'):
        continue
    for m in re.finditer(r'echo\s+"([a-z_]+)=([^"]*)"\s*>>\s*"\$GITHUB_OUTPUT"', body):
        wf_emitted.setdefault(s['id'], {}).setdefault(m.group(1), set()).add(
            '<dynamic>' if '$' in m.group(2) else m.group(2))

# SCRIPT_STEPS IS DERIVED, NOT HARDCODED (#7104 PR-B review).
#
# It used to be the literal set {'infra_config_gate', 'infra_config_gate_pass2'}. A hardcoded
# set is a snapshot: rename a step, or add a THIRD invocation of the script, and the new step
# is silently outside the set — so none of its `if:`/`env:` literals are validated against
# what the script can emit, which is the entire job of this guard. Derived from the workflow,
# a new invocation is covered the moment it exists.
#
# AND THE INVOCATION ITSELF IS ASSERTED. Nothing previously pinned that pass 2 runs the TESTED
# artifact at all: the old membership test was `head -1` over a population of two, so a pass-2
# step whose `run:` had been changed to an inline body — the 240 duplicated lines of untestable
# YAML the extraction exists to prevent — would still have been treated as a script step and
# graded against the script's outputs. Here the two facts are the same fact: a step is a script
# step BECAUSE its `run:` invokes the script.
SCRIPT_INVOKE = re.compile(r'bash\s+\S*infra-config-verify\.sh')
SCRIPT_STEPS = {s['id'] for s in steps
                if s.get('id') and isinstance(s.get('run'), str) and SCRIPT_INVOKE.search(s['run'])}

# THE GATE CHAIN, DERIVED — because the COUNT PIN below must not quantify over the whole file.
#
# `checked` used to count every `steps.X.outputs.Y` reference anywhere in this 1985-line SHARED
# workflow, and 2 of the 12 it measured (`steps.check_4804.outputs.open`, twice) have nothing to
# do with the infra-config gate. So the flush pin reddened a REGISTERED gate for any PR that
# added an unrelated step-output reference — a guard that fires on work it does not guard trains
# people to bump its literal without reading it, which is how a flush pin becomes a rubber stamp.
#
# The chain is the fixpoint of "CONSUMES the chain", seeded on the steps that invoke the tested
# artifact. Derived rather than enumerated for the same reason SCRIPT_STEPS is: an enumerated set
# is a snapshot, and a newly wired re-push step would sit outside it silently.
# `outcome`/`conclusion` count as edges as well as `outputs`, because the re-push chain is wired
# on step OUTCOMES and an outputs-only closure drops it.
#
# CONSUMES ONLY — the closure deliberately does NOT also pull in everything a chain step reads.
# That backward half was tried and reintroduced the very problem this scoping exists to fix: the
# moment the "Close #4804" step gained a verdict gate, its UNRELATED `steps.check_4804.outputs.open`
# reference was dragged onto the chain and the count jumped by two. A step joins because it
# consumes the gate; a reference counts because its TARGET is on the chain. Those are different
# questions and conflating them makes the pin sensitive to whatever else happens to share an `if:`.
CHAIN_EDGE = re.compile(r"steps\.([A-Za-z0-9_-]+)\.(?:outputs\.[A-Za-z0-9_-]+|outcome|conclusion)")

def _step_refs(s):
    out = set()
    for txt in [s.get('if')] + [v for v in (s.get('env') or {}).values()]:
        if isinstance(txt, str):
            out |= set(CHAIN_EDGE.findall(txt))
    return out

GATE_CHAIN = set(SCRIPT_STEPS)
for _ in range(len(steps) + 1):
    grew = False
    for s in steps:
        r = _step_refs(s)
        if r & GATE_CHAIN:
            sid = s.get('id')
            if sid and sid not in GATE_CHAIN:
                GATE_CHAIN.add(sid)
                grew = True
    if not grew:
        break

ref = re.compile(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)\s*==\s*'([^']*)'")

problems, checked = [], 0

# The chain must not collapse back to the two seed steps: that would silently shrink what the
# count pin quantifies over, which is the same vacuity the pin exists to prevent one level up.
if len(GATE_CHAIN) < 5:
    problems.append("the derived gate chain is %s (%d steps); expected at least 5 — the closure "
                    "stopped following the re-push wiring, so the reference count below no longer "
                    "covers the chain it names." % (sorted(GATE_CHAIN), len(GATE_CHAIN)))

# The derivation must not silently yield the empty set (which would make every literal check
# below vacuous), and it must still find BOTH passes.
if len(SCRIPT_STEPS) < 2:
    problems.append("only %d step(s) invoke infra-config-verify.sh (%s); expected at least 2 "
                    "(pass 1 and pass 2). Either a pass was removed, or its run: no longer "
                    "invokes the tested artifact and has been inlined back into YAML."
                    % (len(SCRIPT_STEPS), sorted(SCRIPT_STEPS)))

# PASS 2 MUST HARDCODE THE 404 ESCAPE HATCH OFF, AND THE LITERAL IS PINNED.
#
# This is R20.4's entire fix and it is one word from being false: `ALLOW_MISSING_STATUS: "true"`
# on pass 2 would let the escape hatch green a run that has ALREADY WRITTEN PRODUCTION, which is
# strictly worse than the race it recovers from. Nothing asserted the value.
p2 = [s for s in steps if s.get('id') == 'infra_config_gate_pass2']
if not p2:
    problems.append("the pass-2 step (id: infra_config_gate_pass2) does not exist")
else:
    ams = (p2[0].get('env') or {}).get('ALLOW_MISSING_STATUS')
    if str(ams).strip().lower() != 'false':
        problems.append("pass 2 sets ALLOW_MISSING_STATUS to %r, expected the hardcoded literal "
                        "'false' — the 404 escape hatch must never be reachable on a pass that "
                        "runs after a production write" % (ams,))
for s in steps:
    cond = s.get('if')
    if not isinstance(cond, str):
        continue
    for sid, out, lit in ref.findall(cond):
        # Only gate-chain references are COUNTED; every reference is still VALIDATED. A
        # dangling step id anywhere in the workflow is a bug worth failing on, and checking it
        # is free — but it must not move the flush count, or the pin reds on unrelated work.
        if sid in GATE_CHAIN:
            checked += 1
        if sid not in ids:
            problems.append("if: names step id '%s', which does not exist" % sid)
            continue
        if sid in SCRIPT_STEPS:
            vals = emitted.get(out)
            if vals is None:
                problems.append("if: compares steps.%s.outputs.%s, which infra-config-verify.sh never writes" % (sid, out))
            elif '<dynamic>' not in vals and lit not in vals:
                problems.append("if: compares %s == '%s' but the script only emits %s" % (out, lit, sorted(vals)))
        else:
            vals = (wf_emitted.get(sid) or {}).get(out)
            if vals is None:
                problems.append("if: compares steps.%s.outputs.%s, which step '%s' never writes" % (sid, out, sid))

# Every `env:` expression naming a step output must resolve too — this is the shape that
# silently yields the empty string rather than erroring.
envref = re.compile(r"steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)")
for s in steps:
    for v in (s.get('env') or {}).values():
        if not isinstance(v, str):
            continue
        for sid, out in envref.findall(v):
            if sid in GATE_CHAIN:
                checked += 1
            if sid not in ids:
                problems.append("env: names step id '%s', which does not exist" % sid)
            elif sid in SCRIPT_STEPS and out not in emitted:
                problems.append("env: reads steps.%s.outputs.%s, which infra-config-verify.sh never writes" % (sid, out))
            # THE SAME CHECK FOR NON-SCRIPT PRODUCERS (#7546 review). The `if:` loop above has
            # exactly this branch -- `vals = (wf_emitted.get(sid) or {}).get(out)` -- and the
            # `env:` loop did not, so an env reference to a WORKFLOW step's output was validated
            # for the step id and never for the output NAME. Measured: deleting the producer line
            # `echo "repush_start_epoch=..." >> "$GITHUB_OUTPUT"` left Guard 1 reporting CHECKED=19
            # and zero problems, while pass 2's absolute freshness pin silently degraded to the
            # weaker APPLY_START_EPOCH reference and still emitted `freshness_evidence=verified`.
            # `env:` is the shape that yields the empty string rather than erroring, which is
            # exactly why it needed the stricter branch, not the looser one.
            elif sid not in SCRIPT_STEPS and (wf_emitted.get(sid) or {}).get(out) is None:
                problems.append("env: reads steps.%s.outputs.%s, which step '%s' never writes to "
                                "$GITHUB_OUTPUT -- this resolves to the EMPTY STRING at runtime, "
                                "silently, and the consumer degrades rather than failing"
                                % (sid, out, sid))

# The backstop must exist and must be always()-keyed.
backstop = [s for s in steps
            if isinstance(s.get('run'), str) and 'NO TERMINAL VERDICT' in s['run']]
if not backstop:
    problems.append("the terminal-verdict backstop step is absent")
elif 'always()' not in str(backstop[0].get('if', '')):
    problems.append("the terminal-verdict backstop exists but is not keyed on always()")

print("CHECKED=%d" % checked)
for p in problems:
    print("PROBLEM=%s" % p)
PYEOF
) || GUARD1="PROBLEM=guard 1 could not run (python3/pyyaml unavailable or the workflow did not parse)"

g1_checked=$(printf '%s\n' "$GUARD1" | sed -n 's/^CHECKED=//p')
g1_problems=$(printf '%s\n' "$GUARD1" | grep -c '^PROBLEM=' || true)
# FLUSH, NOT A FLOOR (#7104 PR-B review). This was `>= 4` against a measured 12, so eight of the
# twelve references could have stopped being examined with the guard still reporting clean — an
# anti-vacuity floor whose slack is larger than the thing it guards is not a floor. Pinned flush
# so drift is loud IN BOTH DIRECTIONS: a reference that disappears from the extractor reds, and a
# newly added if:/env: step-output reference also reds, which is the review prompt you want when
# someone wires a new consumer onto this chain. Re-derive and update on a deliberate change.
#
# SCOPED TO THE GATE CHAIN (#7104 PR-B review, F8). This was 12 measured over the whole
# workflow, 2 of which were `steps.check_4804.outputs.open` — unrelated to this gate. Now 11,
# measured over the derived chain {infra_config_gate, infra_config_gate_pass2, repush_plan,
# repush_apply, ledger_body, terraform_apply}, so an unrelated step-output reference elsewhere
# in this shared workflow no longer reds a registered gate.
#
# 11 -> 13 for #7104 P0-B: the alert step now reads pass 1's verdict (so it can name
# `unadjudicated` rather than describe a delivery failure the gate never reported), and the
# post-apply summary reads pass 2's verdict (so "Self-healed" is gated on the re-push having
# WORKED rather than merely having happened). The step-`outcome` references added alongside them
# are not counted here — the extractor's regex quantifies over `.outputs.` only.
#
# 13 -> 19: the three `success()`-gated steps downstream of the gate (the container swap, the
# #4804 close-out, the drift-issue auto-close) are now gated on the VERDICT as well, two
# references each. `unadjudicated` is the 404 first-bootstrap escape hatch — the gate tolerates a
# missing status endpoint, checks nothing, and exits 0 — so `success()` alone re-armed all three
# behind a verification that never happened.
# 19 -> 22 (#7546 review): the liveness probe now publishes a three-valued `listener_state`,
# and the backstop, the alert step and the post-apply summary each consume it so that
# "the probe could not run" stops being indistinguishable from "the channel is down".
# Three new env: refs on the gate chain, re-derived deliberately as this pin demands.
G1_EXPECTED_REFERENCES=22
if [[ "$g1_problems" -eq 0 && "${g1_checked:-0}" == "$G1_EXPECTED_REFERENCES" ]]; then
  pass "#7104 WORKFLOW-REF PIN: all $g1_checked workflow if:/env: references resolve, and every compared literal is one the producer can emit"
elif [[ "$g1_problems" -eq 0 ]]; then
  fail "#7104 WORKFLOW-REF PIN: examined ${g1_checked:-0} if:/env: step-output reference(s), expected exactly $G1_EXPECTED_REFERENCES. Fewer means the extractor stopped matching and its clean verdict is vacuous; more means a new consumer was wired onto the gate chain — re-derive and update G1_EXPECTED_REFERENCES deliberately."
else
  fail "#7104 WORKFLOW-REF PIN: $g1_problems problem(s) over ${g1_checked:-0} reference(s):"
  printf '%s\n' "$GUARD1" | sed -n 's/^PROBLEM=/      - /p' >&2
fi
# GUARD 3's LITERAL IS THE MEASUREMENT, so it is pinned to the measured value and not
# merely to "some literal". Mutation measured: flipping `repush_graded == '1'` to `'2'`
# passed every check above, because the generic literal check cannot validate an output
# whose producer writes it dynamically. But that literal is the ONLY thing bounding the
# recovery's blast radius: task 4.0 measured the re-push plan against live prd state as
# exactly ONE changing managed resource with host_creates=0, and deploy_pipeline_fix
# depends_on infra_config_handler_bootstrap, which carries an SSH remote-exec that
# -target reaches transitively. A widened literal is a production write against a bridge
# this job tears down three steps later.
#
# Changing the bound therefore requires re-running task 4.0 and editing this line, which
# is the two-producer property the guard is for.
TASK_40_MEASURED_CARDINALITY=1
#
# ------------------------------------------------------------------------------------------
# WHY THIS IS NOW A PARSED-YAML EQUALITY AND NOT A grep (#7104 PR-B review).
#
# The three assertions this block replaces were: a `grep -qE "...repush_graded == '1'"` over
# the WHOLE FILE, and a `grep -nE '^\s+id: repush_apply$' -A2 | grep -qE "if: success\(\)"`.
# Both are extractor escapes, and a mutation battery run against them measured the top
# survivor of the whole PR:
#
#   compose (a) put `if:` ABOVE `id:` in the step, so the `-A2` window — which is key-ORDER
#   dependent and would also break on a two-space `id:` — no longer contained the condition;
#   (b) changed the condition to read `.outcome` instead of `.outputs.`; and (c) DEMOTED the
#   graded literal into a comment. The whole-file grep still found `repush_graded == '1'` in
#   that comment and passed. Net effect: the production apply fired whenever the plan step
#   merely SUCCEEDED, regardless of the grade — the exact blast-radius bound task 4.0 exists
#   to hold — and the suite reported 130/0, rc=0.
#
# A negative grep ("the condition does not say success()") cannot close this: there are
# unboundedly many conditions that are neither the right one nor the one you thought to
# forbid. The assertion has to be POSITIVE EQUALITY against the measured literal, made on the
# resolved mapping rather than on bytes, so that any edit to the condition — reordered keys,
# a different operator, a demoted literal, a folded scalar — changes the thing compared.
# ------------------------------------------------------------------------------------------
GUARD3=$(python3 - "$APPLY_WF" "$TASK_40_MEASURED_CARDINALITY" <<'PYEOF'
import sys, yaml

wf = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
card = sys.argv[2]

steps = []
for job in (wf.get('jobs') or {}).values():
    steps.extend(job.get('steps') or [])
byid = {s.get('id'): s for s in steps if s.get('id')}

problems = []

def norm(v):
    return " ".join(str(v).split()) if v is not None else None

# The two conditions that bound the recovery, each pinned by EQUALITY to the literal that is
# the measurement. Written as a table so adding a bounded step means adding a row, not
# inventing a new grep.
EXPECT = {
    'repush_plan':  "steps.infra_config_gate.outputs.repush_needed == 'true'",
    'repush_apply': "steps.repush_plan.outputs.repush_graded == '%s'" % card,
}
for sid, want in EXPECT.items():
    st = byid.get(sid)
    if st is None:
        problems.append("step id '%s' does not exist — the recovery chain is broken or renamed" % sid)
        continue
    got = norm(st.get('if'))
    if got != want:
        problems.append("steps.%s.if is %r, expected exactly %r" % (sid, got, want))

# BOUNDEDNESS INSIDE ONE STEP. The step-level count elsewhere cannot see a loop: a single
# step body containing `for _i in 1 2 3; do terraform apply ... tfplan-repush; done` is ONE
# line and ONE step, so both "independent producers" agree and both are wrong. Forbid a loop
# keyword in the body that writes production, and count occurrences within that body.
ap = byid.get('repush_apply')
if ap is not None:
    body = ap.get('run') or ''
    code = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith('#'))
    import re as _re
    # OCCURRENCES, NOT LINES (#7546 review). The comment above already prescribed "count
    # occurrences within that body" and the code counted LINES, so two shapes walked through all
    # three producers with the whole suite green, both measured:
    #
    #   terraform apply ... tfplan-repush ; terraform apply ... tfplan-repush   (one line)
    #   terraform apply -auto-approve -input=false tfplan                       (the FIRST plan
    #       file, which survives on the runner until `Reclaim the plan artifacts`)
    #
    # The second is the sharper one: every counter here and in Guard 2 (7) is keyed on the
    # literal `tfplan-repush`, so an apply of a DIFFERENT plan file is invisible to all of them.
    # The chokepoint has to be "a production apply", not "a line mentioning one plan filename".
    n_apply = len(_re.findall(r'(?:^|[\s;&|(])terraform\s+apply\b', code))
    if n_apply != 1:
        problems.append("the repush_apply body runs `terraform apply` %d time(s), expected exactly 1 "
                        "— counted as OCCURRENCES rather than lines, because `a ; b` on one physical "
                        "line is two production writes" % n_apply)
    if not _re.search(r'terraform\s+apply\b[^\n;&|]*\btfplan-repush\b', code):
        problems.append("the repush_apply body's production apply does not use tfplan-repush — an "
                        "apply of any other plan file is a second, unbounded production write that "
                        "the tfplan-repush-keyed counters are structurally unable to see")
    loopkw = _re.search(r'(^|[;&|]|\bdo\b)\s*(for|while|until)\s', code, _re.M)
    if loopkw:
        problems.append("the repush_apply body contains a loop keyword (%r) — one line and one step "
                        "can still be an unbounded number of production writes"
                        % loopkw.group(2))

# ---- FOUR GUARDS WITH NO PRODUCER-SIDE PIN (#7104 PR-B review, security) -------------------
#
# Each of these was measured DELETABLE with every guard in this suite still green, and none had
# a battery row. A guard nothing asserts the existence of is a guard that survives exactly until
# someone finds it inconvenient — and all four sit on the step that authorises the production
# write, which is the last place that should be true.
#
# Pinned on the SHAPE the guard must have (a comparison against a specific literal, a specific
# jq filter, a trap naming a specific file) rather than on prose, so a comment describing the
# prohibition cannot satisfy the pin. Anchored inside the OWNING STEP's body rather than over the
# whole 2000-line workflow, so a same-shaped line elsewhere cannot stand in for a deleted one.
pl = byid.get('repush_plan')
if pl is None:
    problems.append("step id 'repush_plan' does not exist, so its four internal guards cannot be pinned")
else:
    plan_body = pl.get('run') or ''
    plan_code = "\n".join(l for l in plan_body.splitlines() if not l.lstrip().startswith('#'))

    # (1) THE ADDRESS-SET ASSERT. `GRADED == 1` says one managed resource changes; it does not
    #     say WHICH. A plan replacing one entirely different resource satisfies cardinality.
    if not _re.search(r'\$addrs"?\s*!=\s*"terraform_data\.deploy_pipeline_fix"', plan_code):
        problems.append("the re-push plan step no longer asserts the CHANGING ADDRESS SET equals "
                        "terraform_data.deploy_pipeline_fix — cardinality alone passes a plan that "
                        "replaces one entirely different production resource")

    # (2) THE CARDINALITY ASSERT ITSELF, at the producer. The consumer-side `if:` literal is
    #     pinned above; this is the half that makes the grade mean anything.
    if not _re.search(r'"\$GRADED"\s*-ne\s*1\b', plan_code):
        problems.append("the re-push plan step no longer refuses a grade other than 1 "
                        "(`[[ \"$GRADED\" -ne 1 ]]`) — the apply's `if:` would then be keyed on a "
                        "literal the producer never enforces")

    # (3) THE DESTROY GUARD. The re-push must not be able to destroy anything, and the filter is
    #     the shared one the first apply uses.
    if 'destroy-guard-filter-web-platform.jq' not in plan_code:
        problems.append("the re-push plan step no longer runs the destroy-guard jq filter — the "
                        "bounded recovery could plan a destroy against an unreplaceable host")

    # (4) THE TRAP. tfplan-repush.json carries the live prd Doppler token and the webhook HMAC in
    #     CLEARTEXT — terraform's JSON serialization ignores `sensitive`.
    if not _re.search(r"trap\s+'rm -f tfplan-repush\.json'\s+EXIT", plan_code):
        problems.append("the re-push plan step no longer traps `rm -f tfplan-repush.json` on EXIT "
                        "— that render carries the live prd Doppler token and the webhook HMAC in "
                        "cleartext, and the trap is what reclaims it on the failure paths")

print("OK" if not problems else "")
for p in problems:
    print("PROBLEM=%s" % p)
PYEOF
) || GUARD3="PROBLEM=guard 3 could not run (python3/pyyaml unavailable or the workflow did not parse)"

g3_problems=$(printf '%s\n' "$GUARD3" | grep -c '^PROBLEM=' || true)
if [[ "$g3_problems" -eq 0 ]]; then
  pass "#7104 CARDINALITY PIN: repush_plan and repush_apply carry EXACTLY their measured conditions (apply keyed on repush_graded == '${TASK_40_MEASURED_CARDINALITY}'), and the apply body holds one unlooped production write"
else
  fail "#7104 CARDINALITY PIN: $g3_problems problem(s). Widening the apply's literal re-opens the transitive -target blast radius task 4.0 measured shut; narrowing it disables the recovery silently:"
  printf '%s\n' "$GUARD3" | sed -n 's/^PROBLEM=/      - /p' >&2
fi

# ------------------------------------------------------------------------------------------
# A NOTE ON GUARD NAMES, because this PR carries TWO numbering systems (#7104 review).
#
# The plan uses "Guard N" twice with different referents, and `scripts/lint-guard-contract.py`
# lints only one of them (it walks knowledge-base/project/plans/** and never sees this file):
#
#   plan `## Guard Contract`  Guard 1 = the predicate infra_config_should_repush
#                             Guard 2 = the production call-site pin
#   plan R22.5                Guard 1 = the mis-keyed `if:` pin
#                             Guard 2 = the verbatim-move gate
#                             Guard 3 = the graded cardinality
#
# Both sets ship, so a reader grepping "Guard 1" in this file got two different guards. The two
# labels here that followed R22.5's numbering are renamed to descriptive names — WORKFLOW-REF PIN
# and CARDINALITY PIN — so no number is shared. `Guard 2 (N)` is deliberately UNCHANGED: it tracks
# the `## Guard Contract` numbering, which is the one the lint enforces, and renaming it would
# break that correspondence. R22.5's Guard 2 (the verbatim-move gate) has no label here at all
# because it does not ship as a standing assert — it was a commit-time verification, since its
# prescribed baseline `git show origin/main:<workflow>` FLIPS at merge.
#
# --- #7104 AC18 ----------------------------------------------------------------------------
# The step-level error-tolerance key is banned outright in this workflow: it is how a
# verification gate stops failing closed, which is the entire defect class PR-B exists in.
# Asserted as `! grep -q` rather than `grep -c ... = 0`, because a grep -c returning 0
# EXITS 1 and would abort a set -e harness on the passing case (R16.3).
#
# The literal is spelled from parts here on purpose. A test that greps a workflow for a
# forbidden literal, while itself naming that literal in prose, false-FAILS the moment the
# two files are ever scanned together — and more importantly it is the shape that made
# this assert trip on its OWN explanatory comment while it was being written.
FORBIDDEN_KEY="continue-on""-error"
#
# ...AND THE SAME TRAP APPLIES TO THE WORKFLOW, WHICH THIS ASSERT ORIGINALLY MISSED
# (#7104 PR-B review). Spelling the literal from parts protects THIS file; the assert was
# still a bare `grep -q` over the ENTIRE workflow, so it matched any prose there too. It
# fired for real: a review fix added a comment to the ledger step explaining WHY the key is
# not used (it pins `conclusion` to success and would feed
# scripts/followthroughs/moved-block-wedge-5887.sh green over red) and the guard reported the
# workflow as carrying the key. The forbidden thing is a YAML KEY, so the assertion is now
# made against the PARSED DOCUMENT — a comment cannot produce a mapping key, so the explanation
# and the guard can coexist. This also strengthens it: the bare grep could not distinguish
# job-level from step-level, and now both are checked and named.
ac18_ce=$(python3 - "$APPLY_WF" "$FORBIDDEN_KEY" <<'PYEOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
key = sys.argv[2]
hits = []
for jn, job in (wf.get('jobs') or {}).items():
    if not isinstance(job, dict):
        continue
    if key in job:
        hits.append("job '%s'" % jn)
    for st in (job.get('steps') or []):
        if isinstance(st, dict) and key in st:
            hits.append("step '%s' in job '%s'" % (st.get('name') or st.get('id') or '<unnamed>', jn))
print("; ".join(hits))
PYEOF
) || ac18_ce="ERR"
if [[ "$ac18_ce" == "ERR" ]]; then
  fail "#7104 AC18: could not parse the workflow to check for the error-tolerance key — the guard did not evaluate, so its silence cannot be read as clean."
elif [[ -n "$ac18_ce" ]]; then
  fail "#7104 AC18: apply-deploy-pipeline-fix.yml carries '$FORBIDDEN_KEY' at: ${ac18_ce}. A verification gate that tolerates its own failure does not fail closed."
else
  pass "#7104 AC18: no job or step in the workflow carries the error-tolerance key"
fi

# The ledger must never notify. It is created CLOSED and only ever edited, because GitHub
# notifies on comments and state changes but not on body/title edits. Task 7.7's repo-watch
# probe was CUT (the API needs a scope we do not hold), so this assertion IS the property.
#
# Scoped to the LEDGER, not a bare grep: this workflow legitimately comments on #4804 and on
# drift issues, and an unscoped assert would fail on pre-existing, correct code — the
# false-positive that a bare-token assert produces.
if grep -nE 'gh issue (comment|reopen)' "$APPLY_WF" | grep -qiE 'ledger|LEDGER_TITLE|\$num'; then
  fail "#7104 AC18: the workflow comments on or reopens the ledger issue — either would notify, defeating the property the closed-ledger design buys by construction"
else
  pass "#7104 AC18: the workflow never comments on or reopens the ledger (it is created closed and only edited)"
fi

# R19.4 §4: the plan's own "six success()-gated steps" is wrong; the measured count is five.
# Pinned because the backstop's whole justification is what re-arms behind a false green --
# two of these five close the founder's GitHub issues and one swaps the running container.
#
# MEMBERSHIP AND STRUCTURE, NOT A COUNT (#7546 review). This was `== 5` over a set, and a
# scalar over a set samples only its SIZE. Two mutations were measured walking straight
# through it with all four suites green:
#
#   (a) `&&` -> `||` in the redeploy gate. ONE CHARACTER. The production container swap then
#       runs on success() alone, ignoring BOTH verdicts -- the exact property this block names.
#       The count stayed 5 (the substring `success()` is still there) and the WORKFLOW-REF PIN
#       stayed unchanged (the same references still exist).
#   (b) deleting the verdict clause and leaving it as a YAML comment. The ship-gate test's
#       three `toMatch` substring checks all still passed, because it reads the file raw.
#
# A substring test cannot see a boolean structure. So each step is pinned by NAME to its
# whitespace-normalised condition, exactly as Guard 3 pins repush_plan/repush_apply -- which
# also makes a substitution (gut one member, add a success()-gated no-op) loud, and makes the
# failure name the step rather than blaming a count.
ac18_measured=$(python3 - "$APPLY_WF" <<'PYEOF'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
steps = wf['jobs']['apply']['steps']
gi = next(i for i, s in enumerate(steps) if s.get('id') == 'infra_config_gate')

VERDICT = ("(steps.infra_config_gate.outputs.verdict == 'verified' || "
           "steps.infra_config_gate_pass2.outputs.verdict == 'verified')")
EXPECT = {
    'Redeploy to load applied profile and assert loaded==committed (#5875 item 4)':
        "success() && " + VERDICT,
    'Check whether':
        "success()",
    'Verify journald_storage no-SSH surface is live (AC12,':
        "success() && steps.check_4804.outputs.open == 'true'",
    'Close':
        "success() && env.PLAN_HAS_CHANGES == 'true' && "
        "steps.check_4804.outputs.open == 'true' && " + VERDICT,
    'Auto-close any open drift issues for this stack':
        "success() && env.PLAN_HAS_CHANGES == 'true' && " + VERDICT,
}
got = {}
for st in steps[gi+1:]:
    c = st.get('if')
    if isinstance(c, str) and 'success()' in c:
        got[st.get('name')] = " ".join(c.split())

problems = []
for name in sorted(set(EXPECT) | set(got)):
    if name not in got:
        problems.append("step %r is no longer success()-gated downstream of the gate" % name)
    elif name not in EXPECT:
        problems.append("NEW success()-gated step %r downstream of the gate, condition %r -- it "
                        "re-arms behind a false green and is not pinned" % (name, got[name]))
    elif got[name] != EXPECT[name]:
        problems.append("step %r has if: %r, pinned as %r" % (name, got[name], EXPECT[name]))
print("OK" if not problems else "; ".join(problems))
PYEOF
) || ac18_measured="ERR"
if [[ "$ac18_measured" == "OK" ]]; then
  pass "#7104 AC18: all 5 success()-gated steps downstream of the gate carry their pinned condition VERBATIM -- the 3 that re-arm production (container swap, #4804 close, drift auto-close) are structurally gated on a verdict, so an && -> || inversion is loud rather than invisible to a count"
else
  fail "#7104 AC18: the success()-gated step set downstream of the gate drifted from its pin: $ac18_measured. These steps re-arm behind a false green -- two close the founder's GitHub issues and one swaps the running container. If the change is deliberate, update the EXPECT table and say why in the commit."
fi

# THE SCANNER'S OFFSET INVARIANT, ASSERTED OVER THE WHOLE DIRECTORY (#7546 review).
#
# infra-config-shellscan.py states this invariant twice -- "newlines are preserved inside every
# blanked span so line numbers and offsets survive unchanged", and "_blank preserves byte offsets
# exactly ... so the operator can be FOUND in the blanked text and its target READ from the
# original at the same offset". LENGTH was preserved. NEWLINE POSITIONS were not:
#
#   * `_blank`'s escape branch emitted two SPACES for a backslash-NEWLINE inside a double-quoted
#     string (a line continuation);
#   * `strip_noise`'s arithmetic substitution flattened a MULTI-LINE $(( )) with ' ' * len(),
#     while the `[[ ]]` substitution two lines below already did it correctly.
#
# Measured: 33 of 163 apps/web-platform/infra/*.sh diverged. It was LATENT rather than live --
# the two files the guards actually scan did not diverge -- and that is exactly why it needs a
# standing assertion instead of a fix: `loop_depth_map` keys `depth_at` by CLEAN line number
# while its caller looks up RAW line numbers from a grep, so one ordinary edit adding a
# multi-line $(( )) or a `\`-newline ABOVE the adjudicate call silently shifts every lookup and
# the D1 depth check reads the wrong line. Quantified over the DIRECTORY, not over the two
# current subjects, because the next subject is the one that will diverge.
SCAN_INVARIANT=$(python3 - "$SCRIPT_DIR" <<'PYEOF'
import glob, importlib.util, os, pathlib, sys

d = sys.argv[1]
_spec = importlib.util.spec_from_file_location('shellscan', os.path.join(d, 'infra-config-shellscan.py'))
_m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_m)

files = sorted(glob.glob(os.path.join(d, '*.sh')))
if len(files) < 20:
    print("SCAN-ERROR: only %d *.sh found in %s -- the sweep is vacuous" % (len(files), d))
    sys.exit(0)
bad = []
for f in files:
    raw = pathlib.Path(f).read_text(encoding='utf-8', errors='replace')
    for name, fn in (('strip_noise', _m.strip_noise), ('strip_comments', _m.strip_comments)):
        out = fn(raw)
        if len(out) != len(raw):
            bad.append("%s: %s changed LENGTH %d -> %d" % (os.path.basename(f), name, len(raw), len(out)))
        elif out.count('\n') != raw.count('\n'):
            bad.append("%s: %s changed NEWLINE COUNT %d -> %d"
                       % (os.path.basename(f), name, raw.count('\n'), out.count('\n')))
print("OK %d" % len(files) if not bad else "; ".join(bad[:6]))
PYEOF
) || SCAN_INVARIANT="SCAN-ERROR (python3 unavailable)"
if [[ "$SCAN_INVARIANT" == OK\ * ]]; then
  pass "#7104 scanner: strip_noise/strip_comments preserve byte LENGTH and NEWLINE POSITIONS over all ${SCAN_INVARIANT#OK } infra/*.sh — the invariant the redirect detector's read-from-raw-at-blanked-offset and loop_depth_map's line keys both rest on"
else
  fail "#7104 scanner: the offset/newline invariant is BROKEN — $SCAN_INVARIANT. loop_depth_map keys depth_at by CLEAN line number while its caller looks up RAW line numbers, so any divergence above the adjudicate call silently shifts the D1 depth check onto the wrong line."
fi

# EVERY OPERATOR-FACING LEVER IS COMPLETE, AND CARRIES ITS FORBIDDEN TARGET (#7546 review).
#
# The diff hands a non-technical founder -- and, explicitly in the issue body, "an engineer/agent"
# -- a terraform command to run against production. Measured on the shipped tree: FOUR emission
# sites, and ZERO of them carried `-target=`. This file's own comment on the re-push plan says
# why that matters: "-replace alone would plan the whole graph" -- 230 resources, 20 variables
# with no default, on a root containing a host the repo treats as unreplaceable. The workflow
# gets its OWN invocation right and got the one it hands a human wrong, four times out of four.
#
# The guardrail sweep had the same shape: 3 of 4 sites named the forbidden target, and the one
# that did not was the backstop arm that fires when the re-push has ALREADY bricked the channel
# -- i.e. the state with no fallback. That is the "two-thirds false annotation" class this PR
# exists to close, recurring inside the fix, and a per-site sweep is what catches it rather than
# a spot check on the site someone happened to be editing.
LEVER_AUDIT=$(awk '/apply -replace=terraform_data\.infra_config_handler_bootstrap/{
    n++
    if (!/-target=terraform_data\.infra_config_handler_bootstrap/) bad = bad " L" NR ":no-target"
    if (!/doppler run --name-transformer tf-var/)                  bad = bad " L" NR ":no-doppler"
    if (!/Do NOT run terraform apply -replace=hcloud_server\.web/) bad = bad " L" NR ":no-guardrail"
  } END { printf "%d%s", n+0, bad }' "$APPLY_WF")
lever_n="${LEVER_AUDIT%%[!0-9]*}"
lever_bad="${LEVER_AUDIT#"$lever_n"}"
if [[ "${lever_n:-0}" -ge 1 && -z "$lever_bad" ]]; then
  pass "#7104 lever: all $lever_n operator-facing handler-replace lever(s) are TARGETED (-replace alone plans the whole 230-resource graph), doppler-wrapped (so the operator is never prompted for 20 secret variables), and name the forbidden hcloud_server.web target"
else
  fail "#7104 lever: operator-facing recovery command(s) are incomplete or unguarded ($lever_n site(s);$lever_bad). A bare -replace plans the WHOLE graph, an unwrapped terraform prompts a non-technical founder for every secret variable, and an emission without the forbidden-target sentence is how a prior annotation told an operator to destroy an unreplaceable host."
fi

# Cardinality floor: if the reference extractor silently matches nothing, the clean
# result above would be a statement about the empty set.
# (The standalone `g1_checked >= 4` anti-vacuity row that used to sit here is DELETED. It was
# unreachable-as-a-failure: the Guard 1 arm above already requires the same quantity, so this
# one could not fail unless that one had already failed — and it inflated the tally by 1, which
# the assertion-count floor then counted as coverage. The vacuity property it named is now
# carried by the flush `G1_EXPECTED_REFERENCES` pin on that same arm, which is strictly
# stronger because it also catches the count going UP.)

# --- #7220 review: ASSERTION-COUNT FLOOR ---------------------------------------------------
# Nothing asserted that the assertions RAN. Measured: deleting the entire #7220 block took the
# suite 53 -> 40 passed, 0 failed, exit 0 — a silent truncation that reads exactly like a clean
# run. A floor (not equality — the count is developer-incremented) makes arm deletion loud.
GATE_MIN_ASSERTIONS=134
# Adjudicated DIRECTLY, not through fail(). Measured: `fail() { return 0; }` made this suite
# report `94 passed, 0 failed` / `OK` / exit 0 WITH a genuinely broken assertion present — and
# the floor built to make truncation loud was itself dispatched through the neutered function,
# so the one-line mutation that disarms every assertion also disarmed its own backstop.
#
# THE FLOOR ITSELF HAD ONE PRODUCER (#7104 PR-B review). Two one-line mutations defeated it and
# both are closed here:
#
#  (a) `pass=$((pass + 2))` inflated the counter to 260 against a floor of 130, so the floor
#      passed with half the arms deletable. Closed by reconciling the counter against the
#      independently-appended PASS log — two producers that must agree.
#  (b) `GATE_MIN_ASSERTIONS=$pass` makes the comparison a tautology at any count. Nothing at
#      RUNTIME can distinguish that from a correct literal, because by the time the comparison
#      runs both sides are just numbers. So it is checked in the SOURCE: the floor must be
#      assigned a bare integer. Reading this file is legitimate here — the suite already reads
#      the workflow and the library it grades, and this is the one assertion whose subject is
#      its own text.
#  (c) BOTH PRODUCERS IN (a) WERE THE SAME FUNCTION. The counter and the PASS log were written
#      by the same one-line `pass()`, so the "two producers that must agree" were one, and
#      `printf 'PASS\nPASS\n' … pass=$((pass + 2))` moved them together: 264 passed, 0 failed,
#      OK, rc=0, with 66 real assertions deletable. The third producer below is this suite's own
#      captured STDOUT, written by the redirection at the top of the file rather than by
#      `pass()`, so no edit to `pass()` can inflate it silently.
close_stdout_capture
emitted_passes=$(grep -c '^PASS$' "$PASSLOG" 2>/dev/null || true)
# `|| true`, NOT `|| echo 0` (caught by scripts/lint-shell-capture-exit): `grep -c` PRINTS `0`
# and THEN exits 1 on no match, so `|| echo 0` appends a SECOND line and the variable becomes
# "0\n0" — which every numeric comparison below then mis-evaluates. `|| true` keeps the zero the
# command already printed.
stdout_passes=$(grep -c '^  PASS: ' "$STDOUT_LOG" 2>/dev/null || true)
if [[ "$emitted_passes" -ne "$pass" ]]; then
  echo "  FAIL: assertion-count reconciliation: the counter says $pass but $emitted_passes PASS lines were emitted. The two producers disagree, so the tally is not a count of assertions and the floor below is meaningless." >&2
  echo "---"
  echo "infra-config-gate.test.sh: $pass passed, $fail failed (TALLY DESYNCHRONISED)"
  exit 1
fi
if [[ "$stdout_passes" -ne "$pass" ]]; then
  echo "  FAIL: assertion-count reconciliation (stdout): the counter says $pass but $stdout_passes '  PASS: ' lines were actually PRINTED. The counter is not measuring emitted assertions — this is the D2 shape, where inflating the tally hides deleted arms behind a satisfied floor." >&2
  echo "---"
  echo "infra-config-gate.test.sh: $pass passed, $fail failed (STDOUT DESYNCHRONISED)"
  exit 1
fi
# The one mutation that CAN keep all three in sync is printing each assertion twice. It is not
# free: it doubles the output a human reads, and identical adjacent messages are what that looks
# like. Adjacent rather than global — two arms may legitimately share wording, but an assertion
# never legitimately reports the same sentence twice in a row.
dup_adjacent=$(grep '^  PASS: ' "$STDOUT_LOG" | uniq -d | head -3)
if [[ -n "$dup_adjacent" ]]; then
  echo "  FAIL: assertion-count integrity: consecutive identical PASS lines were emitted, so the tally is inflated by repetition rather than by assertions: ${dup_adjacent}" >&2
  echo "---"
  echo "infra-config-gate.test.sh: $pass passed, $fail failed (DUPLICATE ASSERTIONS)"
  exit 1
fi
if ! grep -qE '^GATE_MIN_ASSERTIONS=[0-9]+$' "${BASH_SOURCE[0]}"; then
  echo "  FAIL: the assertion-count floor is not a literal integer in the source — a floor derived from the tally it guards (GATE_MIN_ASSERTIONS=\$pass) is a tautology that can never fail." >&2
  echo "---"
  echo "infra-config-gate.test.sh: $pass passed, $fail failed (FLOOR IS NOT A LITERAL)"
  exit 1
fi
if [[ "$pass" -lt "$GATE_MIN_ASSERTIONS" ]]; then
  echo "  FAIL: assertion-count floor: only $pass assertions ran, expected >= $GATE_MIN_ASSERTIONS — arms were deleted or skipped" >&2
  echo "---"
  echo "infra-config-gate.test.sh: $pass passed, $fail failed (FLOOR BREACHED)"
  exit 1
fi

# Known-negative self-test: prove the instrument can still report a failure before trusting any
# verdict it produced. An assertion harness that has never been shown to emit a FAIL has not
# returned a pass. Runs in a subshell so it cannot perturb the real counters.
#
# MEASURED AND CORRECTED (#7104 PR-B, task 8.2's dispatch row). The previous form REDEFINED
# fail() inside the subshell, so it proved only that a function written two lines earlier
# increments a counter — it was structurally unable to observe the REAL fail() being neutered.
# Measured on a sandbox copy: `fail() { :; }` left this suite reporting `127 passed, 0 failed`,
# exit 0, with the self-test GREEN. That is the guard's-own-dispatch mutation passing through
# the one assertion whose entire purpose is to catch it.
#
# The fix is to drive the REAL fail(). The subshell keeps its side effects (the printed FAIL
# line, the counter increment) off the parent's tally, while the function under test is the one
# production uses. The assertion-count floor above is the second producer: with fail() neutered
# AND a genuine defect present, the failing arm's `pass` never fires and the floor reddens.
if ( f0="$fail"; fail "self-test (expected — this line proves fail() records)" >/dev/null; [[ "$fail" -eq $((f0 + 1)) ]] ); then
  :
else
  echo "  FAIL: harness self-test — the REAL fail() does not record a failure; every verdict above is unverifiable" >&2
  exit 1
fi

# POSITIVE CONTROL ON pass() (#7546 review). The three-producer reconciliation above catches an
# inflated tally only when the extra lines are IDENTICAL AND ADJACENT -- `dup_adjacent` is
# `grep '^  PASS: ' | uniq -d`. The comment above claims "the one mutation that CAN keep all
# three in sync is printing each assertion twice"; that is a false universal. Measured:
#
#   pass() { echo "  PASS: $1"; echo "  PASS: (b) $1"; printf 'PASS\nPASS\n' >> "$PASSLOG"; pass=$((pass + 2)); }
#
# keeps the counter, the PASS log and the captured stdout mutually consistent, produces NO
# adjacent duplicate (the second line is worded differently), and left this suite reporting
# `264 passed, 0 failed`, OK, rc=0 -- with 66 real assertions deletable underneath it.
#
# The invariant a wording change cannot dodge is a property of pass() ITSELF: one call emits
# exactly one PASS line and advances the counter by exactly one. Driven against the REAL
# helper, with PASSLOG redirected so this control cannot perturb the reconciliation above.
if ( _p0="$pass"; PASSLOG="$TMP/selftest.passlog"; : > "$PASSLOG"
     pass "self-test (expected — this line proves pass() emits exactly one assertion)" \
       > "$TMP/selftest.out" 2>&1
     _n=$(grep -c '^  PASS: ' "$TMP/selftest.out" || true)
     [[ "$pass" -eq $((_p0 + 1)) && "$_n" -eq 1 ]] ); then
  :
else
  echo "  FAIL: harness self-test — one pass() call does not emit exactly one PASS line and one increment. A helper that emits two lines per call inflates the tally past its floor while keeping every producer consistent, which is what hides deleted arms." >&2
  exit 1
fi

echo "---"
echo "infra-config-gate.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "OK"
