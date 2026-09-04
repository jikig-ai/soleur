#!/usr/bin/env bash
# Guard A and Guard B for the #7650 Phase 2 `sentry_alert` adoption.
#
#   Guard A  no unexplained CREATE reaches the apply, and `sentry_issue_alert`
#            creates halt unconditionally.
#            Implementations: scripts/sentry-issue-alert-create-tripwire.sh (A-ii)
#                             scripts/sentry-create-gate.sh, now invoked in BOTH
#                             workflow jobs (A-i)
#   Guard B  the forget<->import bijection.
#            Implementation: scripts/sentry-forget-import-bijection.sh
#            Consumer:       scripts/sentry-adoption-plan-assert.sh (AC2/AC10)
#
# Guard C — `forget` counted for every type and fed into `destroy_count` — is
# tested where it lives, in tests/scripts/test-destroy-guard-counter-sentry.sh
# (T15-T21) and tests/scripts/test-sentry-destroy-counts.sh (T3b), because its
# property is stated at the destroy gate's verdict rather than at a script's.
#
# ── TWO THINGS THIS SUITE IS BUILT NOT TO DO ───────────────────────────────
# 1. Report a pass from a fixture that failed for a SECOND reason. Every mutant
#    below is checked to have actually LANDED, and every mutant must reach the
#    code under test: a fixture that trips a count guard before the guard under
#    test ever runs proves nothing while reporting green.
# 2. Report `0 passed, 0 failed` and exit 0 with its assertions deleted. The
#    floor at the bottom of this file is the harness row for that: the suite
#    fails unless it actually ran every test it names.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRIPWIRE="$REPO_ROOT/scripts/sentry-issue-alert-create-tripwire.sh"
BIJECTION="$REPO_ROOT/scripts/sentry-forget-import-bijection.sh"
ADOPT="$REPO_ROOT/scripts/sentry-adoption-plan-assert.sh"
BINDING="$REPO_ROOT/scripts/sentry-monitor-binding-gate.sh"
CREATE_GATE="$REPO_ROOT/scripts/sentry-create-gate.sh"
WF="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
pass=0; fail=0
EXPECTED_TESTS=32

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

for f in "$TRIPWIRE" "$BIJECTION" "$ADOPT" "$BINDING" "$CREATE_GATE" "$WF"; do
  [[ -f "$f" ]] || { echo "ERROR: $f does not exist — RED phase expected this." >&2; exit 1; }
done

# ── fixture builders (synthesized; no captured plan is needed for any row) ──
_row() { # $1=type $2=name $3=actions-json [$4=importing-id]
  local imp=""
  [[ -n "${4:-}" ]] && imp=",\"importing\":{\"id\":\"$4\"}"
  printf '{"type":"%s","address":"%s.%s","mode":"managed","change":{"actions":%s,"before":{},"after":{}%s}}' \
    "$1" "$1" "$2" "$3" "$imp"
}

_plan() { # rows... -> a plan document on stdout
  local IFS=,
  printf '{"resource_changes":[%s]}' "$*"
}

# _pairs <n> -> N matched forget/import pairs, named p1..pN
_pairs() {
  local n="$1" i rows=()
  for ((i = 1; i <= n; i++)); do
    rows+=("$(_row sentry_issue_alert "p$i" '["forget"]')")
    rows+=("$(_row sentry_alert "p$i" '["no-op"]' "acme/10$i")")
  done
  _plan "${rows[@]}"
}

_write() { local f="$TMPD/$1.json"; cat > "$f"; echo "$f"; }
_rc() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
_err() { "$@" 2>&1 >/dev/null; }

# The workflow is one file with two jobs whose gate blocks are near-identical.
# Rows A8/A9 are exactly the claim "this invocation exists in THAT job", so
# counting across the whole file would satisfy both rows from one call — the
# asymmetry Guard A exists to close. Slice per job.
_job_region() { # $1=job name -> that job's YAML on stdout
  awk -v job="  $1:" '
    $0 == job { injob = 1; next }
    injob && /^  [a-z_-]+:$/ { injob = 0 }
    injob { print }
  ' "$WF"
}

# ════════════════════════════════════════════════════════════════════════════
# Guard A — create protection
# ════════════════════════════════════════════════════════════════════════════

# A1 — a pure create on sentry_issue_alert is RED, and the message NAMES it.
# "RED" alone is satisfied by a guard that reds on everything; naming the
# address is what makes the failure actionable at 3am.
t_a1_issue_alert_create_red() {
  local f; f=$(_plan "$(_row sentry_issue_alert byok_art_33_breach '["create"]')" | _write a1)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  local msg; msg=$(_err bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'sentry_issue_alert.byok_art_33_breach' <<<"$msg"; then
    _report "A1 a pure create on sentry_issue_alert REDs and names the address" ok
  else
    _report "A1 a pure create on sentry_issue_alert REDs and names the address" fail \
      "rc=$rc (want 1); message did not name the address: $msg"
  fi
}

# A2 — the ack must not reach this tripwire. Two independent claims, because
# either alone is satisfiable by an implementation that still greens on an ack:
# the SCRIPT never reads a commit message, and the workflow INVOCATIONS sit
# outside every ack-conditional branch.
t_a2_not_ack_reachable() {
  local reads_msg structural=ok
  # Anchor on the READ, never on the bare token. The tripwire's own error message
  # says the words "[ack-destroy] does not reach it" — that is prose telling an
  # operator not to try, not a commit-message read, and a bare-token grep flags it.
  # Comments are stripped first for the same reason.
  reads_msg=$(grep -vE '^[[:space:]]*#' "$TRIPWIRE" \
    | grep -cE 'HEAD_MSG|ack_destroy|head_commit|git[[:space:]]+log' || true)
  # In both jobs the tripwire call must precede the first `ack_destroy=` line —
  # everything after that point is inside the ack's blast radius.
  local job
  for job in plan_pr apply; do
    local region tw ack
    region=$(_job_region "$job")
    tw=$(grep -n 'sentry-issue-alert-create-tripwire.sh' <<<"$region" | head -1 | cut -d: -f1)
    ack=$(grep -n '^\s*ack_destroy=false' <<<"$region" | head -1 | cut -d: -f1)
    if [[ -z "$tw" || -z "$ack" || "$tw" -ge "$ack" ]]; then
      structural="bad($job tw=${tw:-none} ack=${ack:-none})"
      break
    fi
  done
  if [[ "$reads_msg" -eq 0 && "$structural" == "ok" ]]; then
    _report "A2 [ack-destroy] cannot reach the tripwire (script reads no commit message; both calls precede the ack)" ok
  else
    _report "A2 [ack-destroy] cannot reach the tripwire" fail \
      "commit-message READS in the script=$reads_msg (want 0), placement=$structural"
  fi
}

# A3 — the case a dropped `import{}` produces IN A LATER PR: a sentry_alert
# create with no added block explaining it.
t_a3_unexplained_sentry_alert_create_red() {
  local c="$TMPD/a3-creates.txt" d="$TMPD/a3.diff"
  printf 'sentry_alert.byok_cap_exceeded\n' > "$c"
  printf '+  frequency_minutes = 60\n' > "$d"
  local rc; rc=$(_rc bash "$CREATE_GATE" "$c" "$d")
  if [[ "$rc" -eq 1 ]]; then
    _report "A3 a sentry_alert create with no added resource block REDs" ok
  else
    _report "A3 a sentry_alert create with no added resource block REDs" fail "rc=$rc want 1"
  fi
}

# A4 — and the mirror: adding an alert stays a normal, silent flow. A3 without
# A4 is satisfied by a gate that reds on every create, which would train the
# ack-blindness the whole design rejects.
t_a4_explained_sentry_alert_create_green() {
  local c="$TMPD/a4-creates.txt" d="$TMPD/a4.diff"
  printf 'sentry_alert.some_new_rule\n' > "$c"
  printf '+resource "sentry_alert" "some_new_rule" {\n+  name = "some-new-rule"\n' > "$d"
  local rc; rc=$(_rc bash "$CREATE_GATE" "$c" "$d")
  if [[ "$rc" -eq 0 ]]; then
    _report "A4 a sentry_alert create explained by an added block passes SILENTLY" ok
  else
    _report "A4 a sentry_alert create explained by an added block passes silently" fail \
      "rc=$rc want 0 — the gate fires on the normal add-an-alert flow"
  fi
}

# A5 — a replace. `["create","delete"]`, and the ordering is not fixed, so the
# tripwire assembles on index("create") and not on exact array equality. A
# replace of a survivor is still a live paging rule torn down and rebuilt.
t_a5_replace_red() {
  local f; f=$(_plan "$(_row sentry_issue_alert auth_per_user_loop '["create","delete"]')" | _write a5)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  local msg; msg=$(_err bash "$TRIPWIRE" "$f")
  # Anchored on the FINDING LINE, not the bare name. The tripwire's static error
  # prose says "Only two sentry_issue_alert resources may exist
  # (auth_per_user_loop, sandbox_startup_failure)" on EVERY failure, so a bare
  # `grep -q auth_per_user_loop` was satisfied by the boilerplate — a mutation
  # that stopped naming the offending address left this row green. Verified by
  # the review's mutation battery.
  if [[ "$rc" -eq 1 ]] && grep -qE 'sentry_issue_alert\.auth_per_user_loop actions=' <<<"$msg"; then
    _report "A5 a create_before_destroy REPLACE on sentry_issue_alert REDs (index, not ==)" ok
  else
    _report "A5 a replace on sentry_issue_alert REDs" fail "rc=$rc (want 1); msg=$msg"
  fi
}

# A6 — vacuity floor on the guard's own dispatch. A full-root Sentry plan always
# carries a row per managed resource, no-ops included (the live baseline carries
# 88), so zero rows means the document is truncated or was never written — not
# that there is nothing to check.
t_a6_zero_rows_red() {
  local empty missing
  empty=$(printf '{"resource_changes":[]}' | _write a6-empty)
  missing=$(printf '{}' | _write a6-missing)
  local rc1 rc2; rc1=$(_rc bash "$TRIPWIRE" "$empty"); rc2=$(_rc bash "$TRIPWIRE" "$missing")
  # The message is pinned too: both SUTs also exit 1 on an unparseable document,
  # so an rc-only assertion would pass on a fixture that broke for another reason.
  local m1; m1=$(_err bash "$TRIPWIRE" "$empty")
  if [[ "$rc1" -eq 1 && "$rc2" -eq 1 ]] && grep -q 'ZERO resource_changes' <<<"$m1"; then
    _report "A6 a plan with zero resource_changes REDs (vacuity floor on dispatch)" ok
  else
    _report "A6 a plan with zero resource_changes REDs" fail \
      "empty-array rc=$rc1, absent-key rc=$rc2, both want 1"
  fi
}

# A7 — the two survivors must still be updatable. Without this row the tripwire
# could be a blanket "no sentry_issue_alert row of any kind", which would red
# every legitimate edit to the two rules the provider cannot express.
t_a7_update_green() {
  local f; f=$(_plan "$(_row sentry_issue_alert auth_per_user_loop '["update"]')" \
                     "$(_row sentry_issue_alert sandbox_startup_failure '["no-op"]')" | _write a7)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "A7 an UPDATE on a surviving sentry_issue_alert passes (the two are still editable)" ok
  else
    _report "A7 an UPDATE on a surviving sentry_issue_alert passes" fail "rc=$rc want 0"
  fi
}

# A8/A9 — the invocation rows. Rows A1-A7 all run against one fixture through one
# entry point, so a single wired call would satisfy the entire matrix while
# reproducing the exact asymmetry Guard A exists to close: before this PR
# `sentry-create-gate.sh` was invoked once, in `plan_pr`, and the `apply` job
# computed `$resource_creates` and never read it.
t_a8_a9_invoked_in_both_jobs() {
  local missing=()
  local job
  for job in plan_pr apply; do
    local region; region=$(_job_region "$job")
    grep -q 'sentry-issue-alert-create-tripwire.sh' <<<"$region" || missing+=("$job:tripwire")
    grep -q 'sentry-create-gate.sh'                 <<<"$region" || missing+=("$job:create-gate")
    grep -q 'sentry-adoption-plan-assert.sh'        <<<"$region" || missing+=("$job:adoption-assert")
    grep -q 'sentry-monitor-binding-gate.sh'        <<<"$region" || missing+=("$job:binding-gate")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _report "A8/A9 every guard is invoked in BOTH plan_pr and apply (no single-job asymmetry)" ok
  else
    _report "A8/A9 every guard is invoked in both plan_pr and apply" fail \
      "missing: ${missing[*]} — a guard wired into one job only leaves the other arm ungated, which is how the apply arm had no create check at all"
  fi
}

# A10 — placement. On the plan artifact, with the apply gated on its exit. A
# tripwire that runs after `terraform apply` fires when the resource already
# exists, which is a report, not a gate.
# A11 — the guards run UNCONDITIONALLY, which A8/A9 cannot see.
#
# THE REGRESSION THIS PR ITSELF FIXED, and which nothing asserted. The tripwire,
# the binding gate and the adoption assert were originally nested inside
# `if [[ "$resource_creates" -gt 0 ]]`, which made the binding gate — the only
# thing that notices all 27 paging rules being repointed at a detector that
# watches nothing — unreachable on exactly the plans it is for, because a
# correlated rebind CREATES NOTHING. Re-nesting them leaves A8/A9 green (the
# strings are still in both job regions), A2 green (still before the ack) and
# A10 green (still before the apply). Verified by the review's mutation battery.
#
# So this asserts PLACEMENT, not presence: in each job region, the invocation
# must not sit inside any `if`/`elif` block. Measured by indentation — an
# invocation nested in a conditional is indented deeper than the `if` that opens
# it, and the shipped calls sit at the same level as the `if` keyword itself.
t_a11_guards_are_unconditional() {
  local nested
  nested=$(python3 - "$WF" <<'PYEOF'
import sys, yaml
GUARDS = ["sentry-issue-alert-create-tripwire.sh",
          "sentry-monitor-binding-gate.sh",
          "sentry-adoption-plan-assert.sh"]
doc = yaml.safe_load(open(sys.argv[1]))
bad, seen = [], set()
for jname in ("plan_pr", "apply"):
    for step in (doc["jobs"][jname].get("steps") or []):
        run = step.get("run")
        if not run:
            continue
        lines = [l for l in run.split("\n") if l.strip()]
        if not lines:
            continue
        # Base indent of this run: script — the level a top-level statement sits at.
        base = min(len(l) - len(l.lstrip()) for l in lines)
        for g in GUARDS:
            for l in lines:
                if g in l and not l.lstrip().startswith("#"):
                    seen.add((jname, g))
                    ind = len(l) - len(l.lstrip())
                    if ind != base:
                        bad.append(f"{jname}:{g} indented {ind} vs base {base}")
                    break
for jname in ("plan_pr", "apply"):
    for g in GUARDS:
        if (jname, g) not in seen:
            bad.append(f"{jname}:{g} ABSENT")
for b in bad:
    print(b)
PYEOF
)
  if [[ -z "$nested" ]]; then
    _report "A11 the tripwire, binding gate and adoption assert run UNCONDITIONALLY in both jobs" ok
  else
    _report "A11 the guards run unconditionally in both jobs" fail \
      "not at the run-script's top level: ${nested} — a correlated rebind creates nothing, so a guard behind \`if resource_creates > 0\` is unreachable on precisely the plans it exists for"
  fi
}

t_a10_runs_before_apply() {
  local region; region=$(_job_region apply)
  local tw ap
  tw=$(grep -n 'sentry-issue-alert-create-tripwire.sh' <<<"$region" | head -1 | cut -d: -f1)
  ap=$(grep -n 'terraform apply -auto-approve' <<<"$region" | head -1 | cut -d: -f1)
  if [[ -n "$tw" && -n "$ap" && "$tw" -lt "$ap" ]]; then
    _report "A10 the tripwire runs on the plan artifact, BEFORE terraform apply" ok
  else
    _report "A10 the tripwire runs before terraform apply" fail \
      "tripwire at line ${tw:-none}, terraform apply at line ${ap:-none} — by the time apply has run the duplicate rule exists and is already paging"
  fi
}

# Harness row (b) — a must-PASS fixture with three unrelated diff-matched
# creates across two other types. Without it the matrix is satisfiable by a
# gate stuck RED.
t_a_harness_three_unrelated_creates_pass() {
  local c="$TMPD/ah-creates.txt" d="$TMPD/ah.diff"
  printf 'sentry_cron_monitor.nightly_reconcile\nsentry_cron_monitor.weekly_digest\nsentry_uptime_monitor.marketing_site\n' > "$c"
  {
    printf '+resource "sentry_cron_monitor" "nightly_reconcile" {\n'
    printf '+resource "sentry_cron_monitor" "weekly_digest" {\n'
    printf '+resource "sentry_uptime_monitor" "marketing_site" {\n'
  } > "$d"
  local rc_gate rc_tw f
  rc_gate=$(_rc bash "$CREATE_GATE" "$c" "$d")
  f=$(_plan "$(_row sentry_cron_monitor nightly_reconcile '["create"]')" \
            "$(_row sentry_cron_monitor weekly_digest '["create"]')" \
            "$(_row sentry_uptime_monitor marketing_site '["create"]')" | _write ah)
  rc_tw=$(_rc bash "$TRIPWIRE" "$f")
  if [[ "$rc_gate" -eq 0 && "$rc_tw" -eq 0 ]]; then
    _report "A-harness three unrelated diff-matched creates across two other types PASS" ok
  else
    _report "A-harness three unrelated diff-matched creates pass" fail \
      "create-gate rc=$rc_gate tripwire rc=$rc_tw, both want 0 — a guard stuck RED satisfies every row above"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Guard B — the forget<->import bijection
# ════════════════════════════════════════════════════════════════════════════

# B1 — the one-line edit that passes everything else: drop an `import{}` and the
# remaining 26 pairs are each individually well-formed. Only the PAIRING breaks.
t_b1_missing_import_red() {
  local f; f=$(_pairs 3 | jq -c 'del(.resource_changes[] | select(.address == "sentry_alert.p2"))' | _write b1)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  local msg; msg=$(_err bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'p2' <<<"$msg" && grep -qi 'not imported' <<<"$msg"; then
    _report "B1 a forget with no matching import REDs and names the unpaired address" ok
  else
    _report "B1 a forget with no matching import REDs and names it" fail "rc=$rc; msg=$msg"
  fi
}

# B2 — the mirror. Same live rule managed twice rather than orphaned.
t_b2_missing_forget_red() {
  local f; f=$(_pairs 3 | jq -c 'del(.resource_changes[] | select(.address == "sentry_issue_alert.p2"))' | _write b2)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  local msg; msg=$(_err bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'p2' <<<"$msg" && grep -qi 'not forgotten' <<<"$msg"; then
    _report "B2 an import with no matching forget REDs and names the unpaired address" ok
  else
    _report "B2 an import with no matching forget REDs and names it" fail "rc=$rc; msg=$msg"
  fi
}

# B3 — MEMBERSHIP, not cardinality. Forget X, import Y: 3 == 3, and the relation
# is still broken. A count-only implementation passes this and ships the bug.
t_b3_mismatched_membership_red() {
  local f
  f=$(_pairs 3 | jq -c '(.resource_changes[] | select(.address == "sentry_alert.p2") | .address) = "sentry_alert.somethingelse"' | _write b3)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  local msg; msg=$(_err bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'p2' <<<"$msg" && grep -q 'somethingelse' <<<"$msg"; then
    _report "B3 equal counts with mismatched membership REDs, naming BOTH sides" ok
  else
    _report "B3 equal counts with mismatched membership REDs" fail \
      "rc=$rc; msg=$msg — cardinality alone passes this fixture, so a count check would ship green"
  fi
}

# B4 — the SECOND pair is broken and the first is intact. Stopping at the first
# member is itself the failure class, and in a file of 27 near-identical blocks
# it is the second one that a scoped edit breaks.
t_b4_second_pair_broken_red() {
  local f; f=$(_pairs 4 | jq -c 'del(.resource_changes[] | select(.address == "sentry_alert.p3"))' | _write b4)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  local msg; msg=$(_err bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'p3' <<<"$msg"; then
    _report "B4 a break in a LATER pair is found and named (no stop-at-first)" ok
  else
    _report "B4 a break in a later pair is found and named" fail "rc=$rc; msg=$msg"
  fi
}

# B5 — the vacuity floor. Two empty sets satisfy set equality trivially; a guard
# that reports PASS over an empty plan is worse than no guard.
t_b5_zero_and_zero_red() {
  local f; f=$(_plan "$(_row sentry_cron_monitor unrelated '["no-op"]')" | _write b5)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  local msg; msg=$(_err bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'ZERO forgets and ZERO imports' <<<"$msg"; then
    _report "B5 zero forgets AND zero imports REDs (vacuity floor)" ok
  else
    _report "B5 zero forgets and zero imports REDs" fail "rc=$rc want 1"
  fi
}

# B6 — matched pairs pass.
t_b6_matched_pairs_green() {
  local f; f=$(_pairs 27 | _write b6)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "B6 27 matched pairs PASS" ok
  else
    _report "B6 27 matched pairs pass" fail "rc=$rc want 0"
  fi
}

# Harness row (b) — vary the CARDINALITY, not the content: 3 matched pairs must
# pass too. A hardcoded 27 inside the bijection would red this and nothing else.
t_b_harness_three_pairs_green() {
  local f; f=$(_pairs 3 | _write bh3)
  local rc; rc=$(_rc bash "$BIJECTION" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "B-harness 3 matched pairs pass (the bijection does not hardcode 27)" ok
  else
    _report "B-harness 3 matched pairs pass" fail "rc=$rc want 0 — the guard has a cardinality baked in"
  fi
}

# Harness row (a) — replace the address extractor with one that returns a
# CONSTANT for every address. The guard must still RED.
#
# A degenerate extractor is the shape in which this guard fails open: collapse
# every address to one token and the two sets compare equal, so a naive
# implementation reports a clean bijection over a plan where the pairing was
# never checked at all. The `_dupes` clause is what stops that — a one-to-one
# relation cannot have a repeated member on either side — and this row is the
# only thing that exercises it.
#
# It is asserted at the mutant's VERDICT, not at which clause produced it: what
# matters is that no extractor bug can turn a broken plan green.
t_b_harness_constant_extractor_defeats_b1() {
  local mut="$TMPD/bijection-mutant.sh"
  # Neutralise the `rname` mapping so every address collapses to one constant.
  sed 's|^  def rname:.*|  def rname: "CONST";|' "$BIJECTION" > "$mut"
  if ! grep -q 'def rname: "CONST";' "$mut"; then
    _report "B-harness a constant address extractor defeats B1" fail \
      "the mutation did not land — rname was not rewritten, so this row proves nothing"
    return
  fi
  local f; f=$(_pairs 3 | jq -c 'del(.resource_changes[] | select(.address == "sentry_alert.p2"))' | _write bhc)
  local real mutant clean_mutant
  real=$(_rc bash "$BIJECTION" "$f")
  mutant=$(_rc bash "$mut" "$f")
  # And on a plan that is genuinely fine: the mutant must red there too, rather
  # than only on B1's fixture. A constant extractor cannot certify anything.
  clean_mutant=$(_rc bash "$mut" "$(_pairs 3 | _write bhc-clean)")
  if [[ "$real" -eq 1 && "$mutant" -eq 1 && "$clean_mutant" -eq 1 ]]; then
    _report "B-harness a constant address extractor still REDs — no extractor bug fails this guard open" ok
  else
    _report "B-harness a constant address extractor still REDs" fail \
      "real rc=$real (want 1), mutant-on-broken rc=$mutant (want 1), mutant-on-clean rc=$clean_mutant (want 1) — a degenerate extractor made the sets compare equal and the guard reported a bijection it never checked"
  fi
}

# B7 — LOCALE COLLATION. The regression that the p1/p2/p3 fixtures structurally
# could not catch, found only by running the guard against the real 27-rule plan.
#
# `sort` under a UTF-8 locale applies collation rules that ignore punctuation;
# `comm` compares byte-wise. On names carrying `_` — which is every one of the
# real 27 — the two disagree, `comm` prints "file 1 is not in sorted order" to
# stderr, and its output is UNDEFINED: it may invent differences or, worse, miss
# real ones. The live plan passed anyway, by luck. A guard that is correct by
# luck on the one input that matters is exactly what this suite exists to stop.
#
# This row asserts BOTH halves, because either alone is satisfiable by a broken
# implementation: the clean case must pass with NO collation warning on stderr,
# and a genuinely broken pair among the same underscore-bearing names must still
# be found and named.
# The name set is MEASURED, not decorative. Under en_US.UTF-8 `sort` these
# interleave (punctuation is ignored):
#     web_a  weba  web_host  webhost
# under `LC_ALL=C sort` they group (`_` is 0x5F, below every lowercase letter):
#     web_a  web_host  weba  webhost
# Two different orders, which is precisely what makes `comm` unsafe. An earlier
# draft of this row used plausible-looking names (byok_art_33_breach, ...) that
# happen to collate IDENTICALLY under both rules — it passed against a
# deliberately broken implementation, which is the "fixture that proves nothing"
# trap. Do not "tidy" these names; the divergence IS the fixture. Verified the
# same way the bug was found: the real 27-rule plan diverges at
# `workspaces_luks_drift`, for the same reason.
_pairs_underscored() { # $1=n -> N matched pairs whose names EXPOSE the collation split
  local n="$1" i rows=()
  local names=(web_a weba web_host webhost web_zz webzz
               zot_a zota zot_mirror zotmirror)
  for ((i = 0; i < n; i++)); do
    rows+=("$(_row sentry_issue_alert "${names[$i]}" '["forget"]')")
    rows+=("$(_row sentry_alert "${names[$i]}" '["no-op"]' "acme/20$i")")
  done
  _plan "${rows[@]}"
}

t_b7_locale_collation() {
  local clean broken rc_clean rc_broken err_clean
  clean=$(_pairs_underscored 10 | _write b7clean)
  broken=$(_pairs_underscored 10 \
    | jq -c 'del(.resource_changes[] | select(.address == "sentry_alert.web_host"))' \
    | _write b7broken)

  err_clean=$(bash "$BIJECTION" "$clean" 2>&1 >/dev/null); rc_clean=$?
  rc_broken=$(_rc bash "$BIJECTION" "$broken")
  local msg_broken; msg_broken=$(_err bash "$BIJECTION" "$broken")

  if [[ "$rc_clean" -eq 0 ]] \
     && ! grep -qi 'not in sorted order' <<<"$err_clean" \
     && [[ "$rc_broken" -eq 1 ]] \
     && grep -q 'web_host' <<<"$msg_broken"; then
    _report "B7 underscore-bearing names: no collation warning, and a broken pair is still named" ok
  else
    _report "B7 underscore-bearing names sort byte-wise for comm" fail \
      "clean rc=$rc_clean (want 0) stderr='$err_clean' (want no 'not in sorted order'); broken rc=$rc_broken (want 1) named=$(grep -c web_host <<<"$msg_broken") — LC_ALL=C is missing from a sort feeding comm, so comm's output is undefined"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# AC11 — the monitor-binding gate. 79 lines of hard gate on the apply path
# whose only prior coverage anywhere in the tree was a grep for its FILENAME.
#
# Its failure mode is the quietest in this PR: a correlated rebind is not a
# delete, not a create and not a nested shrink, so `destroy_count` stays 0, the
# ack passes, and all 27 paging rules — `byok-art-33-breach` included — end up
# pointed at a detector that watches nothing, on a green apply.
# ════════════════════════════════════════════════════════════════════════════
_binding_plan() { # $1..$n = monitor_ids arrays (or the literal `null`)
  local rows=() i=0
  for ids in "$@"; do
    i=$((i + 1))
    rows+=("$(printf '{"type":"sentry_alert","address":"sentry_alert.r%s","mode":"managed","change":{"actions":["no-op"],"before":{},"after":{"monitor_ids":%s}}}' "$i" "$ids")")
  done
  _plan "${rows[@]}"
}

t_d1_correct_binding_passes() {
  local f; f=$(_binding_plan '["1213799"]' '["1213799"]' | _write d1)
  local rc; rc=$(_rc bash "$BINDING" "$f")
  if [[ "$rc" -eq 0 ]]; then _report "D1 every sentry_alert binding the expected detector PASSES" ok
  else _report "D1 correct bindings pass" fail "rc=$rc want 0"; fi
}

t_d2_wrong_binding_reds() {
  local f; f=$(_binding_plan '["1213799"]' '["9999999"]' | _write d2)
  local rc; rc=$(_rc bash "$BINDING" "$f"); local msg; msg=$(_err bash "$BINDING" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q 'sentry_alert.r2' <<<"$msg"; then
    _report "D2 a rebound detector REDs and names the address" ok
  else _report "D2 a rebound detector REDs and names it" fail "rc=$rc msg=$msg"; fi
}

t_d3_unreadable_binding_reds() {
  local f; f=$(_binding_plan '["1213799"]' 'null' | _write d3)
  local rc; rc=$(_rc bash "$BINDING" "$f"); local msg; msg=$(_err bash "$BINDING" "$f")
  if [[ "$rc" -eq 1 ]] && grep -q '<unreadable>' <<<"$msg"; then
    _report "D3 a null monitor_ids is UNCHECKED, not passing — REDs as <unreadable>" ok
  else _report "D3 a null monitor_ids REDs" fail "rc=$rc msg=$msg"; fi
}

# A DELETE row has `.change.after == null`. Before the review it read as an
# unreadable binding, so the first PR deliberately retiring an alert hit a
# permanent, un-acknowledgeable refusal — this gate has no ack path and, unlike
# the adoption assert, does not self-retire.
t_d4_delete_row_is_skipped() {
  local f
  f=$(_plan "$(_row sentry_alert keeper '["no-op"]')" \
            '{"type":"sentry_alert","address":"sentry_alert.retired","mode":"managed","change":{"actions":["delete"],"before":{"monitor_ids":["1213799"]},"after":null}}' \
      | jq -c '(.resource_changes[] | select(.address=="sentry_alert.keeper") | .change.after) = {"monitor_ids":["1213799"]}' | _write d4)
  local rc; rc=$(_rc bash "$BINDING" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "D4 a DELETE row is skipped, not read as an unreadable binding" ok
  else
    _report "D4 a delete row is skipped" fail \
      "rc=$rc want 0 — an intentional retirement cannot be acknowledged past this gate, so it would be permanently un-mergeable"
  fi
}

# The floor that was DEAD CODE: `checked -eq 0` is unreachable, so the real
# vacuity case (a truncated `terraform show -json`) printed a green line. It was
# mitigated only by the create tripwire running first at both call sites.
t_d5_zero_rows_reds() {
  local empty missing
  empty=$(printf '{"resource_changes":[]}' | _write d5e)
  missing=$(printf '{}' | _write d5m)
  local r1 r2; r1=$(_rc bash "$BINDING" "$empty"); r2=$(_rc bash "$BINDING" "$missing")
  local m; m=$(_err bash "$BINDING" "$empty")
  if [[ "$r1" -eq 1 && "$r2" -eq 1 ]] && grep -q 'ZERO resource_changes' <<<"$m"; then
    _report "D5 a zero-row plan REDs on the gate's OWN floor, not a neighbour's ordering" ok
  else _report "D5 a zero-row plan REDs" fail "empty rc=$r1 absent rc=$r2 msg=$m"; fi
}

# Non-vacuity: a legitimate plan touching only monitors must still pass.
t_d6_no_sentry_alert_rows_passes() {
  local f; f=$(_plan "$(_row sentry_cron_monitor nightly '["update"]')" | _write d6)
  local rc; rc=$(_rc bash "$BINDING" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "D6 a non-empty plan with no sentry_alert rows passes (non-vacuity for D5)" ok
  else _report "D6 a monitor-only plan passes" fail "rc=$rc want 0 — every unrelated Sentry PR would red"; fi
}

# ════════════════════════════════════════════════════════════════════════════
# AC2/AC10 — the adoption assert, which is what carries Guard B into the apply
# ════════════════════════════════════════════════════════════════════════════

# C1 — self-skipping. Every plan from the run after this one onward has no
# forget and no import rows; the assert must be inert on them, or it reds every
# future apply of unrelated Sentry work.
t_c1_non_adoption_plan_skips() {
  local f; f=$(_plan "$(_row sentry_cron_monitor newthing '["create"]')" | _write c1)
  local rc; rc=$(_rc bash "$ADOPT" "$f" 27)
  local msg; msg=$(bash "$ADOPT" "$f" 27 2>&1)
  if [[ "$rc" -eq 0 ]] && grep -q 'SKIP' <<<"$msg"; then
    _report "C1 a plan with no forget/import rows SKIPs (inert after the adoption applies)" ok
  else
    _report "C1 a non-adoption plan skips" fail "rc=$rc; msg=$msg"
  fi
}

# C2 — the AC10 property itself: an adoption plan carrying anything that is not
# a no-op or a forget is rejected. This is the hole the apply arm had, where a
# blanket [ack-destroy] greened every non-delete change.
t_c2_extra_change_red() {
  local f
  f=$(_pairs 3 | jq -c '.resource_changes += [{"type":"sentry_alert","address":"sentry_alert.drifted","mode":"managed","change":{"actions":["update"],"before":{},"after":{}}}]' | _write c2)
  local rc; rc=$(_rc bash "$ADOPT" "$f" 3)
  local msg; msg=$(_err bash "$ADOPT" "$f" 3)
  if [[ "$rc" -eq 1 ]] && grep -q 'sentry_alert.drifted' <<<"$msg"; then
    _report "C2 an adoption plan with an extra UPDATE row REDs and names it (AC10)" ok
  else
    _report "C2 an adoption plan with an extra update row REDs" fail "rc=$rc; msg=$msg"
  fi
}

# C3 — cardinality. The bijection holds for 26 pairs too; dropping a
# removed{}+import{} PAIR is the edit that keeps it holding while a live paging
# rule is silently left on the old address.
t_c3_dropped_pair_red() {
  local f; f=$(_pairs 26 | _write c3)
  local rc; rc=$(_rc bash "$ADOPT" "$f" 27)
  local msg; msg=$(_err bash "$ADOPT" "$f" 27)
  if [[ "$rc" -eq 1 ]] && grep -q '26' <<<"$msg"; then
    _report "C3 a dropped removed{}+import{} PAIR REDs on cardinality (the bijection still holds)" ok
  else
    _report "C3 a dropped pair REDs on cardinality" fail "rc=$rc; msg=$msg"
  fi
}

# C4 — a clean adoption passes. Non-vacuity for C2/C3.
t_c4_clean_adoption_green() {
  local f; f=$(_pairs 27 | _write c4)
  local rc; rc=$(_rc bash "$ADOPT" "$f" 27)
  if [[ "$rc" -eq 0 ]]; then
    _report "C4 a clean 27-pair adoption plan PASSES (non-vacuity for C2/C3)" ok
  else
    _report "C4 a clean 27-pair adoption plan passes" fail \
      "rc=$rc want 0 — an assert stuck RED satisfies C2 and C3 without testing anything"
  fi
}

# C5 — the import ids are cross-checked against the committed live capture. An
# id typo does not fail Terraform: it adopts a DIFFERENT live rule under this
# name, and the plan is clean.
# C6 — a DUPLICATED import id. The realistic generator/hand-edit error, and the
# one C5 structurally cannot see: the capture holds all 30 live workflows, so an
# id copy-pasted from another rule IS present in it and passes membership. Two
# addresses importing one id means one live rule adopted twice and one adopted by
# nobody.
t_c6_duplicate_import_id_red() {
  # The capture must hold the ids `_pairs` actually emits (acme/10N -> 101,102,103),
  # AND the duplicate must be one of them. Otherwise this reds on MEMBERSHIP
  # instead of uniqueness — a fixture failing for a second reason, which proves
  # nothing about C6. The assertion below rejects that outcome explicitly rather
  # than accepting any red.
  local cap="$TMPD/capture6.json"
  printf '[{"id":"101","name":"p1"},{"id":"102","name":"p2"},{"id":"103","name":"p3"}]' > "$cap"
  local f
  f=$(_pairs 3 | jq -c '(.resource_changes[] | select(.address == "sentry_alert.p3") | .change.importing.id) = "acme/101"' | _write c6)
  local rc; rc=$(_rc bash "$ADOPT" "$f" 3 "$cap")
  local msg; msg=$(_err bash "$ADOPT" "$f" 3 "$cap")
  if [[ "$rc" -eq 1 ]] && grep -q 'imported at more than one address' <<<"$msg" \
     && ! grep -q 'not present in the committed live capture' <<<"$msg"; then
    _report "C6 a DUPLICATED (but live) import id REDs on uniqueness, not on membership" ok
  else
    _report "C6 a duplicated live import id REDs on uniqueness" fail \
      "rc=$rc; msg=$msg — if this red on membership instead, the fixture's duplicate is not a live id and the row proves nothing"
  fi
}

t_c5_import_id_not_in_capture_red() {
  local cap="$TMPD/capture.json"
  # `_pairs` emits import ids of the form `acme/10N`, so the capture's workflow
  # ids are 101/102/103. A fixture whose ids did not match would red C5's
  # must-PASS arm for a reason that has nothing to do with the assertion.
  printf '[{"id":"101","name":"p1"},{"id":"102","name":"p2"},{"id":"103","name":"p3"}]' > "$cap"
  local good bad
  good=$(_pairs 3 | _write c5good)
  bad=$(_pairs 3 | jq -c '(.resource_changes[] | select(.address == "sentry_alert.p2") | .change.importing.id) = "acme/999999"' | _write c5bad)
  local rc_good rc_bad; rc_good=$(_rc bash "$ADOPT" "$good" 3 "$cap"); rc_bad=$(_rc bash "$ADOPT" "$bad" 3 "$cap")
  local msg; msg=$(_err bash "$ADOPT" "$bad" 3 "$cap")
  if [[ "$rc_good" -eq 0 && "$rc_bad" -eq 1 ]] && grep -q '999999' <<<"$msg"; then
    _report "C5 an import id absent from the live capture REDs; the captured ids pass" ok
  else
    _report "C5 an import id absent from the live capture REDs" fail \
      "captured-ids rc=$rc_good (want 0), bogus-id rc=$rc_bad (want 1); msg=$msg"
  fi
}

t_a1_issue_alert_create_red
t_a2_not_ack_reachable
t_a3_unexplained_sentry_alert_create_red
t_a4_explained_sentry_alert_create_green
t_a5_replace_red
t_a6_zero_rows_red
t_a7_update_green
t_a8_a9_invoked_in_both_jobs
t_a10_runs_before_apply
t_a11_guards_are_unconditional
t_a_harness_three_unrelated_creates_pass
t_b1_missing_import_red
t_b2_missing_forget_red
t_b3_mismatched_membership_red
t_b4_second_pair_broken_red
t_b5_zero_and_zero_red
t_b6_matched_pairs_green
t_b_harness_three_pairs_green
t_b_harness_constant_extractor_defeats_b1
t_b7_locale_collation
t_c1_non_adoption_plan_skips
t_c2_extra_change_red
t_c3_dropped_pair_red
t_c4_clean_adoption_green
t_c5_import_id_not_in_capture_red
t_c6_duplicate_import_id_red
t_d1_correct_binding_passes
t_d2_wrong_binding_reds
t_d3_unreadable_binding_reds
t_d4_delete_row_is_skipped
t_d5_zero_rows_reds
t_d6_no_sentry_alert_rows_passes

echo "=== $pass passed, $fail failed ==="

# ── Harness row (a): the suite must not report `0 passed, 0 failed` and exit 0 ──
# Delete an assertion body and keep the `pass` accounting and this floor is what
# notices. It counts EXECUTED tests, so a commented-out dispatch line reds here
# even though every remaining test is green.
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
