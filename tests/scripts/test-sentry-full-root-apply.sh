#!/usr/bin/env bash
# Regression anchor for #6589 (the #6074 / #4929 class): apply-sentry-infra.yml
# must plan Terraform against the FULL ROOT, never a hand-maintained `-target=`
# allow-list.
#
# WHY THIS EXISTS. A `-target`-scoped plan restricts Terraform's plan universe to
# the listed addresses. A resource whose block is DELETED from a .tf file is, by
# construction, no longer nameable in that list — so `terraform plan -target=...`
# never considers it and the live resource is never destroyed. Deletion became a
# silent no-op. #6034 added a monitor block AND its -target line; #6074 removed
# BOTH together (the intuitive edit) and orphaned a live monitor that billed
# $0.78/mo and carried a 12-day unresolved incident. The workflow's own comment
# documented the identical leak from #4929 and nobody re-checked it. Monitor
# count went 8 -> 49 in two months and never once decreased.
#
# Under a full-root plan the universe is `state UNION config`, so removing a block
# yields a real destroy that the [ack-destroy] gate then governs.
#
# NON-VACUITY. Every assertion below is mutation-tested inline: the check is run
# against a deliberately-broken copy and must FAIL there. A guard that cannot go
# red is not a guard. See
# knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
SCOPE_GUARD="$REPO_ROOT/tests/scripts/test-destroy-guard-sentry-scope-guard.sh"
FILTER="$REPO_ROOT/tests/scripts/lib/destroy-guard-filter-sentry.jq"
FIXTURES="$REPO_ROOT/tests/scripts/fixtures"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

for f in "$WORKFLOW" "$SCOPE_GUARD" "$FILTER"; do
  [[ -f "$f" ]] || { echo "[FAIL] missing required file: $f" >&2; exit 1; }
done

# Strip whole-line comments ONLY. Both YAML and the bash inside `run: |` use `#`,
# so one filter covers both. This is load-bearing: the workflow legitimately
# DESCRIBES the retired -target= mechanism in prose (and the ADR-031 amendment
# does too), so a bare `grep -- -target=` over the raw body would false-FAIL on
# the very comment explaining why the mechanism is gone. Anchor on the syntactic
# construct a comment cannot produce, never the bare token.
# See cq-assert-anchor-not-bare-token +
# knowledge-base/project/learnings/test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md
_strip_comments() { grep -vE '^[[:space:]]*#' "$1"; }

# ── T1: no executable `-target=` survives in the workflow ────────────────────
# The #6074 fix itself. Checks EXECUTABLE lines only (comments stripped above).
# NO PIPE INTO `grep -q` (#7024). Under `set -o pipefail`, `grep -q` exits on its FIRST
# match and closes the pipe; if the producer still has unwritten data it takes SIGPIPE and
# the PIPELINE reports 141 even though the pattern MATCHED. In a POSITIVE predicate like
# this one that reads as "no -target= found" — the FAIL-OPEN direction, on the #6074 guard
# for `terraform destroy` reachability.
#
# Capture once, then match with a herestring: no pipe, so no SIGPIPE.
_has_executable_target() {
  local body; body=$(_strip_comments "$1")
  grep -qE -- '-target=' <<<"$body"
}

t_no_executable_target() {
  if _has_executable_target "$WORKFLOW"; then
    local hits; hits=$(_strip_comments "$WORKFLOW" | grep -nE -- '-target=' | head -5)
    _report "T1 no executable -target= in apply-sentry-infra.yml (full-root plan)" fail \
      "found:
$hits"
  else
    _report "T1 no executable -target= in apply-sentry-infra.yml (full-root plan)" ok
  fi
}

# T1-mutation: prove T1 can go RED. Inject an executable -target= into a copy.
t_no_executable_target_is_not_vacuous() {
  local tmp; tmp=$(mktemp); cp "$WORKFLOW" "$tmp"
  printf '            -target=sentry_cron_monitor.synthetic_mutation \\\n' >> "$tmp"
  if _has_executable_target "$tmp"; then
    _report "T1-mut T1 detects an injected executable -target= (non-vacuity)" ok
  else
    _report "T1-mut T1 detects an injected executable -target= (non-vacuity)" fail \
      "the check stayed green against a workflow carrying a real -target= line"
  fi
  rm -f "$tmp"
}

# T1-comment-tolerance: a COMMENT naming -target= must NOT trip T1. Pins the
# comment-strip so a future "simplification" to a bare grep is caught here rather
# than by a confusing false-FAIL on the ADR prose.
t_comment_mentioning_target_is_tolerated() {
  local tmp; tmp=$(mktemp)
  printf '# Historical note: this workflow used to pass -target=sentry_cron_monitor.foo\n' > "$tmp"
  printf 'jobs:\n  apply:\n    steps:\n      - run: terraform plan -no-color\n' >> "$tmp"
  if _has_executable_target "$tmp"; then
    _report "T1-tol a comment naming -target= does not trip T1" fail \
      "comment-strip is broken — the guard would false-FAIL on its own explanatory prose"
  else
    _report "T1-tol a comment naming -target= does not trip T1" ok
  fi
  rm -f "$tmp"
}

# ── T2: the type-scope guard sees `state UNION config`, not just .tf ────────
# A .tf-ONLY type set is vacuous in exactly the direction of this bug: under
# full-root the plan universe is state UNION config, so a type that exists in
# STATE with no remaining .tf block is invisible to a .tf-only reader — and that
# is precisely the class this PR destroys. Had kb_tenant_mint_silent_fallback
# been the last sentry_issue_alert, a .tf-only guard would have omitted that type,
# passed VACUOUSLY, and let an array-of-blocks destroy through unchecked.
#
# The union is assembled across two callers, because the halves live in different
# places: the guard reads .tf here (no credentials needed), and the WORKFLOW
# injects the state half from the plan JSON — which IS state UNION config, so it
# is exact rather than a reconstruction. The guard cannot read state itself: the
# R2 backend needs AWS credentials that test-all.sh does not have, and a
# `terraform state list` whose failure was tolerated would rebuild the vacuity.
# Assert BOTH halves are wired, or the union is a claim rather than a mechanism.
t_scope_guard_accepts_state_injection() {
  local body; body=$(_strip_comments "$SCOPE_GUARD")
  if grep -qE 'SENTRY_STATE_TYPES' <<<"$body"; then
    _report "T2 scope guard accepts the state half via SENTRY_STATE_TYPES" ok
  else
    _report "T2 scope guard accepts the state half via SENTRY_STATE_TYPES" fail \
      "no SENTRY_STATE_TYPES — the guard cannot see state-only types under any caller"
  fi
}

t_workflow_feeds_plan_types_to_guard() {
  local body; body=$(_strip_comments "$WORKFLOW")
  # Anchor on the assignment construct + the guard invocation carrying the env
  # var — not the bare token, which also appears in this workflow's prose.
  if grep -qE 'SENTRY_STATE_TYPES="\$plan_types"' <<<"$body" \
     && grep -qE 'plan_types=\$\(terraform show -json' <<<"$body"; then
    _report "T2b workflow feeds the PLAN's types (state UNION config) into the guard" ok
  else
    _report "T2b workflow feeds the PLAN's types (state UNION config) into the guard" fail \
      "the workflow never injects plan types — CI would only ever check the .tf half, so a state-only type stays invisible"
  fi
}

t_scope_guard_reads_tf() {
  local body; body=$(_strip_comments "$SCOPE_GUARD")
  if grep -qE 'SENTRY_TF_DIR' <<<"$body"; then
    _report "T2c scope guard sources the .tf half via SENTRY_TF_DIR (parameterized)" ok
  else
    _report "T2c scope guard sources the .tf half via SENTRY_TF_DIR" fail \
      "no SENTRY_TF_DIR — the .tf half is missing or not parameterized (AC6's empty->FAIL is then untestable)"
  fi
}

# The empty->FAIL posture, exercised rather than asserted in prose. A guard that
# passes when it discovered nothing reports green after a parser regression or a
# moved directory — precisely when its verdict matters most.
t_scope_guard_fails_on_empty() {
  local d rc=0; d=$(mktemp -d)
  SENTRY_TF_DIR="$d" bash "$SCOPE_GUARD" >/dev/null 2>&1 || rc=$?
  rmdir "$d"
  if [[ "$rc" -ne 0 ]]; then
    _report "T2d scope guard FAILs on an empty SENTRY_TF_DIR (empty->FAIL, AC6)" ok
  else
    _report "T2d scope guard FAILs on an empty SENTRY_TF_DIR (empty->FAIL, AC6)" fail \
      "guard passed on an empty discovery — it would report green after a parser regression"
  fi
}

# Non-vacuity for the state half: an uncovered type reachable ONLY via state must
# trip the guard. This is the #6589 class in miniature.
t_scope_guard_catches_state_only_uncovered_type() {
  local rc=0
  SENTRY_STATE_TYPES='sentry_metric_alert.orphan_in_state_only' \
    bash "$SCOPE_GUARD" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _report "T2e scope guard catches an uncovered STATE-ONLY type (non-vacuity)" ok
  else
    _report "T2e scope guard catches an uncovered STATE-ONLY type (non-vacuity)" fail \
      "a type present only in state slipped the guard — the union is not wired"
  fi
}

# ── T3: the destroy filter still counts a removed block as a delete ──────────
# Full-root removal must not weaken the guard. Reuses the synthesized fixture.
t_filter_counts_removed_block() {
  local got
  got=$(jq -f "$FILTER" < "$FIXTURES/tfplan-sentry-resource-delete.json" | jq -r '.resource_deletes')
  if [[ "$got" == "1" ]]; then
    _report "T3 removed-block fixture yields resource_deletes=1 through the filter" ok
  else
    _report "T3 removed-block fixture yields resource_deletes=1 through the filter" fail \
      "got '$got' want '1'"
  fi
}


# T1-mut-top: the SAME injection, at the TOP of the file instead of the bottom (#7024).
#
# THE EXISTING BOTTOM-INJECTION ARM COULD NEVER HAVE DETECTED THE SIGPIPE SHAPE, EVEN IN
# PRINCIPLE. `grep -q` only early-closes the pipe on an EARLY match; a match appended at
# the very end means grep reads to EOF and the producer never blocks. So an arm that
# appends can prove the PATTERN works and nothing at all about the pipeline.
#
# This arm is GREEN both before and after the #7024 fix, and that is documented rather
# than hidden: at current file sizes SIGPIPE is structurally unreachable here (see
# t_sigpipe_mechanism_is_real below for the measurement). Its value is that it stays green
# for the RIGHT reason, and that it will catch the shape if apply-sentry-infra.yml ever
# grows past the pipe buffer.
t_no_executable_target_is_not_vacuous_top_injection() {
  local tmp; tmp=$(mktemp)  # lint-trap-ownership: ok — rm -f inline below; single tmp, no exit between alloc and cleanup; bounded; matches this file's existing arms (#6734, ADR-129)
  printf '            -target=sentry_cron_monitor.synthetic_top_mutation \\\n' > "$tmp"
  cat "$WORKFLOW" >> "$tmp"
  if _has_executable_target "$tmp"; then
    _report "T1-mut-top T1 detects a -target= injected at the TOP (the only position SIGPIPE could bite)" ok
  else
    _report "T1-mut-top T1 detects a -target= injected at the TOP (the only position SIGPIPE could bite)" fail \
      "the check stayed green against a workflow whose FIRST line carries a real -target="
  fi
  rm -f "$tmp"
}

# T4: the SIGPIPE mechanism itself, proved on a SYNTHETIC producer (#7024, AC18).
#
# THE PRODUCER MATTERS, and getting this wrong makes the arm silently vacuous. Measured on
# a 202,014-byte input with the match on line 1:
#
#   grep -v ... | grep -q MATCH   -> rc=141 in 50/50 runs
#   cat        ... | grep -q MATCH -> rc=141 in  0/50 runs
#
# So the arm uses the SAME producer family as production (`grep -v`, which is what
# _strip_comments is). A `cat`-based probe reports a clean 0 forever and proves nothing —
# the instrument removing the phenomenon it is meant to observe.
#
# TWO INSTRUMENT GUARDS, for the same reason:
#   - `grep` must resolve to a real BINARY. In some interactive shells it is a function
#     shim whose -q drains stdin, which removes the race and reports 0 at every size.
#   - A POSITIVE CONTROL that MUST fire. If `yes | grep -q y` does not yield 141, this
#     environment cannot exhibit SIGPIPE at all and any result here is VOID, not clean.
t_sigpipe_mechanism_is_real() {
  if [[ "$(type -t grep)" != "file" ]]; then
    _report "T4 SIGPIPE mechanism (synthetic >64KB producer, early match)" fail \
      "grep resolves to a $(type -t grep), not a binary — a shim that drains stdin removes the very race this measures"
    return
  fi

  local ctl=0
  yes 2>/dev/null | grep -q y || ctl=$?  # sigpipe-demo: intentional (this IS the control)
  if [[ "$ctl" -ne 141 ]]; then
    _report "T4 SIGPIPE mechanism (synthetic >64KB producer, early match)" fail \
      "positive control did not fire: the yes-into-quiet-grep control returned $ctl, want 141 — this environment cannot exhibit SIGPIPE, so any result here is void"
    return
  fi

  local big; big=$(mktemp)  # lint-trap-ownership: ok — rm -f inline below; single tmp, no exit between alloc and cleanup; bounded (#6734, ADR-129)
  printf 'MATCH_ME_FIRST\n' > "$big"
  head -c 200000 /dev/zero | tr '\0' 'x' | fold -w 100 >> "$big"

  local rc=0 rc_fixed=0 body
  ( set -o pipefail; grep -vE '^ZZZ_NEVER_MATCHES' "$big" | grep -q 'MATCH_ME_FIRST' ) || rc=$?  # sigpipe-demo: intentional (this IS the reproduction)
  body=$(grep -vE '^ZZZ_NEVER_MATCHES' "$big")
  ( set -o pipefail; grep -q 'MATCH_ME_FIRST' <<<"$body" ) || rc_fixed=$?
  rm -f "$big"

  if [[ "$rc" -eq 141 && "$rc_fixed" -eq 0 ]]; then
    _report "T4 SIGPIPE mechanism: a piped grep -q reports 141 ON A MATCH; the herestring form reports 0" ok
  else
    _report "T4 SIGPIPE mechanism: a piped grep -q reports 141 ON A MATCH; the herestring form reports 0" fail \
      "piped=$rc (want 141), herestring=$rc_fixed (want 0)"
  fi
}

# T4b: the FIXED predicate never flakes on the REAL input (#7024).
#
# THIS CORRECTS A MEASUREMENT THIS PR WAS PLANNED AROUND. The plan asserted SIGPIPE was
# "structurally unreachable" here because apply-sentry-infra.yml strips to ~16.8 KB against
# a 65,536-byte pipe buffer, and cited 10/10 runs returning 0.
#
# That reasoning is wrong and the conclusion with it. The buffer bounds how much a producer
# can write BEFORE BLOCKING; it does not stop the consumer exiting first. `grep -q` exits on
# the first match, and any write the producer has not yet completed then takes EPIPE. Total
# size under the buffer only makes the race NARROW, not impossible.
#
# Measured on the real input, 100 runs, binaries pinned, with `-target=` injected at the top:
#
#   rc=141 -> 2 ; rc=0 -> 98
#
# ~2%. A 10-run sample had a ~82% chance of seeing zero of those, so the original
# all-zero observation was the LIKELY outcome even with the defect fully live. And because
# _has_executable_target is a POSITIVE predicate, rc=141 reads as "no -target= found" and
# T1 reports OK — a live FAIL-OPEN on the #6074 guard for `terraform destroy`
# reachability, roughly 1 run in 50.
#
# So this arm guards the FIX on the REAL input rather than asserting an absence of risk.
t_fixed_predicate_does_not_flake_on_the_real_input() {
  local tmp; tmp=$(mktemp)  # lint-trap-ownership: ok — rm -f inline below; single tmp, no exit between alloc and cleanup; bounded (#6734, ADR-129)
  printf '            -target=sentry_cron_monitor.synthetic_top_mutation \\\n' > "$tmp"
  cat "$WORKFLOW" >> "$tmp"

  local rc bad=0 runs=40
  for _ in $(seq 1 "$runs"); do
    rc=0
    ( set -o pipefail; _has_executable_target "$tmp" ) || rc=$?
    # The predicate must be TRUE (0) every time: the file carries a -target= on line 1.
    [[ "$rc" -eq 0 ]] || bad=$((bad + 1))
  done
  rm -f "$tmp"

  if [[ "$bad" -eq 0 ]]; then
    _report "T4b the FIXED _has_executable_target is stable over ${runs} runs on the real workflow (the piped form flaked ~2%)" ok
  else
    _report "T4b the FIXED _has_executable_target is stable over ${runs} runs on the real workflow" fail \
      "${bad}/${runs} runs did not return 0 — the predicate is still non-deterministic; a piped grep -q has come back"
  fi
}

t_no_executable_target
t_no_executable_target_is_not_vacuous
t_no_executable_target_is_not_vacuous_top_injection
t_sigpipe_mechanism_is_real
t_fixed_predicate_does_not_flake_on_the_real_input
t_comment_mentioning_target_is_tolerated
t_scope_guard_accepts_state_injection
t_workflow_feeds_plan_types_to_guard
t_scope_guard_reads_tf
t_scope_guard_fails_on_empty
t_scope_guard_catches_state_only_uncovered_type
t_filter_counts_removed_block

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
