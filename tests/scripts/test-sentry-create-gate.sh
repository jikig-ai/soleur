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

t_added_block_explains_create
t_unexplained_create_fails
t_no_creates_passes
t_comment_does_not_explain_create
t_context_line_does_not_explain_create
t_partial_match_fails
t_prefix_does_not_cross_explain
t_type_must_match
t_gate_discriminates

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
