#!/usr/bin/env bash
# Guard A and Guard B for the #7650 Phase 2 `sentry_alert` adoption.
#
#   Guard A  no unexplained CREATE reaches the apply, and `sentry_issue_alert`
#            creates halt unconditionally.
#            Implementations: scripts/sentry-issue-alert-create-tripwire.sh (A-ii)
#                             scripts/sentry-create-gate.sh, now invoked in BOTH
#                             workflow jobs (A-i)
#   Guard 2  (#8451) no create/update/replace of a `sentry_alert` whose
#            after-state carries a legacy trigger type the provider re-sends as
#            `comparison: true`, zeroing the paging threshold.
#            Implementation: scripts/sentry-issue-alert-create-tripwire.sh
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
EXPECTED_TESTS=70

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

# _pairs <n> -> N matched forget/import pairs, named p1..pN. An import row's
# after-state is the object read back from Sentry, so it carries that
# workflow's name (the real plan shape; section 4 of the assert reads it).
_pairs() {
  local n="$1" i rows=()
  for ((i = 1; i <= n; i++)); do
    rows+=("$(_row sentry_issue_alert "p$i" '["forget"]')")
    rows+=("$(_row sentry_alert "p$i" '["no-op"]' "acme/10$i" | jq -c --arg n "p$i" '.change.after.name = $n')")
  done
  _plan "${rows[@]}"
}

# _lrow <name> <actions-json> <legacy-json|absent> [importing-id] -> a
# sentry_alert row whose after-state carries `legacy_trigger_conditions`, the
# field the v0.15.7 provider re-sends with `comparison: true` on any write.
_lrow() {
  local imp="" leg=""
  [[ -n "${4:-}" ]] && imp=",\"importing\":{\"id\":\"$4\"}"
  [[ "$3" != absent ]] && leg="\"legacy_trigger_conditions\":$3"
  printf '{"type":"sentry_alert","address":"sentry_alert.%s","mode":"managed","change":{"actions":%s,"before":{},"after":{%s}%s}}' \
    "$1" "$2" "$leg" "$imp"
}
LEGACY='["event_unique_user_frequency_count"]'

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
  # prose names all three survivors (auth_per_user_loop, sandbox_startup_failure,
  # git_data_boot_warning) on EVERY failure, so a bare `grep -q auth_per_user_loop`
  # is satisfied by the boilerplate — a mutation that drops the real finding line
  # would still pass. #7826 WIDENED that boilerplate from two names to three, so
  # the trap is armed for `git_data_boot_warning` too: any future assertion that
  # greps the tripwire's output for a bare resource name is vacuous. Anchor on the
  # finding line's shape instead.
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

# A7 — the sentry_issue_alert refusal keys on CREATE only. Since #8451 no
# sentry_issue_alert remains (the last two were adopted as `sentry_alert`, and
# their write hazard is Guard 2's, rows G2-*), so this row no longer protects an
# editable survivor. It pins the selector's shape: without it the refusal could
# be a blanket "no sentry_issue_alert row of any kind", which would also red the
# `["forget"]` rows every adoption plan carries.
t_a7_update_green() {
  local f; f=$(_plan "$(_row sentry_issue_alert auth_per_user_loop '["update"]')" \
                     "$(_row sentry_issue_alert sandbox_startup_failure '["no-op"]')" | _write a7)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "A7 an UPDATE on a sentry_issue_alert passes (the refusal is create-only)" ok
  else
    _report "A7 an UPDATE on a sentry_issue_alert passes (the refusal is create-only)" fail "rc=$rc want 0"
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
# Guard 3 (#8630) — the binding gate is ADDRESS-AWARE. Every sentry_alert other
# than the cron-bound set still binds exactly 1213799 (the correlated-rebind
# protection for the issue-stream rules is unchanged). The cron-bound address
# `sentry_alert.cron_monitor_failure` binds a NON-EMPTY set, each element the
# `.values.id` of a `sentry_cron_monitor` in the SAME plan's planned_values,
# never 1213799, never null. A second address binding cron detectors is refused
# until the gate's literal names it. Each RED row asserts the offending ADDRESS
# and its own reason literal, so a RED for a neighbouring reason cannot pass.
# Row 6 of the matrix (the 0-row anti-vacuity floor) is D5 above, unchanged.
# ════════════════════════════════════════════════════════════════════════════
CRON_ADDR="sentry_alert.cron_monitor_failure"
# 59 synthesized cron detector ids (not real Sentry ids).
CRON_IDS=$(jq -nc '[range(59) | tostring | "40000\(.)"]')
# _g3_plan <cron-ids-json> <alerts-json> — a plan whose planned_values carries
# one sentry_cron_monitor per cron id (plus one uptime monitor, so "is some
# monitor's id" and "is a sentry_cron_monitor's id" differ), and whose
# resource_changes carry the given alerts ([{addr, ids}]) plus the monitors.
_g3_plan() {
  jq -nc --argjson c "$1" --argjson a "$2" '
    ([ $c | to_entries[] | {address: "sentry_cron_monitor.m\(.key)", mode: "managed",
         type: "sentry_cron_monitor", name: "m\(.key)", values: {id: .value, name: "m\(.key)"}} ]
     + [ {address: "sentry_uptime_monitor.web", mode: "managed", type: "sentry_uptime_monitor",
          name: "web", values: {id: "555000"}} ]) as $mons
    | { planned_values: { root_module: { resources: (
          $mons + [ $a[] | {address: .addr, mode: "managed", type: "sentry_alert",
                            name: (.addr | sub("^sentry_alert\\."; "")), values: {monitor_ids: .ids}} ] ) } },
        resource_changes: (
          [ $mons[] | {address, mode, type, name, change: {actions: ["no-op"], before: .values, after: .values}} ]
          + [ $a[] | {address: .addr, mode: "managed", type: "sentry_alert",
                      name: (.addr | sub("^sentry_alert\\."; "")),
                      change: {actions: ["no-op"], before: {}, after: {monitor_ids: .ids}}} ] ) }'
}
# _issue_alerts <n> — n issue-stream alerts all binding 1213799.
_issue_alerts() { jq -nc --argjson n "$1" '[range($n) | {addr: "sentry_alert.issue_\(.)", ids: ["1213799"]}]'; }
# _g3_red <label> <plan-file> <address> <reason-literal>
_g3_red() {
  local label="$1" f="$2" addr="$3" want="$4" rc msg
  rc=$(_rc bash "$BINDING" "$f"); msg=$(_err bash "$BINDING" "$f")
  if [[ "$rc" -eq 1 ]] && grep -F -- "$addr " <<<"$msg" | grep -qF -- "$want"; then
    _report "$label" ok
  else
    _report "$label" fail "rc=$rc (want 1), address '$addr' with reason '$want' not on one stderr line. stderr: $(head -c 600 <<<"$msg")"
  fi
}
_cron_ok() { jq -nc --arg a "$CRON_ADDR" --argjson c "$CRON_IDS" '[{addr: $a, ids: $c}]'; }

t_g3_1_issue_rule_rebound_to_cron_red() {
  local alerts f
  alerts=$(jq -nc --argjson i "$(_issue_alerts 3)" --argjson k "$(_cron_ok)" \
    '$i + $k | (.[1].ids = ["400007"])')
  f=$(_g3_plan "$CRON_IDS" "$alerts" | _write g3-1)
  _g3_red "G3-1 an issue-stream rule rebound to a cron detector id REDs (names sentry_alert.issue_1)" \
    "$f" "sentry_alert.issue_1" "expected '1213799'"
}
t_g3_2a_cron_binds_expected_alone_red() {
  local f; f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" '$i + [{addr: $a, ids: ["1213799"]}]')" | _write g3-2a)
  _g3_red "G3-2a cron_monitor_failure binding 1213799 alone REDs (contains the issue-stream detector)" \
    "$f" "$CRON_ADDR" "contains the issue-stream detector '1213799'"
}
t_g3_2b_cron_binds_expected_plus_cron_red() {
  local f; f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" --argjson c "$CRON_IDS" '$i + [{addr: $a, ids: ($c + ["1213799"])}]')" | _write g3-2b)
  _g3_red "G3-2b cron_monitor_failure binding 1213799 PLUS the 59 cron ids REDs" \
    "$f" "$CRON_ADDR" "contains the issue-stream detector '1213799'"
}
t_g3_3_cron_binds_non_cron_id_red() {
  # 555000 IS a monitor in the plan — an uptime monitor, not a cron monitor.
  local f; f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" --argjson c "$CRON_IDS" '$i + [{addr: $a, ids: ($c[1:] + ["555000"])}]')" | _write g3-3)
  _g3_red "G3-3 cron_monitor_failure binding an id that is no sentry_cron_monitor's .values.id (an uptime monitor's) REDs" \
    "$f" "$CRON_ADDR" "not the .values.id of any sentry_cron_monitor"
}
t_g3_4_second_cron_bound_address_red() {
  local f msg
  f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --argjson k "$(_cron_ok)" --argjson c "$CRON_IDS" '$i + $k + [{addr: "sentry_alert.cron_monitor_failure_2", ids: $c[0:3]}]')" | _write g3-4)
  _g3_red "G3-4 a SECOND address binding cron detector ids REDs (not in the gate's cron-bound set)" \
    "$f" "sentry_alert.cron_monitor_failure_2" "not in the gate's cron-bound address set"
  # The compliant first address must not be the one blamed.
  msg=$(_err bash "$BINDING" "$f")
  if grep -qF -- "$CRON_ADDR " <<<"$msg"; then
    _report "G3-4b the compliant cron_monitor_failure is NOT blamed alongside the second address" fail "stderr: $(head -c 400 <<<"$msg")"
  else
    _report "G3-4b the compliant cron_monitor_failure is NOT blamed alongside the second address" ok
  fi
}
t_g3_5a_cron_empty_set_red() {
  local f; f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" '$i + [{addr: $a, ids: []}]')" | _write g3-5a)
  _g3_red "G3-5a cron_monitor_failure binding an EMPTY set REDs" "$f" "$CRON_ADDR" "binds an EMPTY monitor_ids set"
}
t_g3_5b_cron_null_element_red() {
  local f; f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" --argjson c "$CRON_IDS" '$i + [{addr: $a, ids: ($c + [null])}]')" | _write g3-5b)
  _g3_red "G3-5b cron_monitor_failure with a null element REDs" "$f" "$CRON_ADDR" "carries 1 null element(s)"
}
t_g3_p1_real_shape_passes() {
  # 33 issue-stream rules + cron_monitor_failure with all 59 cron ids, the
  # alerts and the ids both in shuffled (non-sorted) order.
  local alerts f rc out
  alerts=$(jq -nc --argjson i "$(_issue_alerts 33)" --arg a "$CRON_ADDR" --argjson c "$CRON_IDS" '
    ($c | to_entries | sort_by((.key * 37) % 59) | map(.value)) as $shuf
    | ($i[0:17] + [{addr: $a, ids: $shuf}] + $i[17:])')
  f=$(_g3_plan "$CRON_IDS" "$alerts" | _write g3-p1)
  if ! jq -e --argjson c "$CRON_IDS" '[.resource_changes[] | select(.type=="sentry_alert")] as $s
        | ($s | length) == 34
        and ($s[17].change.after.monitor_ids | length) == 59
        and ($s[17].change.after.monitor_ids != ($s[17].change.after.monitor_ids | sort))
        and (($s[17].change.after.monitor_ids | sort) == ($c | sort))' "$f" >/dev/null; then
    _report "G3-P1 real shape passes" fail "fixture did not land as 34 alerts with 59 shuffled cron ids"; return
  fi
  rc=0; out=$(bash "$BINDING" "$f" 2>&1) || rc=$?
  # The FULL count clause, not the prefix: "1 cron-bound" is the jq-side count
  # of cron-bound rows that complied, so a regression that stops counting (or
  # counts a non-cron row as cron) moves this literal.
  if [[ "$rc" -eq 0 ]] && grep -qF -- "PASS (34 sentry_alert resource(s): 33 bind detector 1213799, 1 cron-bound" <<<"$out"; then
    _report "G3-P1 33 issue-stream rules + cron_monitor_failure with 59 shuffled cron ids PASS" ok
  else
    _report "G3-P1 real shape passes" fail "rc=$rc out=$(head -c 500 <<<"$out")"
  fi
}
t_g3_p2_no_cron_row_passes() {
  local f rc out
  f=$(_g3_plan "$CRON_IDS" "$(_issue_alerts 33)" | _write g3-p2)
  rc=0; out=$(bash "$BINDING" "$f" 2>&1) || rc=$?
  if [[ "$rc" -eq 0 ]] && grep -qF -- "PASS (33 sentry_alert resource(s)" <<<"$out"; then
    _report "G3-P2 the pre-merge shape (no cron_monitor_failure row) still PASSES" ok
  else
    _report "G3-P2 no cron row passes" fail "rc=$rc out=$(head -c 500 <<<"$out")"
  fi
}
# G3-6 — a monitor id carrying a NEWLINE must not split a verdict row. The gate
# used to emit `addr<TAB>ids<TAB>why` with `jq -r` and re-split it in bash with
# `read`, so an id of "999\n" put an empty `why` on the first half-line (PASS)
# and a bare fragment on the second (PASS), and any passing non-1213799 row
# was counted as cron-bound WITHOUT checking its address.
t_g3_6a_newline_id_on_issue_rule_red() {
  local f msg
  f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" '$i + [{addr: "sentry_alert.a", ids: ["999\n"]}]')" | _write g3-6a)
  _g3_red "G3-6a an issue rule binding [\"999\\n\"] REDs (a newline in an id cannot split the row into two PASSes)" \
    "$f" "sentry_alert.a" "expected '1213799'"
  # The id is rendered ESCAPED on the offending line, never as a raw line break.
  msg=$(_err bash "$BINDING" "$f")
  if grep -F -- "sentry_alert.a " <<<"$msg" | grep -qF -- "'999\\n'"; then
    _report "G3-6b the newline-bearing id is rendered escaped ('999\\n') on the address's own line" ok
  else
    _report "G3-6b newline-bearing id rendered escaped" fail "stderr: $(head -c 400 <<<"$msg")"
  fi
}
t_g3_6c_newline_id_on_cron_rule_red() {
  local f
  f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" '$i + [{addr: $a, ids: ["400000\nx", "1213799"]}]')" | _write g3-6c)
  _g3_red "G3-6c cron_monitor_failure binding [\"400000\\nx\",\"1213799\"] REDs (contains the issue-stream detector)" \
    "$f" "$CRON_ADDR" "contains the issue-stream detector '1213799'"
}
# G3-7 — a REPLACE (["delete","create"] / ["create","delete"]) carries the new
# binding in `.change.after`; only a PURE delete has nothing to check.
_g3_actions() { # $1=address $2=actions-json — jq-edit a plan on stdin
  jq -c --arg a "$1" --argjson act "$2" '(.resource_changes[] | select(.address == $a) | .change.actions) = $act'
}
t_g3_7a_replaced_cron_rule_red() {
  local f
  f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" '$i + [{addr: $a, ids: ["1213799", "999"]}]')" \
      | _g3_actions "$CRON_ADDR" '["delete","create"]' | _write g3-7a)
  if ! jq -e --arg a "$CRON_ADDR" '.resource_changes[] | select(.address == $a) | .change.actions == ["delete","create"]' "$f" >/dev/null; then
    _report "G3-7a replaced cron rule REDs" fail "fixture did not land (actions not [delete,create])"; return
  fi
  _g3_red "G3-7a a REPLACED cron_monitor_failure bound to [1213799,999] REDs (a replace is not skipped as a delete)" \
    "$f" "$CRON_ADDR" "contains the issue-stream detector '1213799'"
}
t_g3_7b_replaced_issue_rule_red() {
  local f alerts
  alerts=$(jq -nc --argjson i "$(_issue_alerts 3)" --argjson k "$(_cron_ok)" '$i + $k | (.[1].ids = ["400007"])')
  f=$(_g3_plan "$CRON_IDS" "$alerts" | _g3_actions "sentry_alert.issue_1" '["create","delete"]' | _write g3-7b)
  if ! jq -e '.resource_changes[] | select(.address == "sentry_alert.issue_1") | .change.actions == ["create","delete"]' "$f" >/dev/null; then
    _report "G3-7b replaced issue rule REDs" fail "fixture did not land (actions not [create,delete])"; return
  fi
  _g3_red "G3-7b a REPLACED issue rule bound to a cron id REDs (create_before_destroy ordering)" \
    "$f" "sentry_alert.issue_1" "expected '1213799'"
}
# G3-8 — only a MANAGED sentry_cron_monitor's id is a routable detector. A
# `data` source of the same type is not a monitor this root declares.
t_g3_8_data_mode_cron_monitor_not_accepted() {
  local f
  f=$(_g3_plan "$CRON_IDS" "$(jq -nc --argjson i "$(_issue_alerts 2)" --arg a "$CRON_ADDR" --argjson c "$CRON_IDS" '$i + [{addr: $a, ids: ($c + ["777000"])}]')" \
      | jq -c '.planned_values.root_module.resources += [{address: "data.sentry_cron_monitor.ext", mode: "data",
                 type: "sentry_cron_monitor", name: "ext", values: {id: "777000", name: "ext"}}]' | _write g3-8)
  if ! jq -e '[.planned_values.root_module.resources[] | select(.type == "sentry_cron_monitor" and .mode == "data" and .values.id == "777000")] | length == 1' "$f" >/dev/null; then
    _report "G3-8 data-mode cron monitor" fail "fixture did not land"; return
  fi
  _g3_red "G3-8 cron_monitor_failure binding a DATA-mode sentry_cron_monitor's id REDs (managed monitors only)" \
    "$f" "$CRON_ADDR" "binds id(s) 777000 that are not the .values.id of any sentry_cron_monitor"
}
# G3-9 — an issue rule binding the issue-stream detector PLUS a cron id is not
# compliant: the issue-stream check is set EQUALITY, not "contains 1213799".
t_g3_9_issue_rule_expected_plus_cron_red() {
  local f alerts
  alerts=$(jq -nc --argjson i "$(_issue_alerts 3)" --argjson k "$(_cron_ok)" '$i + $k | (.[1].ids = ["1213799", "400000"])')
  f=$(_g3_plan "$CRON_IDS" "$alerts" | _write g3-9)
  _g3_red "G3-9 an issue rule binding [1213799,400000] REDs (equality, not containment)" \
    "$f" "sentry_alert.issue_1" "expected '1213799'"
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

# C2 — the AC10 property, SCOPED TO THE ADOPTED ROWS (#8451 CTO ruling). An
# adoption landing on a wedged root necessarily carries the unapplied backlog
# (creates/updates merged while every plan failed), so global inertness cannot
# hold. Inertness is asserted where the adoption acts: every IMPORT row must be
# a no-op, every FORGET must move the legacy type, and nothing anywhere may
# delete or replace. Backlog creates/updates are delegated to the create gate
# (diff-matched against the last applied commit), the reference gate and the
# tripwire, and are printed, never silently passed.
_c2_run() { # $1=label-slug $2=jq-edit -> sets C2_RC, C2_MSG (stdout+stderr)
  local f; f=$(_pairs 3 | jq -c "$2" | _write "c2-$1")
  C2_RC=$(_rc bash "$ADOPT" "$f" 3)
  C2_MSG=$(bash "$ADOPT" "$f" 3 2>&1)
}
t_c2a_import_with_update_red() {
  _c2_run a '(.resource_changes[] | select(.address == "sentry_alert.p2") | .change.actions) = ["update"]'
  if [[ "$C2_RC" -eq 1 ]] && grep -q 'sentry_alert.p2 .*(3a:' <<<"$C2_MSG"; then
    _report "C2a an UPDATE at an imported address REDs and names it (the adopted row is not inert)" ok
  else
    _report "C2a an update at an imported address REDs" fail "rc=$C2_RC; msg=$C2_MSG"
  fi
}
t_c2b_backlog_rows_pass_and_are_printed() {
  _c2_run b '.resource_changes += [
    {"type":"sentry_alert","address":"sentry_alert.backlog_update","mode":"managed","change":{"actions":["update"],"before":{},"after":{}}},
    {"type":"sentry_cron_monitor","address":"sentry_cron_monitor.backlog_create","mode":"managed","change":{"actions":["create"],"before":null,"after":{}}}]'
  if [[ "$C2_RC" -eq 0 ]] && grep -q 'sentry_alert.backlog_update' <<<"$C2_MSG" \
     && grep -q 'sentry_cron_monitor.backlog_create' <<<"$C2_MSG"; then
    _report "C2b backlog create/update rows elsewhere PASS and are printed (delegated, not silent)" ok
  else
    _report "C2b backlog rows pass and are printed" fail "rc=$C2_RC; msg=$C2_MSG"
  fi
}
t_c2c_replace_anywhere_red() {
  _c2_run c '.resource_changes += [{"type":"sentry_alert","address":"sentry_alert.replaced","mode":"managed","change":{"actions":["create","delete"],"before":{},"after":{}}}]'
  if [[ "$C2_RC" -eq 1 ]] && grep -q 'sentry_alert.replaced .*(3c:' <<<"$C2_MSG"; then
    _report "C2c a REPLACE anywhere REDs and names it (no ack reaches it)" ok
  else
    _report "C2c a replace anywhere REDs" fail "rc=$C2_RC; msg=$C2_MSG"
  fi
}
t_c2d_delete_anywhere_red() {
  _c2_run d '.resource_changes += [{"type":"sentry_cron_monitor","address":"sentry_cron_monitor.gone","mode":"managed","change":{"actions":["delete"],"before":{},"after":null}}]'
  if [[ "$C2_RC" -eq 1 ]] && grep -q 'sentry_cron_monitor.gone .*(3c:' <<<"$C2_MSG"; then
    _report "C2d a DELETE anywhere REDs and names it" ok
  else
    _report "C2d a delete anywhere REDs" fail "rc=$C2_RC; msg=$C2_MSG"
  fi
}
t_c2e_forget_of_non_legacy_type_red() {
  _c2_run e '.resource_changes += [{"type":"sentry_alert","address":"sentry_alert.forgotten","mode":"managed","change":{"actions":["forget"],"before":{},"after":null}}]'
  if [[ "$C2_RC" -eq 1 ]] && grep -q 'sentry_alert.forgotten .*(3b:' <<<"$C2_MSG"; then
    _report "C2e a FORGET of a sentry_alert REDs (forgets may only move the legacy type)" ok
  else
    _report "C2e a forget of a sentry_alert REDs" fail "rc=$C2_RC; msg=$C2_MSG"
  fi
}

# L — scripts/sentry-last-applied-sha.sh: the create gate's window starts at the
# commit last APPLIED — the newest main push/dispatch run whose `apply` job ran
# its `Terraform apply` STEP to success. Not the run (a kill-switch run is green
# with the apply skipped) and not the job (a post-apply probe can red the job
# after the apply landed). The fake gh returns API-SHAPED JSON and applies the
# script's own `--jq` filter with the real jq, so the event filter, the job-name
# filter and the step-name filter are all exercised (review M1/M1b/M2/M3).
LAST_APPLIED="$REPO_ROOT/scripts/sentry-last-applied-sha.sh"
SHA_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SHA_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SHA_C=cccccccccccccccccccccccccccccccccccccccc
_la_stub() { # $1=mode -> a PATH dir with a fake gh
  local d="$TMPD/la-$1"; mkdir -p "$d"
  cat > "$d/gh" <<'STUB'
#!/usr/bin/env bash
# Refuse anything but `gh api <expected path> --jq <expr>` (exit 64).
[[ "$1" == api && "$3" == --jq && -n "${4:-}" ]] || { echo "unexpected gh call: $*" >&2; exit 64; }
path="$2"; expr="$4"
step='Terraform apply (cron + uptime monitors)'
job() { # $1=job name $2=job conclusion $3=apply-step conclusion (or "none")
  if [[ "$3" == none ]]; then printf '{"name":"%s","conclusion":"%s","steps":[]}' "$1" "$2"
  else printf '{"name":"%s","conclusion":"%s","steps":[{"name":"Terraform init","conclusion":"success"},{"name":"%s","conclusion":"%s"}]}' "$1" "$2" "$step" "$3"; fi
}
case "$path" in
  "repos/o/r/actions/workflows/apply-sentry-infra.yml/runs?branch=main&status=completed&per_page=50")
    [[ "$LA_MODE" == apierr ]] && exit 1
    if [[ "$LA_MODE" == none ]]; then json='{"workflow_runs":[]}'
    else
      # Run 100 is a pull_request run on the NEWEST slot whose own apply step
      # "succeeded" — the event filter must pass over it.
      json=$(printf '{"workflow_runs":[{"id":100,"head_sha":"%s","event":"pull_request"},{"id":101,"head_sha":"%s","event":"push"},{"id":102,"head_sha":"%s","event":"workflow_dispatch"}]}' "$SHA_C" "$SHA_A" "$SHA_B")
    fi ;;
  "repos/o/r/actions/runs/100/jobs?filter=all&per_page=100")
    json="{\"jobs\":[$(job apply success success)]}" ;;
  "repos/o/r/actions/runs/101/jobs?filter=all&per_page=100")
    # A decoy job listed FIRST carrying the same step name, succeeded: the job
    # filter must not credit it.
    decoy=$(job plan_pr success success)
    case "$LA_MODE" in
      first)      json="{\"jobs\":[$decoy,$(job apply success success)]}" ;;
      skipfirst)  json="{\"jobs\":[$decoy,$(job apply skipped none)]}" ;;
      probefail)  json="{\"jobs\":[$decoy,$(job apply failure success)]}" ;;
      applyfail)  json="{\"jobs\":[$decoy,$(job apply failure failure)]}" ;;
      # Attempt 1 applied, a re-run attempt 2 failed at the apply step: the run
      # WAS applied (filter=all returns both attempts' jobs).
      rerun)      json="{\"jobs\":[$decoy,$(job apply failure failure),$(job apply success success)]}" ;;
      *)          json="{\"jobs\":[$decoy]}" ;;
    esac ;;
  "repos/o/r/actions/runs/102/jobs?filter=all&per_page=100")
    json="{\"jobs\":[$(job apply success success)]}" ;;
  *) echo "unexpected gh path: $path" >&2; exit 64 ;;
esac
printf '%s' "$json" | jq -r "$expr"
STUB
  chmod +x "$d/gh"; echo "$d"
}
_la_run() { # $1=mode -> LA_OUT, LA_RC
  local d; d=$(_la_stub "$1")
  LA_RC=0
  LA_OUT=$(LA_MODE="$1" SHA_A="$SHA_A" SHA_B="$SHA_B" SHA_C="$SHA_C" GITHUB_REPOSITORY=o/r PATH="$d:$PATH" bash "$LAST_APPLIED" 2>&1) || LA_RC=$?
}
t_l1_newest_applied_run() {
  _la_run first
  if [[ "$LA_RC" -eq 0 && "$LA_OUT" == "$SHA_A" ]]; then
    _report "L1 last-applied: the newest push run whose apply STEP succeeded is returned (PR run and decoy job passed over)" ok
  else _report "L1 last-applied newest applied run" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l2_skipped_apply_is_not_applied() {
  _la_run skipfirst
  if [[ "$LA_RC" -eq 0 && "$LA_OUT" == "$SHA_B" ]]; then
    _report "L2 last-applied: a run whose apply job was SKIPPED is passed over (the decoy job's success is not credited)" ok
  else _report "L2 last-applied skips a run with a skipped apply" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l6_post_apply_probe_failure_still_applied() {
  _la_run probefail
  if [[ "$LA_RC" -eq 0 && "$LA_OUT" == "$SHA_A" ]]; then
    _report "L6 last-applied: a job that FAILED after its apply step succeeded still counts as applied (the window does not stall)" ok
  else _report "L6 last-applied counts a post-apply probe failure as applied" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l7_failed_apply_step_is_not_applied() {
  _la_run applyfail
  if [[ "$LA_RC" -eq 0 && "$LA_OUT" == "$SHA_B" ]]; then
    _report "L7 last-applied: a run whose apply STEP failed is passed over" ok
  else _report "L7 last-applied skips a failed apply step" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l9_earlier_attempt_applied() {
  _la_run rerun
  if [[ "$LA_RC" -eq 0 && "$LA_OUT" == "$SHA_A" ]]; then
    _report "L9 last-applied: an earlier ATTEMPT that applied counts even when a later re-run attempt failed" ok
  else _report "L9 last-applied counts an earlier applied attempt" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l3_api_error_fails_closed() {
  _la_run apierr
  if [[ "$LA_RC" -eq 1 && "$LA_OUT" == *"::error::"* ]]; then
    _report "L3 last-applied: an unreadable run list fails CLOSED" ok
  else _report "L3 last-applied fails closed on API error" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l4_nothing_applied_fails_closed() {
  _la_run none
  if [[ "$LA_RC" -eq 1 && "$LA_OUT" == *"none of the newest"* ]]; then
    _report "L4 last-applied: no applied run found fails CLOSED" ok
  else _report "L4 last-applied fails closed when nothing applied" fail "rc=$LA_RC out=$LA_OUT"; fi
}
t_l5_both_sites_use_the_window() {
  # Per SITE, not a file-wide count (review M8): the line immediately above each
  # create-gate `-- 'apps/web-platform/infra/sentry/*.tf'` pathspec must be the
  # diff FROM "$last_applied", and each site must carry the ancestry refusal.
  local diffs; diffs=$(awk '/-- .apps\/web-platform\/infra\/sentry\/\*\.tf. > \/tmp\/sentry-(apply-)?tf\.diff/ { print prev } { prev = $0 }' "$WF")
  local n_diff; n_diff=$(grep -c . <<<"$diffs")
  local n_good; n_good=$(grep -cE '^[[:space:]]+git -C "\$\{GITHUB_WORKSPACE\}" diff "\$last_applied" HEAD \\$' <<<"$diffs")
  local n_call; n_call=$(grep -cE '^[[:space:]]+last_applied=\$\(.*bash "\$\{GITHUB_WORKSPACE\}/scripts/sentry-last-applied-sha\.sh"\) \|\| exit 1$' "$WF")
  local n_anc; n_anc=$(grep -cE 'merge-base --is-ancestor "\$last_applied" HEAD' "$WF")
  if [[ "$n_diff" -eq 2 && "$n_good" -eq 2 && "$n_call" -eq 2 && "$n_anc" -eq 2 ]]; then
    _report "L5 both create-gate sites diff FROM the last applied commit, behind the lookup and an ancestry refusal" ok
  else _report "L5 both create-gate sites use the last-applied window" fail "diff sites=$n_diff last_applied diffs=$n_good lookups=$n_call ancestry=$n_anc"; fi
}
t_l8_step_name_is_the_workflows() {
  # The helper keys on a step NAME; a rename in the workflow must red here, not
  # silently refuse every create in production.
  local step; step=$(sed -n 's/^APPLY_STEP="\(.*\)"$/\1/p' "$LAST_APPLIED")
  if [[ -n "$step" ]] && grep -qxF "      - name: ${step}" "$WF"; then
    _report "L8 the helper's APPLY_STEP names a real step in the workflow ('$step')" ok
  else _report "L8 helper step name matches the workflow" fail "APPLY_STEP='$step' not found as a step name in $WF"; fi
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

# C7 — the imported object must BE the captured workflow of its id. Under
# ignore_changes = all an import always plans no-op, so swapping two live ids
# passes 3a, uniqueness and membership; only the read-back name tells.
t_c7_swapped_import_ids_red() {
  local cap="$TMPD/capture7.json"
  printf '[{"id":"101","name":"p1"},{"id":"102","name":"p2"},{"id":"103","name":"p3"}]' > "$cap"
  local swapped absent
  swapped=$(_pairs 3 | jq -c '(.resource_changes[] | select(.address == "sentry_alert.p1") | .change.after.name) = "p2"
                        | (.resource_changes[] | select(.address == "sentry_alert.p2") | .change.after.name) = "p1"' | _write c7)
  absent=$(_pairs 3 | jq -c '(.resource_changes[] | select(.address == "sentry_alert.p3") | .change.after) = {}' | _write c7b)
  local rc_s rc_a; rc_s=$(_rc bash "$ADOPT" "$swapped" 3 "$cap"); rc_a=$(_rc bash "$ADOPT" "$absent" 3 "$cap")
  local ms ma; ms=$(_err bash "$ADOPT" "$swapped" 3 "$cap"); ma=$(_err bash "$ADOPT" "$absent" 3 "$cap")
  if [[ "$rc_s" -eq 1 && "$rc_a" -eq 1 ]] \
     && grep -q 'sentry_alert.p1 id=101 imported name=p2 capture name=p1' <<<"$ms" \
     && grep -q 'sentry_alert.p3 id=103 imported name=<absent> capture name=p3' <<<"$ma"; then
    _report "C7 an import whose read-back name is not the captured workflow's (swapped or unreadable) REDs" ok
  else
    _report "C7 swapped/unreadable import names RED" fail "rc_s=$rc_s rc_a=$rc_a; msgs: $ms / $ma"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Guard 2 (#8451) — no threshold-destroying write reaches apply
# ════════════════════════════════════════════════════════════════════════════
# Matrix row 2 (a zero-row plan) is A6: the same floor, the same script.
# Every RED row anchors on the FINDING LINE (`sentry_alert.<name> actions=`),
# never on a bare name: the static prose names both adopted rules on every
# failure, so a bare-name grep is satisfied by the boilerplate.

# G2-1 — an update on an adopted legacy-trigger rule. `ignore_changes = all`
# plans no update today; this is the day someone narrows it.
t_g2_1_legacy_update_red() {
  local f; f=$(_plan "$(_lrow sandbox_startup_failure '["update"]' "$LEGACY")" | _write g2-1)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  local msg; msg=$(_err bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 1 ]] && grep -qE 'sentry_alert\.sandbox_startup_failure actions=update' <<<"$msg" \
     && grep -q 'comparison: true' <<<"$msg" && grep -q '#7985' <<<"$msg"; then
    _report "G2-1 an UPDATE on a legacy-trigger sentry_alert REDs, names it, says why and the remedy" ok
  else
    _report "G2-1 an UPDATE on a legacy-trigger sentry_alert REDs" fail "rc=$rc (want 1); msg=$msg"
  fi
}

# G2-3 — second member. A guard that inspects only the first sentry_alert row
# (`first(...)`, `.[0]`) passes this plan: the compliant row comes first.
t_g2_3_second_member_create_red() {
  local f; f=$(_plan "$(_lrow some_native_rule '["no-op"]' '[]')" \
                     "$(_lrow auth_per_user_loop '["create"]' "$LEGACY")" | _write g2-3)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  local msg; msg=$(_err bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 1 ]] && grep -qE 'sentry_alert\.auth_per_user_loop actions=create' <<<"$msg" \
     && ! grep -qE 'sentry_alert\.some_native_rule actions=' <<<"$msg"; then
    _report "G2-3 a legacy CREATE behind a compliant no-op row REDs (census, not first row)" ok
  else
    _report "G2-3 a legacy create behind a compliant row REDs" fail "rc=$rc (want 1); msg=$msg"
  fi
}

# G2-4 — a replace, in both orderings (create_before_destroy serialises
# `["create","delete"]`). A `-replace`/taint or a label rename lands here.
t_g2_4_legacy_replace_red() {
  local a b; a=$(_plan "$(_lrow sandbox_startup_failure '["delete","create"]' "$LEGACY")" | _write g2-4a)
  b=$(_plan "$(_lrow sandbox_startup_failure '["create","delete"]' "$LEGACY")" | _write g2-4b)
  local rc_a rc_b; rc_a=$(_rc bash "$TRIPWIRE" "$a"); rc_b=$(_rc bash "$TRIPWIRE" "$b")
  local ma mb; ma=$(_err bash "$TRIPWIRE" "$a"); mb=$(_err bash "$TRIPWIRE" "$b")
  if [[ "$rc_a" -eq 1 && "$rc_b" -eq 1 ]] \
     && grep -qE 'sentry_alert\.sandbox_startup_failure actions=delete,create' <<<"$ma" \
     && grep -qE 'sentry_alert\.sandbox_startup_failure actions=create,delete' <<<"$mb"; then
    _report "G2-4 a REPLACE on a legacy-trigger sentry_alert REDs in both orderings" ok
  else
    _report "G2-4 a replace on a legacy-trigger sentry_alert REDs" fail \
      "delete,create rc=$rc_a create,delete rc=$rc_b (both want 1); msgs: $ma / $mb"
  fi
}

# G2-5 — must-PASS. The adoption itself is an import no-op (a read), and after
# the #7985 native conversion an update writes the true {interval,value}. A
# guard stuck RED satisfies G2-1/3/4; this row is what it fails.
t_g2_5_import_and_native_update_pass() {
  local f; f=$(_plan "$(_lrow auth_per_user_loop '["no-op"]' "$LEGACY" acme/566671)" \
                     "$(_lrow sandbox_startup_failure '["no-op"]' "$LEGACY" acme/669246)" \
                     "$(_lrow converted_rule '["update"]' '[]')" \
                     "$(_lrow other_native_rule '["update"]' absent)" | _write g2-5)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 0 ]]; then
    _report "G2-5 an import no-op carrying legacy and a native-trigger UPDATE both PASS" ok
  else
    _report "G2-5 import no-op + native update pass" fail "rc=$rc want 0; msg=$(_err bash "$TRIPWIRE" "$f")"
  fi
}

# G2-6 — the refreshed BEFORE state (review of #8451). Narrowing ignore_changes
# AND deleting the `legacy_trigger_conditions` line plans an update whose AFTER
# carries no legacy entry while live still has the trigger: the write strips it.
t_g2_6_before_legacy_update_red() {
  local f; f=$(_plan "$(_lrow sandbox_startup_failure '["update"]' absent)" \
    | jq -c --argjson L "$LEGACY" '.resource_changes[0].change.before = {legacy_trigger_conditions: $L}' | _write g2-6)
  local rc; rc=$(_rc bash "$TRIPWIRE" "$f")
  local msg; msg=$(_err bash "$TRIPWIRE" "$f")
  if [[ "$rc" -eq 1 ]] && grep -qE 'sentry_alert\.sandbox_startup_failure actions=update legacy_trigger_conditions after=\[\] before=\[event_unique_user_frequency_count\]' <<<"$msg"; then
    _report "G2-6 an UPDATE whose after drops the legacy trigger but whose refreshed before carries it REDs" ok
  else
    _report "G2-6 an update stripping a live legacy trigger REDs" fail "rc=$rc (want 1); msg=$msg"
  fi
}

# G2-7 — ANY legacy type, and every member of the list. The provider re-sends
# every legacy entry, not only the fidelity projection's excluded types; and a
# selector reading `$legacy[0]` must not miss the second element.
t_g2_7_any_legacy_type_and_second_element_red() {
  local a b
  a=$(_plan "$(_lrow r_other '["update"]' '["issue_resolution_change"]')" | _write g2-7a)
  b=$(_plan "$(_lrow r_two '["create"]' '["issue_resolution_change","event_unique_user_frequency_count"]')" | _write g2-7b)
  local rc_a rc_b; rc_a=$(_rc bash "$TRIPWIRE" "$a"); rc_b=$(_rc bash "$TRIPWIRE" "$b")
  local ma mb; ma=$(_err bash "$TRIPWIRE" "$a"); mb=$(_err bash "$TRIPWIRE" "$b")
  if [[ "$rc_a" -eq 1 && "$rc_b" -eq 1 ]] \
     && grep -qE 'sentry_alert\.r_other actions=update .*after=\[issue_resolution_change\]' <<<"$ma" \
     && grep -qE 'sentry_alert\.r_two actions=create .*after=\[issue_resolution_change,event_unique_user_frequency_count\]' <<<"$mb"; then
    _report "G2-7 a write carrying a non-excluded legacy type, or a two-element legacy list, REDs" ok
  else
    _report "G2-7 any legacy type / every element REDs" fail "rc_a=$rc_a rc_b=$rc_b; msgs: $ma / $mb"
  fi
}

# G2-8 — an import that also UPDATES is a write, and a legacy value unknown at
# plan time cannot be judged, so both are refused.
t_g2_8_import_update_and_unknown_red() {
  local a b
  a=$(_plan "$(_lrow auth_per_user_loop '["update"]' "$LEGACY" acme/566671)" | _write g2-8a)
  b=$(_plan "$(_lrow r_unknown '["create"]' absent)" \
    | jq -c '.resource_changes[0].change.after_unknown = {legacy_trigger_conditions: true}' | _write g2-8b)
  local rc_a rc_b; rc_a=$(_rc bash "$TRIPWIRE" "$a"); rc_b=$(_rc bash "$TRIPWIRE" "$b")
  local ma mb; ma=$(_err bash "$TRIPWIRE" "$a"); mb=$(_err bash "$TRIPWIRE" "$b")
  if [[ "$rc_a" -eq 1 && "$rc_b" -eq 1 ]] \
     && grep -qE 'sentry_alert\.auth_per_user_loop actions=update' <<<"$ma" \
     && grep -qE 'sentry_alert\.r_unknown actions=create .*unknown at plan time' <<<"$mb"; then
    _report "G2-8 an import that UPDATES, and a legacy value unknown at plan time, both RED" ok
  else
    _report "G2-8 import+update and unknown legacy RED" fail "rc_a=$rc_a rc_b=$rc_b; msgs: $ma / $mb"
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
t_g2_1_legacy_update_red
t_g2_3_second_member_create_red
t_g2_4_legacy_replace_red
t_g2_5_import_and_native_update_pass
t_g2_6_before_legacy_update_red
t_g2_7_any_legacy_type_and_second_element_red
t_g2_8_import_update_and_unknown_red
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
t_c2a_import_with_update_red
t_c2b_backlog_rows_pass_and_are_printed
t_c2c_replace_anywhere_red
t_c2d_delete_anywhere_red
t_c2e_forget_of_non_legacy_type_red
t_c3_dropped_pair_red
t_l1_newest_applied_run
t_l2_skipped_apply_is_not_applied
t_l3_api_error_fails_closed
t_l4_nothing_applied_fails_closed
t_l5_both_sites_use_the_window
t_l6_post_apply_probe_failure_still_applied
t_l7_failed_apply_step_is_not_applied
t_l8_step_name_is_the_workflows
t_l9_earlier_attempt_applied
t_c4_clean_adoption_green
t_c5_import_id_not_in_capture_red
t_c7_swapped_import_ids_red
t_c6_duplicate_import_id_red
t_d1_correct_binding_passes
t_d2_wrong_binding_reds
t_d3_unreadable_binding_reds
t_d4_delete_row_is_skipped
t_d5_zero_rows_reds
t_d6_no_sentry_alert_rows_passes
t_g3_1_issue_rule_rebound_to_cron_red
t_g3_2a_cron_binds_expected_alone_red
t_g3_2b_cron_binds_expected_plus_cron_red
t_g3_3_cron_binds_non_cron_id_red
t_g3_4_second_cron_bound_address_red
t_g3_5a_cron_empty_set_red
t_g3_5b_cron_null_element_red
t_g3_p1_real_shape_passes
t_g3_p2_no_cron_row_passes
t_g3_6a_newline_id_on_issue_rule_red
t_g3_6c_newline_id_on_cron_rule_red
t_g3_7a_replaced_cron_rule_red
t_g3_7b_replaced_issue_rule_red
t_g3_8_data_mode_cron_monitor_not_accepted
t_g3_9_issue_rule_expected_plus_cron_red

echo "=== $pass passed, $fail failed ==="

# ── Harness row (a): the suite must not report `0 passed, 0 failed` and exit 0 ──
# Delete an assertion body and keep the `pass` accounting and this floor is what
# notices. It counts EXECUTED tests, so a commented-out dispatch line reds here
# even though every remaining test is green.
#
# Harness row (b): the floor below reads counters that ONLY `_report` moves, so
# it backstops the very helper it depends on. Drive both of `_report`'s paths
# once with the counters snapshotted, check each moved by exactly one, then
# unwind. Emitted with printf + exit DIRECTLY — routing this through `_report`
# would dispatch the detector through the thing it detects (the pattern in
# apps/web-platform/scripts/sentry-monitors-audit.test.sh and the defect class
# scripts/guard-vacuity-floor.test.sh exists for).
_h_p=$pass; _h_f=$fail
{ _report "harness self-test (unwound)" ok; _report "harness self-test (unwound)" fail; } >/dev/null 2>&1
if [[ "$pass" -ne $((_h_p + 1)) || "$fail" -ne $((_h_f + 1)) ]]; then
  printf 'FATAL: _report cannot conclude — pass %s->%s (want +1), fail %s->%s (want +1).\n' \
    "$_h_p" "$pass" "$_h_f" "$fail" >&2
  exit 1
fi
pass=$_h_p; fail=$_h_f
ran=$((pass + fail))
if [[ "$ran" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $ran test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

[[ "$fail" -eq 0 ]]
