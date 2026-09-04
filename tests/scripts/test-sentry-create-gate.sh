#!/usr/bin/env bash
# Tests for scripts/sentry-create-gate.sh (#6589) — is every planned CREATE
# explained by a resource block the PR added?
#
# The gate's value is entirely in the DISTINCTION it draws: the normal
# add-a-monitor flow must pass SILENTLY (or the gate trains the ack-blindness it
# exists to avoid), while an unexplained create must fail. T1 vs T2 is that
# distinction; if they ever return the same verdict the gate is worthless in one
# direction or the other.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/scripts/sentry-create-gate.sh"
pass=0; fail=0
EXPECTED_TESTS=12

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

[[ -f "$GATE" ]] || { echo "ERROR: $GATE does not exist — RED phase expected this." >&2; exit 1; }

# _run <created-lines> <added-diff-lines> -> rc
_run() {
  local c a rc=0
  c=$(mktemp); a=$(mktemp)
  printf '%s' "$1" > "$c"; printf '%s' "$2" > "$a"
  bash "$GATE" "$c" "$a" >/dev/null 2>&1 || rc=$?
  rm -f "$c" "$a"
  echo "$rc"
}

# ── T1: the normal flow — adding a monitor passes SILENTLY ──────────────────
t_added_block_explains_create() {
  local rc; rc=$(_run 'sentry_cron_monitor.scheduled_new_thing
' '+resource "sentry_cron_monitor" "scheduled_new_thing" {
+  project = "soleur-web-platform"
')
  if [[ "$rc" -eq 0 ]]; then
    _report "T1 a create explained by an added resource block passes silently" ok
  else
    _report "T1 a create explained by an added resource block passes silently" fail \
      "rc=$rc — the gate fires on the normal add-a-monitor flow, which trains ack-blindness"
  fi
}

# ── T2: the hazard — an unexplained create fails ────────────────────────────
t_unexplained_create_fails() {
  local rc; rc=$(_run 'sentry_cron_monitor.deleted_in_ui_by_hand
' '+resource "sentry_cron_monitor" "some_other_monitor" {
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T2 a create with no added block FAILS (state/config divergence)" ok
  else
    _report "T2 a create with no added block FAILS" fail "rc=$rc want 1"
  fi
}

# ── T3: no creates at all ───────────────────────────────────────────────────
t_no_creates_passes() {
  local rc; rc=$(_run '' '')
  if [[ "$rc" -eq 0 ]]; then
    _report "T3 a plan with no creates passes" ok
  else
    _report "T3 a plan with no creates passes" fail "rc=$rc want 0"
  fi
}

# ── T4: a COMMENT naming the resource must not explain a create ─────────────
# The .tf files carry monitor names in comments. A bare-name grep would match
# the comment and pass vacuously while the unexplained create sailed through —
# the exact "anchor on syntax, not the bare token" trap.
t_comment_does_not_explain_create() {
  local rc; rc=$(_run 'sentry_cron_monitor.ghost
' '+# resource "sentry_cron_monitor" "ghost" was removed in #1234; see the ADR
+# ghost is intentionally absent
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T4 a COMMENT mentioning the resource does not explain a create" ok
  else
    _report "T4 a COMMENT mentioning the resource does not explain a create" fail \
      "rc=$rc — a commented-out block satisfied the gate; the anchor is matching prose"
  fi
}

# ── T5: a CONTEXT line (unchanged, no '+') must not explain a create ────────
# A diff hunk carries unchanged context lines. Only an ADDED line means "this PR
# added it"; matching context would let a pre-existing block explain a create
# that the PR did not introduce.
t_context_line_does_not_explain_create() {
  local rc; rc=$(_run 'sentry_cron_monitor.preexisting
' ' resource "sentry_cron_monitor" "preexisting" {
   project = "soleur-web-platform"
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T5 an unchanged CONTEXT line does not explain a create (needs '+')" ok
  else
    _report "T5 an unchanged CONTEXT line does not explain a create" fail \
      "rc=$rc — a context line satisfied the gate; the '+' anchor is not enforced"
  fi
}

# ── T6: partial match — some explained, some not ────────────────────────────
t_partial_match_fails() {
  local rc; rc=$(_run 'sentry_cron_monitor.explained
sentry_cron_monitor.unexplained
' '+resource "sentry_cron_monitor" "explained" {
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T6 one unexplained create among explained ones still FAILs" ok
  else
    _report "T6 one unexplained create among explained ones still FAILs" fail "rc=$rc want 1"
  fi
}

# ── T7: name-prefix collisions must not cross-explain ───────────────────────
# `foo` must not be explained by an added block for `foo_bar`. Without a closing
# quote in the anchor, the regex would match the longer name's prefix.
t_prefix_does_not_cross_explain() {
  local rc; rc=$(_run 'sentry_cron_monitor.foo
' '+resource "sentry_cron_monitor" "foo_bar" {
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T7 an added block for foo_bar does NOT explain a create of foo" ok
  else
    _report "T7 an added block for foo_bar does NOT explain a create of foo" fail \
      "rc=$rc — prefix collision: the anchor is missing its closing quote"
  fi
}

# ── T8: type must match too ─────────────────────────────────────────────────
t_type_must_match() {
  local rc; rc=$(_run 'sentry_uptime_monitor.thing
' '+resource "sentry_cron_monitor" "thing" {
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T8 a same-NAME block of a different TYPE does not explain a create" ok
  else
    _report "T8 a same-NAME block of a different TYPE does not explain a create" fail "rc=$rc want 1"
  fi
}

# ── T9: non-vacuity — T1 and T2 must DIFFER ─────────────────────────────────
t_gate_discriminates() {
  local explained unexplained
  explained=$(_run 'sentry_cron_monitor.x
' '+resource "sentry_cron_monitor" "x" {
')
  unexplained=$(_run 'sentry_cron_monitor.x
' '+resource "sentry_cron_monitor" "y" {
')
  if [[ "$explained" -eq 0 && "$unexplained" -eq 1 ]]; then
    _report "T9 explained and unexplained creates get DIFFERENT verdicts (non-vacuity)" ok
  else
    _report "T9 explained and unexplained creates get DIFFERENT verdicts" fail \
      "explained=$explained (want 0) unexplained=$unexplained (want 1) — the gate is stuck in one direction"
  fi
}

# ── T10-T12 (#7650 Phase 2): sentry_alert, the type this gate now also sees ──
# Until Phase 2 the gate's every fixture was a monitor. `sentry_alert` is the
# type the adoption introduces, and it is the one whose unexplained create is
# most expensive: 27 of them are live paging rules, one is the GDPR Art. 33
# breach alert, and a duplicate does not fail loudly — it pages twice and bills
# twice. A guard whose matrix never names the type it was extended for is
# asserting coverage it does not have.
t_sentry_alert_added_block_explains_create() {
  local rc; rc=$(_run 'sentry_alert.byok_art_33_breach
' '+resource "sentry_alert" "byok_art_33_breach" {
+  name = "byok-art-33-breach"
')
  if [[ "$rc" -eq 0 ]]; then
    _report "T10 a sentry_alert create explained by an added block passes silently" ok
  else
    _report "T10 a sentry_alert create explained by an added block passes silently" fail \
      "rc=$rc — the gate fires on the normal add-an-alert flow"
  fi
}

# The case a dropped `import{}` produces in any PR that did not also add the
# block: Terraform sees config with nothing in state behind it and plans a CREATE
# of a rule that already exists live.
t_sentry_alert_unexplained_create_fails() {
  local rc; rc=$(_run 'sentry_alert.byok_cap_exceeded
' '+  frequency_minutes = 60
+# byok_cap_exceeded is unchanged here
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T11 a sentry_alert create with no added block FAILS (the dropped-import{} shape)" ok
  else
    _report "T11 a sentry_alert create with no added block FAILS" fail "rc=$rc want 1"
  fi
}

# Cross-type collision. The 27 adopted rules keep the resource NAME they had as
# `sentry_issue_alert`, so for every one of them there is a same-named block of
# the other type in this file's history — and, for the two survivors, in its
# present. An added `sentry_issue_alert "x"` must never explain a create of
# `sentry_alert.x`: that is precisely a half-done migration, and waving it
# through is how the same live rule ends up managed at two addresses.
t_sentry_alert_not_explained_by_issue_alert_block() {
  local rc; rc=$(_run 'sentry_alert.auth_per_user_loop
' '+resource "sentry_issue_alert" "auth_per_user_loop" {
+  name = "auth-per-user-loop"
')
  if [[ "$rc" -eq 1 ]]; then
    _report "T12 an added sentry_issue_alert block does NOT explain a sentry_alert create" ok
  else
    _report "T12 an added sentry_issue_alert block does NOT explain a sentry_alert create" fail \
      "rc=$rc — a same-named block of the OTHER type satisfied the gate; that is a half-done migration passing as explained"
  fi
}

t_added_block_explains_create
t_unexplained_create_fails
t_no_creates_passes
t_comment_does_not_explain_create
t_context_line_does_not_explain_create
t_partial_match_fails
t_prefix_does_not_cross_explain
t_type_must_match
t_gate_discriminates
t_sentry_alert_added_block_explains_create
t_sentry_alert_unexplained_create_fails
t_sentry_alert_not_explained_by_issue_alert_block

echo "=== $pass passed, $fail failed ==="
# HARNESS FLOOR (#7650 review). A commented-out dispatch line reads green
# forever without this: the suite reports `0 failed` and exits 0 having
# silently stopped running assertions. The three suites added by #7650 Phase 2
# carry the same floor; these three were EXTENDED by it and deserve it too,
# because the rows added here are the ones carrying Guard C.
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
