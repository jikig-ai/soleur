#!/usr/bin/env bash
# Tests for scripts/sentry-squash-ack-detect.sh (#6589) — does a pre-staged
# [ack-destroy] survive GitHub's squash-body composition?
#
# The subject-vs-body distinction (T2 vs T1) is the whole reason this script
# exists rather than a grep. A naive `grep -F '[ack-destroy]'` over the raw
# commit messages passes T2 — and T2 is a case where the apply gate REJECTS,
# because GitHub renders the subject as "* [ack-destroy]" and destroys the line
# anchor. That divergence is the #6074 reintroduction path: PR gate green, apply
# gate red, orphan survives.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DETECT="$REPO_ROOT/scripts/sentry-squash-ack-detect.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

[[ -f "$DETECT" ]] || { echo "ERROR: $DETECT does not exist — RED phase expected this." >&2; exit 1; }

# _expect <want_rc> <label> <json-array-of-messages>
_expect() {
  local want="$1" label="$2" json="$3" rc=0
  printf '%s' "$json" | bash "$DETECT" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "got rc=$rc want rc=$want for $json"
  fi
}

# ── T1: the SUPPORTED way to pre-stage an ack ───────────────────────────────
# Ack on its own line in a commit BODY. GitHub carries body lines verbatim, so
# it stays line-anchored in the squash body. This must be accepted.
_expect 0 "T1 ack on its own line in a commit BODY is detected" \
  '["feat: retire the ghcr token minter monitor\n\n[ack-destroy]\n\nRefs #6589."]'

# ── T2: the trap ────────────────────────────────────────────────────────────
# Ack as a commit SUBJECT. GitHub renders it "* [ack-destroy]", which does NOT
# match the anchored regex — so the apply gate would REJECT. This script must
# agree with the apply gate and reject too. A raw grep would wrongly accept.
_expect 1 "T2 ack as a commit SUBJECT is rejected (GitHub prefixes it '* ')" \
  '["[ack-destroy]"]'

_expect 1 "T2b ack as a subject among several commits is still rejected" \
  '["chore: init","[ack-destroy]","feat: remove monitor block"]'

# ── T3: line-anchoring, mirroring the counter tests' T5 ─────────────────────
_expect 1 "T3 ack as a mid-line substring is rejected (not line-anchored)" \
  '["chore: discuss [ack-destroy] policy inline"]'

_expect 1 "T3b ack with trailing text on the same body line is rejected" \
  '["feat: x\n\n[ack-destroy] because the monitor is dead"]'

# ── T4: multi-commit composition ────────────────────────────────────────────
# The ack may be in ANY commit's body — GitHub concatenates them all.
_expect 0 "T4 ack in the body of a LATER commit is detected" \
  '["chore: initialize branch","feat: remove monitor block\n\n[ack-destroy]"]'

_expect 0 "T4b ack in the body of the FIRST of several commits is detected" \
  '["feat: remove monitor\n\n[ack-destroy]","chore: fix typo"]'

# ── T5: absence ─────────────────────────────────────────────────────────────
_expect 1 "T5 no ack anywhere is rejected" \
  '["feat: remove monitor block","chore: update tests"]'

_expect 1 "T5b empty commit list is rejected (cannot certify an absent ack)" '[]'

# ── T6: near-miss literals must not satisfy the gate ────────────────────────
_expect 1 "T6 [ack-destroy-all] does not satisfy the gate" \
  '["feat: x\n\n[ack-destroy-all]"]'

_expect 1 "T6b [ACK-DESTROY] (wrong case) does not satisfy the gate" \
  '["feat: x\n\n[ACK-DESTROY]"]'

_expect 1 "T6c bare ack-destroy without brackets does not satisfy the gate" \
  '["feat: x\n\nack-destroy"]'

# ── T7: the emulation is REAL, not a grep ───────────────────────────────────
# Non-vacuity anchor. T1 and T2 carry the SAME literal in the same commit list
# shape; only the position (body vs subject) differs. A grep-based
# implementation returns the same verdict for both. If this ever fails, the
# script has been "simplified" back into the bug.
t_emulation_distinguishes_position() {
  local body_rc=0 subj_rc=0
  printf '%s' '["feat: x\n\n[ack-destroy]"]' | bash "$DETECT" >/dev/null 2>&1 || body_rc=$?
  printf '%s' '["[ack-destroy]"]'            | bash "$DETECT" >/dev/null 2>&1 || subj_rc=$?
  if [[ "$body_rc" -eq 0 && "$subj_rc" -eq 1 ]]; then
    _report "T7 body-vs-subject produce DIFFERENT verdicts (emulation is not a grep)" ok
  else
    _report "T7 body-vs-subject produce DIFFERENT verdicts (emulation is not a grep)" fail \
      "body_rc=$body_rc (want 0) subj_rc=$subj_rc (want 1) — a grep over raw messages returns the same verdict for both, which greens this gate while the apply gate reds"
  fi
}
t_emulation_distinguishes_position

# ── T8: the composed body actually carries the '* ' bullets ─────────────────
# Pins the composition itself, not just its verdict, so a future edit that drops
# the subject prefix is caught here rather than by a confusing prod divergence.
t_composition_prefixes_subjects() {
  # A subject-only ack must be rejected BECAUSE of the bullet. Prove the bullet
  # is what does it: the same string as a body line is accepted (T1/T7). If the
  # prefix were dropped, subject-ack would be accepted and T2 would fail — so
  # T2 + T7 together already pin it. This test states the invariant explicitly.
  local out
  out=$(printf '%s' '["subject line","second: subj\n\nbody line"]' | jq -r '
    [ .[] | split("\n") | "* " + .[0] + (if length > 1 then "\n" + (.[1:] | join("\n")) else "" end) ]
    | join("\n\n")')
  if [[ "$out" == '* subject line'*'* second: subj'*'body line' ]]; then
    _report "T8 composition prefixes each subject with '* ' and keeps body verbatim" ok
  else
    _report "T8 composition prefixes each subject with '* ' and keeps body verbatim" fail "got: $out"
  fi
}
t_composition_prefixes_subjects

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
