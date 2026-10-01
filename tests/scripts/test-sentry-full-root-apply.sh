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
# Override exists for mutation testing only: point it at a mutated COPY, never edit the
# tracked workflow in place to prove a guard can go red.
WORKFLOW="${SENTRY_APPLY_WORKFLOW_OVERRIDE:-$REPO_ROOT/.github/workflows/apply-sentry-infra.yml}"
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

# T13 (#7650 review) — INHERITED ERREXIT around a status-bearing command.
#
# THE CLASS, not the instance. Actions invokes a bare `run:` as `bash -e {0}`, so
# errexit is INHERITED and a `set -uo pipefail` line cannot clear it. Any command
# whose NON-ZERO exit is a normal answer — `grep -q` (1 = no match), `diff` (1 =
# they differ) — therefore kills the step on its ordinary path unless the block
# brackets it with `set +e` or consumes the status in a condition.
#
# This workflow's header documents the trap twice, and a step added in #7650
# Phase 2 walked into it anyway: the forensics sweep ran `grep -qE "$sentinel"`
# followed by `rc=$?`, so on every CLEAN run (no secret, grep returns 1) the step
# died at that line, silently, before any annotation — skipping the two
# post-apply probes that assert `byok-art-33-breach` is live, and filing a p1
# that told the operator to "assume a partial write" after a perfectly clean
# apply. Measured rc=1 by emulating `bash -e` on the extracted block.
#
# So the assertion is structural and general: in every `run:` block of this
# workflow, a bare `grep -q…` / `diff` line IMMEDIATELY followed by `rc=$?` must
# sit inside a `set +e` region. Consuming the status in an `if`/`&&`/`||` is the
# other correct shape and is not flagged, because there the status is handled.
t_no_unbracketed_status_capture() {
  local findings
  findings=$(python3 - "$WORKFLOW" <<'PYEOF'
import re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
bad = []
for jname, job in (doc.get("jobs") or {}).items():
    for step in (job.get("steps") or []):
        run = step.get("run")
        if not run:
            continue
        # Join backslash-continued lines FIRST. Without this the scan is
        # line-oriented and a multi-line `VAR=$( ... \\\n ... )` never matches
        # the SHAPE 2 regex, which needs the closing paren on the same line.
        # Measured on #7866: stripping the rescue from the two-line `declared=$(`
        # assignment — the one whose death kills the whole derivation — survived
        # this rule while the four single-line siblings were all caught.
        joined, buf = [], ""
        for _raw in run.split("\n"):
            buf += _raw
            if buf.rstrip().endswith("\\"):
                buf = buf.rstrip()[:-1] + " "
                continue
            joined.append(buf); buf = ""
        if buf:
            joined.append(buf)
        lines = joined
        errexit = True          # inherited from `bash -e {0}`
        for i, raw in enumerate(lines):
            ln = raw.strip()
            if re.match(r"^set\s+\+e\b", ln) or re.match(r"^set\s+[-a-z]*\+[a-z]*e\b", ln):
                errexit = False
            elif re.match(r"^set\s+-[a-z]*e\b", ln):
                errexit = True
            if not errexit:
                continue
            # SHAPE 1 — a bare status-bearing command whose exit is then captured.
            if re.match(r"^(grep|diff|cmp)\b", ln) and not re.search(r"(\|\||&&|;|\bif\b|\bwhile\b|\buntil\b)", ln):
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
                if re.match(r"^\w+=\$\?", nxt):
                    bad.append(f"{jname} :: {step.get('name','(unnamed)')} :: {ln[:60]}")
            # SHAPE 2 — `VAR=$(... status-bearing ...)`. Same death, different
            # spelling: the assignment INHERITS the substitution's status (and
            # `pipefail` promotes it out of a pipeline), so errexit kills the step
            # at the assignment. Until #7866 this rule matched only SHAPE 1, so it
            # was blind to all four such lines in the AC17 step — including the
            # two its own PR added — and each died silently on its normal path.
            # A guard whose window is narrower than the class it names reports
            # clean on the instances it cannot see.
            m = re.match(r"^\w+=\$\((.*)\)\s*(;.*)?$", ln)
            if m:
                inner = m.group(1)
                if re.search(r"(^|\||\(|\s)(grep|diff|cmp)\b", inner) and not re.search(r"\|\|\s*(true|:)", inner):
                    bad.append(f"{jname} :: {step.get('name','(unnamed)')} :: {ln[:60]}")
            # SHAPE 3 — the same command hidden behind a one-line helper
            # (`_f() { grep ...; }`). This is not hypothetical: the #7866 fix
            # first routed all four counts through a `_lines()` helper, and the
            # SHAPE 2 rule above went GREEN with the rescue stripped, because the
            # `grep` was no longer inside an assignment it inspects. The guard
            # reported clean because it could not SEE the command, not because
            # the command was safe. Rescues belong inline at the call site.
            if re.match(r"^\w+\s*\(\)\s*\{", ln) and re.search(r"\b(grep|diff|cmp)\b", ln) \
               and not re.search(r"\|\|\s*(true|:)", ln):
                bad.append(f"{jname} :: {step.get('name','(unnamed)')} :: helper hides a status-bearing command :: {ln[:50]}")
for b in bad:
    print(b)
PYEOF
)
  if [[ -z "$findings" ]]; then
    _report "T13 no run: block captures a status-bearing command's exit while errexit is in force" ok
  else
    _report "T13 no unbracketed status capture under inherited errexit" fail \
      "these die on their NORMAL path (grep -q returns 1 on no-match) before any annotation:
$findings"
  fi
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
    # NOT A FAILURE — and the direction here is deliberate.
    #
    # T4 DEMONSTRATES a mechanism; it does not guard this repo's code. The guard on the
    # actual fix is T4b, which runs unconditionally below. When the positive control does
    # not fire, this environment cannot exhibit SIGPIPE at all, so a T4 result would be
    # VOID — and reporting a void result as a failure reddens a healthy tree.
    #
    # Measured: GitHub Actions' `test-scripts` container returns ctl=1 here (the control
    # pipeline produces no match), where a developer laptop returns 141. Failing closed on
    # that turned CI red on the very PR that introduced this arm.
    #
    # Reported as a pass with an explicit NOT-EXERCISED label rather than skipped silently:
    # a reader scanning output must be able to see that the demonstration did not run.
    _report "T4 SIGPIPE mechanism — NOT EXERCISED here (positive control returned $ctl, not 141; this environment cannot exhibit SIGPIPE). T4b below is the binding guard." ok
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
# T14 (#8050) — THE APPLY JOB'S FIDELITY WIRING, which no other suite reads.
# The post-apply probe must (a) read a reference the plan step projected from
# THE PLAN BEING APPLIED (never the committed copy), (b) pin fixture mode off,
# (c) run only when the plan step succeeded (and still after a failed apply /
# red AC17), and the reference gate must have exactly ONE call site — in
# `plan_pr`, never in `apply`. A dropped env line would silently revert the
# probe to the committed copy with every other check green.
t_apply_job_fidelity_wiring() {
  local out rc=0
  out=$(python3 - "$WORKFLOW" <<'PYEOF' 2>&1) || rc=$?
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
jobs = d["jobs"]
apply = jobs["apply"]["steps"]; plan_pr = jobs["plan_pr"]["steps"]
bad = []
fid = [s for s in apply if s.get("id") == "fidelity"]
if len(fid) != 1: sys.exit(f"expected one apply step id=fidelity, found {len(fid)}")
env = fid[0].get("env") or {}
if env.get("SENTRY_REFERENCE_FILE") != "${{ runner.temp }}/sentry-alert-reference.json":
    bad.append(f"fidelity SENTRY_REFERENCE_FILE={env.get('SENTRY_REFERENCE_FILE')!r} (want the runner.temp projection)")
if env.get("SENTRY_FIXTURE_RULES", None) != "":
    bad.append(f"fidelity SENTRY_FIXTURE_RULES={env.get('SENTRY_FIXTURE_RULES')!r} (want pinned empty)")
if " ".join((fid[0].get("if") or "").split()) != "always() && steps.plan.outcome == 'success'":
    bad.append(f"fidelity if={fid[0].get('if')!r}")
plan = [s for s in apply if s.get("id") == "plan"]
if len(plan) != 1: sys.exit("expected one apply step id=plan")
run = plan[0]["run"]
proj = [l for l in run.splitlines() if l.lstrip().startswith("jq -S --arg side tf -f") and "/tmp/sentry-apply-plan.json" in l and '"${RUNNER_TEMP}/sentry-alert-reference.json"' in l]
if len(proj) != 1: bad.append(f"plan step projection line count {len(proj)} (want 1)")
def gate_calls(steps):
    return sum(l.lstrip().startswith('bash "${GITHUB_WORKSPACE}/scripts/sentry-alert-reference-gate.sh"') for s in steps for l in (s.get("run") or "").splitlines())
if gate_calls(plan_pr) != 1: bad.append(f"plan_pr gate calls={gate_calls(plan_pr)} (want 1)")
if gate_calls(apply) != 0: bad.append(f"apply gate calls={gate_calls(apply)} (want 0 — the apply job projects its own reference)")
if bad: sys.exit("; ".join(bad))
PYEOF
  if [[ "$rc" -eq 0 ]]; then
    _report "T14 apply job: probe reads the plan-step projection with fixture mode pinned off, runs iff the plan step succeeded; the reference gate has exactly one call site (plan_pr)" ok
  else
    _report "T14 apply-job fidelity wiring" fail "$out"
  fi
}
# ── T15-T18 (#8451) — Guard 3: single-attempt 410 handler at both plan sites ──
# Sentry REMOVED the legacy alert-rule API (a persistent 410, "This API no longer
# exists"), and after #8451 no `sentry_issue_alert` resource remains, so the old
# brownout retry ladder was unreachable and was deleted. Both plan sites now run
# `terraform plan` ONCE; on a 410 the handler names the failing addresses and says
# only what was measured. Each slice runs from the anchor comment to the next line
# that is exactly `          set -e`.
#
# MUTATION MATRIX (plan §Guard 3), demonstrated against a mutated COPY via
# SENTRY_APPLY_WORKFLOW_OVERRIDE:
#   1 `exit $rc` -> `exit 0` at either site                 RED (T16, T18)
#   2 delete one anchor, or add a third                     RED (T15)
#   3 apply slice loses its `got status 410` branch         RED (T16, T18)
#   4 add while/sleep/a second `terraform plan` to a slice  RED (T16)
#   5 drop `rm -f /tmp/sentry-plan.out` from a slice        RED (T16)
#   6 the real workflow, unmodified                         PASS
G3_ANCHOR='          # sentry-plan-410-handler (#8451)'

# Writes slice files slice1, slice2, ... into dir $2; prints the anchor count.
_g3_slices() {
  awk -v anchor="$G3_ANCHOR" -v dir="$2" '
    $0 == anchor { n++; inside = 1; out = dir "/slice" n }
    inside       { print > out }
    inside && $0 == "          set -e" { inside = 0; close(out) }
    END          { print n + 0 }
  ' "$1"
}

t_g3_anchor_count() {
  local d n; d=$(mktemp -d)  # lint-trap-ownership: ok — rm -rf inline below; no exit between alloc and cleanup (#6734, ADR-129)
  n=$(_g3_slices "$WORKFLOW" "$d")
  rm -rf "$d"
  if [[ "$n" == "2" ]]; then
    _report "T15 exactly 2 sentry-plan-410-handler anchors (plan_pr + apply)" ok
  else
    _report "T15 exactly 2 sentry-plan-410-handler anchors" fail "found $n"
  fi
}

t_g3_slice_shape() {
  local d n i f body bad=""; d=$(mktemp -d)  # lint-trap-ownership: ok — rm -rf inline below; no exit between alloc and cleanup (#6734, ADR-129)
  n=$(_g3_slices "$WORKFLOW" "$d")
  for (( i = 1; i <= n; i++ )); do
    f="$d/slice$i"
    if [[ "$(tail -n 1 "$f")" != "          set -e" ]]; then bad+=" slice$i:unterminated"; continue; fi
    # Executable lines only: the comments legitimately say "terraform plan" and "retry".
    body=$(grep -vE '^[[:space:]]*#' "$f" || true)
    # Invocations only: the `::error::terraform plan failed` echoes name it too.
    [[ "$(grep -cE '^[[:space:]]*terraform plan([^[:alnum:]_]|$)' <<<"$body" || true)" == "1" ]] || bad+=" slice$i:terraform-plan-count"
    ! grep -qE '(^|[^[:alnum:]_])(while|until|sleep)([^[:alnum:]_]|$)|plan_backoff' <<<"$body" || bad+=" slice$i:loop-or-sleep"
    grep -qxE '[[:space:]]*rm -f /tmp/sentry-plan\.out' <<<"$body" || bad+=" slice$i:no-rm-f"
    grep -qE '(^|[[:space:]])exit \$rc$' <<<"$body" || bad+=" slice$i:no-exit-rc"
    grep -qF 'got status 410' <<<"$body" || bad+=" slice$i:no-410-branch"
    grep -qxE '[[:space:]]*set \+e' <<<"$body" || bad+=" slice$i:no-set+e"
    # rm -f must come BEFORE the plan, or a failed tee leaves a stale 410 for the grep.
    [[ "$(grep -nE 'rm -f /tmp/sentry-plan\.out|^[[:space:]]*terraform plan' <<<"$body" | head -n 1 || true)" == *"rm -f"* ]] || bad+=" slice$i:rm-after-plan"
  done
  rm -rf "$d"
  if [[ "$n" -ge 1 && -z "$bad" ]]; then
    _report "T16 each 410-handler slice: one terraform plan, no loop/sleep, rm -f before plan, set +e, a 410 branch, exit \$rc ($n slices)" ok
  else
    _report "T16 410-handler slice shape" fail "slices=$n;$bad"
  fi
}

t_g3_no_ladder_residue() {
  local hits
  hits=$(grep -nE 'plan_backoff|brownout_only|SOLEUR_SENTRY_''BROWNOUT|retries for exactly this' "$WORKFLOW" || true)
  if [[ -z "$hits" ]]; then
    _report "T17 no brownout-ladder residue (plan_backoff / brownout_only / markers / 'retries for exactly this')" ok
  else
    _report "T17 brownout-ladder residue" fail "$hits"
  fi
}

# Executes each slice for real, under the shell Actions uses, with `terraform`
# stubbed. The fixture is synthesized in the shape of the #8451 run log.
t_g3_handler_executes() {
  local d n i f out rc bad=""; d=$(mktemp -d)  # lint-trap-ownership: ok — rm -rf inline below; no exit between alloc and cleanup (#6734, ADR-129)
  n=$(_g3_slices "$WORKFLOW" "$d")
  mkdir -p "$d/bin"
  cat > "$d/bin/terraform" <<'STUB'
#!/usr/bin/env bash
case "$G3_MODE" in
  ok)    echo "No changes."; exit 0 ;;
  410)   printf 'Error: Unable to read, got status 410: {"detail":"This API no longer exists."}\n\n  with sentry_alert.synthetic_one,\n  on synthetic.tf line 1, in resource "sentry_alert" "synthetic_one":\n\nError: Unable to read, got status 410: {"detail":"This API no longer exists."}\n\n  with sentry_issue_alert.synthetic_two,\n  on synthetic.tf line 9, in resource "sentry_issue_alert" "synthetic_two":\n'; exit 1 ;;
  mixed) printf 'Error: Unable to read, got status 410: {"detail":"This API no longer exists."}\n\n  with sentry_alert.synthetic_one,\n  on synthetic.tf line 1:\n\nError: Invalid reference\n\n  with sentry_cron_monitor.synthetic_three,\n  on synthetic.tf line 20:\n'; exit 1 ;;
  boxed) printf '╷\n│ Error: Unable to read, got status 410: {"detail":"This API no longer exists."}\n│ \n│   with sentry_alert.synthetic_one,\n│   on synthetic.tf line 1:\n╵\n'; exit 1 ;;
  other) printf 'Error: Invalid provider configuration\n\n  with sentry_cron_monitor.synthetic_three,\n'; exit 1 ;;
  # The provider's usual order: a generic summary, the `with` line, then the 410 in the detail.
  detail) printf 'Error: Client Error\n\n  with sentry_alert.synthetic_one,\n  on synthetic.tf line 1:\n\nUnable to read, got status 410: {"detail":"This API no longer exists."}\n'; exit 1 ;;
  # Vendor text shaped like a `with` line (and like a workflow command) must not be taken as an address.
  spoof) printf 'Error: Unable to read, got status 410:\n  with ::warning::evil, more text\n\n  with sentry_alert.synthetic_one,\n'; exit 1 ;;
  # A Warning: stanza after a 410 error must not have its `with` credited to the 410.
  warn) printf 'Error: Unable to read, got status 410: {"detail":"x"}\n\n  on synthetic.tf line 1:\n\nWarning: Deprecated attribute\n\n  with sentry_cron_monitor.synthetic_four,\n'; exit 1 ;;
esac
STUB
  chmod +x "$d/bin/terraform"
  _g3_run() {  # $1 slice file, $2 mode -> sets out, rc
    local script="$d/run.sh"
    { echo 'set -uo pipefail'; sed -e 's/^          //' -e "s#/tmp/sentry-plan\.out#$d/plan.out#g" "$1"; echo 'echo G3_REACHED_END'; } > "$script"
    rc=0
    out=$(cd "$d" && G3_MODE="$2" PATH="$d/bin:$PATH" bash --noprofile --norc -eo pipefail "$script" 2>&1) || rc=$?
  }
  for (( i = 1; i <= n; i++ )); do
    f="$d/slice$i"
    _g3_run "$f" 410
    [[ "$rc" == "1" ]] || bad+=" slice$i:410:rc=$rc"
    grep -qF 'sentry_issue_alert.synthetic_two' <<<"$(grep -F '::error::' <<<"$out" | grep -F 'on its only attempt' | grep -F 'sentry_alert.synthetic_one' || true)" || bad+=" slice$i:410:annotation"
    _g3_run "$f" mixed
    [[ "$rc" == "1" ]] || bad+=" slice$i:mixed:rc=$rc"
    # Only the 410 stanza's address may be named as a 410.
    grep -qF 'HTTP 410 for sentry_alert.synthetic_one.' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:mixed:annotation"
    ! grep -qF 'synthetic_three' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:mixed:names-non-410"
    _g3_run "$f" boxed
    grep -qF 'HTTP 410 for sentry_alert.synthetic_one.' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:boxed:annotation"
    _g3_run "$f" other
    [[ "$rc" == "1" ]] || bad+=" slice$i:other:rc=$rc"
    grep -qxF '::error::terraform plan failed (exit 1)' <<<"$out" || bad+=" slice$i:other:annotation"
    ! grep -qF '410' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:other:claims-410"
    _g3_run "$f" detail
    grep -qF 'HTTP 410 for sentry_alert.synthetic_one.' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:detail:annotation"
    _g3_run "$f" spoof
    grep -qF 'HTTP 410 for sentry_alert.synthetic_one.' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:spoof:annotation"
    ! grep -qF 'warning' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:spoof:vendor-text-as-address"
    _g3_run "$f" warn
    ! grep -qF 'synthetic_four' <<<"$(grep -F '::error::' <<<"$out" || true)" || bad+=" slice$i:warn:credited-warning"
    _g3_run "$f" ok
    [[ "$rc" == "0" ]] && grep -qxF 'G3_REACHED_END' <<<"$out" || bad+=" slice$i:ok:rc=$rc"
  done
  rm -rf "$d"
  if [[ "$n" -ge 1 && -z "$bad" ]]; then
    _report "T18 each 410-handler slice, executed with a stubbed terraform: 410 -> non-zero + names both addresses; mixed -> names only the 410 address; boxed diagnostics parse; other -> plain error; success -> falls through ($n slices)" ok
  else
    _report "T18 410-handler execution" fail "slices=$n;$bad"
  fi
}

# T19 — the two handler slices are the SAME code. Each is exercised by T16/T18
# separately, so without this they could drift apart and both still pass.
t_g3_slices_identical() {
  local d n; d=$(mktemp -d)  # lint-trap-ownership: ok — rm -rf inline below; no exit between alloc and cleanup (#6734, ADR-129)
  n=$(_g3_slices "$WORKFLOW" "$d")
  local same=0
  if [[ "$n" == "2" ]] && diff -q <(grep -vE '^[[:space:]]*#' "$d/slice1") <(grep -vE '^[[:space:]]*#' "$d/slice2") >/dev/null; then same=1; fi
  rm -rf "$d"
  if [[ "$same" == "1" ]]; then
    _report "T19 the plan_pr and apply 410-handler slices are identical code" ok
  else
    _report "T19 the two 410-handler slices are identical" fail "slices=$n differ (or not 2)"
  fi
}

# T20 — only main applies (#8451 review): a workflow_dispatch from another ref
# would apply that branch's unreviewed .tf with its own copies of the gates.
t_apply_job_main_only() {
  local region; region=$(awk '/^  apply:/{on=1} on && /^    steps:/{exit} on' "$WORKFLOW")
  if grep -qE "^[[:space:]]+&& github\.ref == 'refs/heads/main'$" <<<"$region"; then
    _report "T20 the apply job's if: requires github.ref == refs/heads/main" ok
  else
    _report "T20 apply job is main-only" fail "no github.ref == 'refs/heads/main' conjunct in the apply job's if:"
  fi
}

t_no_unbracketed_status_capture
t_apply_job_fidelity_wiring
t_g3_anchor_count
t_g3_slice_shape
t_g3_no_ladder_residue
t_g3_handler_executes
t_g3_slices_identical
t_apply_job_main_only

echo "=== $pass passed, $fail failed ==="
# Anti-vacuity floor: a deleted dispatch line must red the suite, not shrink it
# (#8451 review — T15-T18 were deletable at exit 0). Reported directly, not
# through _report, which it backstops.
EXPECTED_TESTS=20
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  printf '[FAIL] harness: ran %s test(s), expected %s\n' "$ran" "$EXPECTED_TESTS" >&2
  exit 1
fi
[[ "$fail" -eq 0 ]]
