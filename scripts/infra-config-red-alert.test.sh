#!/usr/bin/env bash
# Tests for infra-config-red-alert.sh (#7220).
#
# This emitter exists because reusing `seccomp_unenforced_alert`'s TRANSPORT reused its
# IDENTITY: an infra-config delivery failure filed an issue TITLED "Security profile (seccomp)
# not enforced", deduped against the seccomp label (so an open seccomp incident swallowed it),
# and paged the seccomp Sentry rule. So the properties under test are mostly about IDENTITY and
# about the two-state split — not about "does it call gh".
#
# The reachable/unreachable split is the second P1: the alert fires on ANY gate failure, and on
# 000/502/503 the listener is DOWN, where `-replace` on the handler bootstrap IS the documented
# route back. Emitting the reachable text there told the operator not to pull the exact lever the
# gate had just prescribed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/infra-config-red-alert.sh"
PASS=0; FAIL=0

# Single owning trap for every sandbox this file allocates (ADR-129, rule (c)). Each mock set
# needs its own dir — the mocks are stateful per case — so they accumulate here and one EXIT
# trap reclaims them all. Without it a mid-run death (a failing assertion under a future
# `set -e`, a SIGINT) leaves a /tmp dir per case behind, and /tmp here is a machine-global
# 4 GiB tmpfs shared by parallel worktrees.
TMPDIRS=()
cleanup_tmpdirs() { [[ ${#TMPDIRS[@]} -gt 0 ]] && rm -rf "${TMPDIRS[@]}"; return 0; }
trap cleanup_tmpdirs EXIT INT TERM
mk_sandbox() { local d; d=$(mktemp -d); TMPDIRS+=("$d"); printf '%s' "$d"; }

ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
has()  { grep -qF "$2" "$1"; }

mk_mocks() {
  local dir="$1"
  cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
printf 'GH:%s\n' "$*" >> "$MOCK_GH_FILE"
if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  [[ -n "${MOCK_EXISTING_ISSUE:-}" ]] && printf '%s\n' "$MOCK_EXISTING_ISSUE"
  exit 0
fi
[[ "${MOCK_GH_WRITE_FAIL:-}" == "1" ]] && exit 4
exit 0
EOF
  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  [[ "$a" == https://* ]] && printf 'CURL_URL:%s\n' "$a" >> "$MOCK_CURL_FILE"
  case "$a" in '{'*) printf 'CURL_BODY:%s\n' "$a" >> "$MOCK_CURL_FILE" ;; esac
done
[[ "${MOCK_CURL_FAIL:-}" == "1" ]] && exit 7
exit 0
EOF
  chmod +x "$dir/gh" "$dir/curl"
}

run_alert() {  # <detail> <reach>
  T=$(mk_sandbox); mk_mocks "$T"
  export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"
  : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
  PATH="$T:$PATH" \
  SENTRY_INGEST_DOMAIN=sentry.example SENTRY_PROJECT_ID=1 SENTRY_PUBLIC_KEY=k \
  INFRA_CONFIG_ALERT_RUN_URL=https://example/run INFRA_CONFIG_ALERT_SHA=abc123 \
    bash "$SCRIPT" "$1" "$2" >/dev/null 2>&1
}

echo "infra-config-red-alert.test.sh"

# --- IDENTITY: the whole reason this file exists ------------------------------------------
run_alert "delivery channel is RED" reachable
if has "$MOCK_GH_FILE" 'ci/infra-config-red'; then
  ok "files under its OWN label, not ci/seccomp-unenforced"
else bad "did not use the ci/infra-config-red label"; fi
if grep -qF 'ci/seccomp-unenforced' "$MOCK_GH_FILE"; then
  bad "LEAKED the seccomp label — an open seccomp incident would swallow this alert"
else ok "never touches the seccomp label (no dedupe collision)"; fi
if grep -qiF 'seccomp' "$MOCK_GH_FILE"; then
  bad "issue text mentions seccomp — the fabricated-security-claim defect"
else ok "issue text makes no security claim"; fi
# jq -n pretty-prints, so the payload carries `"feature": "infra-config"` WITH a space —
# assert the rendered shape, whitespace-tolerant, rather than a compact form the code never emits.
if grep -qE '"feature":[[:space:]]*"infra-config"' "$MOCK_CURL_FILE"; then
  ok "Sentry tags feature:infra-config, not agent-sandbox"
else bad "Sentry payload did not carry feature:infra-config"; fi
if grep -qE '"feature":[[:space:]]*"agent-sandbox"' "$MOCK_CURL_FILE"; then
  bad "Sentry payload still tags agent-sandbox — would page the seccomp rule"
else ok "Sentry never tags agent-sandbox (no rule misroute)"; fi

# --- THE TWO-STATE SPLIT: reachable vs unreachable must NOT say the same thing ------------
run_alert "listener did not answer" unreachable
UNREACH_GH=$(cat "$MOCK_GH_FILE"); UNREACH_CURL=$(cat "$MOCK_CURL_FILE")
run_alert "died at a known line" reachable
REACH_GH=$(cat "$MOCK_GH_FILE")

if [[ "$UNREACH_GH" != "$REACH_GH" ]]; then
  ok "the two states produce DIFFERENT operator-facing output"
else bad "reachable and unreachable emit identical text — the contradiction defect"; fi
if grep -qF 'is not responding' <<<"$UNREACH_GH"; then
  ok "unreachable title says the channel is not responding"
else bad "unreachable state did not use its own title"; fi
# The load-bearing one: on 000/502/503 the gate PRESCRIBES -replace, so the alert must not
# assert app health or forbid the lever.
if grep -qiF 'app health is unaffected' <<<"$UNREACH_GH"; then
  bad "unreachable body asserts app health — it cannot know that when the listener is down"
else ok "unreachable body makes no app-health claim"; fi
if grep -qF 'Do NOT run' <<<"$UNREACH_GH"; then
  bad "unreachable body forbids -replace, contradicting the gate's own recovery guidance"
else ok "unreachable body does not contradict the gate on the -replace lever"; fi
if printf '%s' "$UNREACH_CURL" | grep -qF 'infra-config-listener-down'; then
  ok "unreachable Sentry op is distinguishable from the gate-red op"
else bad "unreachable state reused the gate-red Sentry op"; fi

# --- DEDUPE: comment on an open issue rather than filing a second -------------------------
T=$(mk_sandbox); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
PATH="$T:$PATH" MOCK_EXISTING_ISSUE=4242 bash "$SCRIPT" "recurred" reachable >/dev/null 2>&1
if has "$MOCK_GH_FILE" 'issue comment 4242' && ! has "$MOCK_GH_FILE" 'issue create'; then
  ok "comments on the open issue instead of filing a duplicate"
else bad "did not dedupe onto the existing open issue"; fi

# --- FAIL-OPEN: this runs on the failure path and must never abort the caller -------------
T=$(mk_sandbox); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
PATH="$T:$PATH" MOCK_GH_WRITE_FAIL=1 MOCK_CURL_FAIL=1 bash "$SCRIPT" "everything broken" reachable >/dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
  ok "returns 0 even when BOTH gh and curl fail (fail-open contract)"
else bad "non-zero exit on telemetry failure — would mask the real failure it reports"; fi

# Sentry is skipped, not fatal, when its env is absent.
T=$(mk_sandbox); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
env -u SENTRY_INGEST_DOMAIN -u SENTRY_PROJECT_ID -u SENTRY_PUBLIC_KEY \
  PATH="$T:$PATH" bash "$SCRIPT" "no sentry env" reachable >/dev/null 2>&1
rc_nosentry=$?
if [[ "$rc_nosentry" -eq 0 ]] && [[ ! -s "$MOCK_CURL_FILE" ]] && has "$MOCK_GH_FILE" 'issue'; then
  ok "skips Sentry when its env is unset and still files the issue"
else bad "unset Sentry env broke the GitHub surface (rc=$rc_nosentry)"; fi

# --- #7220 review: THE THIRD STATE, for a gate that never ran -----------------------------
#
# The alert step fires on a job failure where the gate did not pass, which includes the gate
# being SKIPPED because something before it died. Neither existing body is true there:
# "reachable" asserts the files reached the server, "unreachable" asserts the channel did not
# answer. Both name an unmeasured cause. What is actually known is that activation is UNGRADED.
run_alert "the gate never ran" ungraded
UNGRADED_GH=$(cat "$MOCK_GH_FILE"); UNGRADED_CURL=$(cat "$MOCK_CURL_FILE")

if [[ "$UNGRADED_GH" != "$REACH_GH" && "$UNGRADED_GH" != "$UNREACH_GH" ]]; then
  ok "ungraded produces output distinct from BOTH other states"
else bad "ungraded reused another state's text — it would name a cause nothing measured"; fi
if grep -qF 'before it could be checked' <<<"$UNGRADED_GH"; then
  ok "ungraded title says the update was never checked"
else bad "ungraded state did not use its own title"; fi
# The two claims it must NOT make, because it cannot know either.
if grep -qF 'the files themselves reached the server' <<<"$UNGRADED_GH"; then
  bad "ungraded body asserts the files landed — nothing measured that"
else ok "ungraded body makes no delivery claim"; fi
if grep -qF 'did not answer' <<<"$UNGRADED_GH"; then
  bad "ungraded body asserts the channel did not answer — nothing asked it"
else ok "ungraded body makes no listener-down claim"; fi
if grep -qF 'infra-config-gate-ungraded' <<<"$UNGRADED_CURL"; then
  ok "ungraded Sentry op is distinguishable from both other ops"
else bad "ungraded state reused another Sentry op"; fi

# --- #7104 PR-B: THE FOURTH STATE, and the only NON-RED one -------------------------------
#
# The bounded re-push writes PRODUCTION on the sole no-SSH remediation channel and then, on the
# path #7104 exists to create, SUCCEEDS — so the run ends GREEN and, before this mode, told the
# operator nothing at all: the workflow's Sentry breadcrumb (op=infra-config-repush-attempted)
# matches no sentry_issue_alert rule, and the ledger issue is created CLOSED and only ever
# body-edited, which is by construction a surface that never notifies.
#
# The rows below are mostly about what this mode must NOT inherit from the three red ones. The
# dedupe-key row is the load-bearing one: `ci/infra-config-red` is the dedupe key for real P1
# gate failures, so a routine self-heal filed into it would be swallowed as a COMMENT on an open
# incident — or, worse, would itself become the open issue that swallows the next real one. That
# is the identical "two independent classes, one slot" defect this helper's own header records as
# the reason it is not seccomp_unenforced_alert, and it is the failure mode a naive reading of
# "route green runs through infra_config_red_alert" produces.
run_alert "the re-push applied and pass 2 verified" recovered
RECOV_GH=$(cat "$MOCK_GH_FILE"); RECOV_CURL=$(cat "$MOCK_CURL_FILE")

if [[ "$RECOV_GH" != "$REACH_GH" && "$RECOV_GH" != "$UNREACH_GH" && "$RECOV_GH" != "$UNGRADED_GH" ]]; then
  ok "recovered produces output distinct from ALL THREE red states"
else bad "recovered reused a red state's text — it would report a failure that did not happen"; fi

# THE DEDUPE-SLOT SEPARATION. Both directions matter, so both are asserted.
if grep -qF 'ci/infra-config-recovered' <<<"$RECOV_GH"; then
  ok "recovered files under its OWN ci/infra-config-recovered label"
else bad "recovered did not use its own label"; fi
if grep -qF 'ci/infra-config-red' <<<"$RECOV_GH"; then
  bad "recovered touched ci/infra-config-red — a self-heal would swallow (or be swallowed by) a real P1 gate failure in that dedupe slot"
else ok "recovered never touches the red dedupe slot"; fi
if grep -qF 'issue list --label ci/infra-config-recovered' <<<"$RECOV_GH"; then
  ok "recovered DEDUPES against its own label, so an open red incident cannot absorb it"
else bad "recovered deduped against the wrong label"; fi

# Priority: a self-heal that worked is not a p1 page.
if grep -qF 'priority/p2-medium' <<<"$RECOV_GH" && ! grep -qF 'priority/p1-high' <<<"$RECOV_GH"; then
  ok "recovered files at p2, never p1 — it did not page the founder for a success"
else bad "recovered filed at p1 (or omitted p2) — pages the operator for a run that worked"; fi

if grep -qF 'retried itself and succeeded' <<<"$RECOV_GH"; then
  ok "recovered title says the retry succeeded"
else bad "recovered state did not use its own title"; fi

# The three claims it must NOT make, because all three are false on a successful self-heal.
if grep -qF 'did not finish applying' <<<"$RECOV_GH"; then
  bad "recovered body says the update did not finish — it did finish, on the second attempt"
else ok "recovered body asserts no failure"; fi
if grep -qF 'did not answer' <<<"$RECOV_GH"; then
  bad "recovered body asserts the channel did not answer — it answered"
else ok "recovered body makes no listener-down claim"; fi
if grep -qF 'we do not know whether the change took effect' <<<"$RECOV_GH"; then
  bad "recovered body says the outcome is unknown — pass 2 rendered verdict=verified"
else ok "recovered body makes no ungraded claim"; fi

if grep -qF 'infra-config-repush-recovered' <<<"$RECOV_CURL"; then
  ok "recovered Sentry op is distinguishable from all three red ops"
else bad "recovered state reused a red Sentry op"; fi
# Severity and message prefix: an `error`-level event prefixed "delivery gate RED" would train
# the operator to distrust the channel that carries real gate failures.
if grep -qE '"level":[[:space:]]*"warning"' <<<"$RECOV_CURL"; then
  ok "recovered emits at Sentry level warning, not error"
else bad "recovered emitted an error-level Sentry event for a successful recovery"; fi
if grep -qF 'delivery gate RED' <<<"$RECOV_CURL"; then
  bad "recovered Sentry message carries the 'delivery gate RED' prefix — the gate was GREEN"
else ok "recovered Sentry message does not claim the gate was red"; fi

# --- #7220 review: CALLER/CALLEE ENV LOCKSTEP ---------------------------------------------
#
# THE BUG THIS EXISTS FOR. The workflow's alert step exported SECCOMP_ALERT_RUN_URL /
# SECCOMP_ALERT_SHA — copied from the seccomp precedent — while this helper reads
# INFRA_CONFIG_ALERT_RUN_URL / INFRA_CONFIG_ALERT_SHA. Both were therefore ALWAYS empty, so
# every alert body omitted its Commit and CI run lines while its own prose told the operator
# that "the CI run linked below records exactly what was tried". The link was never there.
#
# This file's other cases could not see it: they set the CORRECT names themselves, so they
# proved the helper READS those variables and never that the caller SETS them. A check
# certifying a property adjacent to the one it was named for.
WF="$HERE/../.github/workflows/apply-deploy-pipeline-fix.yml"
if [[ -f "$WF" ]]; then
  # Every variable the helper reads out of the environment, derived from the helper rather than
  # listed here, so a newly-read variable is covered without editing this test.
  helper_vars=$(grep -oE '\$\{INFRA_CONFIG_ALERT_[A-Z_]+' "$SCRIPT" | sed 's/^\${//' | sort -u)
  n_vars=$(grep -c . <<<"$helper_vars")
  if [[ "$n_vars" -ge 2 ]]; then
    ok "derived $n_vars INFRA_CONFIG_ALERT_* variable(s) from the helper"
  else bad "derived only $n_vars INFRA_CONFIG_ALERT_* variables — the extraction is broken, so the lockstep below is vacuous"; fi

  # The alert step's own env block, not the whole workflow: a sibling step legitimately exports
  # SECCOMP_ALERT_* for seccomp_unenforced_alert, and matching that would pass on the bug.
  alert_env=$(awk '
    /^      - name: Alert on a red infra-config gate/ { instep=1; next }
    instep && /^      - name: / { exit }
    instep && /^        run: \|/ { exit }
    instep { print }
  ' "$WF")
  missing=""
  while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    grep -qE "^[[:space:]]+${v}:" <<<"$alert_env" || missing="${missing} ${v}"
  done <<<"$helper_vars"
  if [[ -z "$missing" ]]; then
    ok "the alert step exports every INFRA_CONFIG_ALERT_* variable the helper reads"
  else bad "the alert step never sets:${missing} — the issue body would omit the Commit/CI-run lines it promises"; fi

  # And the inverse half: the step must not be exporting the seccomp names INSTEAD, which is the
  # exact shape of the original defect.
  if grep -qE '^[[:space:]]+SECCOMP_ALERT_' <<<"$alert_env"; then
    bad "the alert step still exports SECCOMP_ALERT_* — the helper does not read those"
  else ok "the alert step does not export the seccomp variable names"; fi

  # --- #7220 review: THE STEP'S CONDITION MUST COVER A GATE THAT NEVER RAN ------------------
  #
  # `== 'failure'` excluded `skipped`, so a pre-gate failure notified nobody. Asserted on the
  # condition text because the branch it guards cannot be reached to observe otherwise.
  #
  # EXTRACTED WITH PyYAML, NOT awk (#7104 PR-B review). The previous extractor was
  # `awk '... /^        if: /{sub(...); print}'`, which reads ONE physical line at a fixed
  # indent. That is an extractor escape, and it fired: when the condition grew past one line and
  # became a folded `if: >-` block, the extractor returned the literal string `>-` and every
  # assertion below graded that instead of the condition. A guard whose subject can be silently
  # replaced by a YAML sigil is not pinning anything. Parsing the document yields the resolved
  # scalar regardless of whether it is written inline, folded, or literal-block.
  #
  # Whitespace is normalised because a folded scalar's line breaks become spaces, so the same
  # logical condition has several byte-representations.
  cond=$(python3 -c '
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for job in wf.get("jobs", {}).values():
    for st in job.get("steps", []) or []:
        if str(st.get("name", "")).startswith("Alert on a red infra-config gate"):
            print(" ".join(str(st.get("if", "")).split()))
            sys.exit(0)
' "$WF" 2>/dev/null)

  if [[ -n "$cond" && "$cond" != ">-" && "$cond" != "|" ]]; then
    ok "extracted the alert step's condition as a resolved scalar ($(wc -c <<<"$cond" | tr -d ' ') bytes)"
  else bad "could not extract the alert condition (got '${cond:-<empty>}') — every row below would be vacuous"; fi

  # A GATE THAT NEVER RAN. Since PR-B the condition keys on the VERDICT, not the step outcome:
  # pass 1 now soft-fails with verdict=pending and exit 0, so `outcome != 'success'` was false on
  # every new terminal-red path. An unset output is '' and `'' != 'verified'` is TRUE, so the
  # verdict form still covers the gate-never-ran case the #7220 review added this row for.
  if grep -qF "steps.infra_config_gate.outputs.verdict != 'verified'" <<<"$cond" \
     && grep -qF "steps.infra_config_gate_pass2.outputs.verdict != 'verified'" <<<"$cond"; then
    ok "the alert keys on BOTH passes' verdicts, so an unset verdict (the gate never ran) still notifies"
  else bad "the alert condition is '${cond}' — it does not require both passes to be non-'verified', so a skipped gate or a mis-keyed pass 2 would notify nobody"; fi

  # A cancelled run must not page. `failure()` gave this for free; `!cancelled()` is the
  # equivalent once the condition also has to fire on a GREEN recovery, where `failure()` is
  # false by construction. Either is acceptable; a bare `always()` is not.
  if grep -qE '(^|[^!])failure\(\)' <<<"$cond" || grep -qF '!cancelled()' <<<"$cond"; then
    ok "the alert cannot fire on a cancelled run (failure() or !cancelled() present)"
  else bad "the alert condition lost its cancellation guard — condition is '${cond}'"; fi
  if grep -qF 'always()' <<<"$cond"; then
    bad "the alert condition uses always(), so a run the operator cancelled would file a P1 incident"
  else ok "the alert condition does not use always()"; fi

  # --- #7104 PR-B: THE GREEN RECOVERY PATH MUST ALSO NOTIFY ---------------------------------
  #
  # The re-push writes production and then succeeds, so the run ends GREEN and `failure()` is
  # false. Before this row the condition was `failure() && ...` alone, and the one path this PR
  # exists to create was the one path that notified nobody.
  if grep -qF 'steps.repush_apply.outcome' <<<"$cond"; then
    ok "the alert condition reads the re-push apply outcome, so a green recovery reaches the operator"
  else bad "the alert condition never mentions steps.repush_apply.outcome — a successful production re-push would notify nobody"; fi

  # THE INVERTED NULL TRAP. `!= 'skipped'` is the natural spelling and is wrong: a renamed or
  # typo'd step id resolves to '', and `'' != 'skipped'` is TRUE, so the mis-keyed case — the one
  # the backstop step exists for — would fire this alert on EVERY run rather than none.
  if grep -qF "steps.repush_apply.outcome != 'skipped'" <<<"$cond"; then
    bad "the alert condition uses \`outcome != 'skipped'\`, which is TRUE for the empty string a renamed step id yields — it would alert on every run"
  else ok "the alert condition does not use the inverted-null \`!= 'skipped'\` form"; fi
else
  bad "could not locate apply-deploy-pipeline-fix.yml — the caller/callee lockstep did NOT run"
fi

# --- #7220 review: THE ALERT STEP'S OWN LOGIC ---------------------------------------------
#
# Drives the step's real `run:` block with a stubbed emitter, so the branch selection and the
# operator-facing rendering are both graded. Run under GitHub's own default shell flags
# (`bash --noprofile --norc -eo pipefail`): `set -e` is ON there and NOT cleared by the block's
# own `set -uo pipefail`, so a harness using a bare `bash` would be blind to an abort.
if [[ -f "$WF" ]]; then
  step_body=$(awk '
    /^      - name: Alert on a red infra-config gate/ { instep=1 }
    instep && /^        run: \|/ { inrun=1; next }
    inrun && /^      - name: / { exit }
    inrun { sub(/^          /, ""); print }
  ' "$WF")
  n_body=$(grep -c . <<<"$step_body")
  if [[ "$n_body" -ge 20 ]]; then
    ok "extracted the alert step's run block ($n_body lines)"
  else bad "extracted only $n_body lines of the alert step — every case below would be vacuous"; fi

  drive_step() {  # <gate-outcome> <apply-outcome> <frame-json-or-empty>
    D=$(mk_sandbox)
    # Stub the emitter: record the ARGUMENTS, which is where reach-mode and WHERE live.
    cat > "$D/stub-helper.sh" <<'STUB'
infra_config_red_alert() { printf 'REACH=%s\n' "${2:-}" >> "$STEP_LOG"; printf 'DETAIL=%s\n' "${1:-}" >> "$STEP_LOG"; return 0; }
STUB
    mkdir -p "$D/ws/scripts"
    cp "$D/stub-helper.sh" "$D/ws/scripts/infra-config-red-alert.sh"
    printf '%s\n' "$step_body" > "$D/step.sh"
    : > "$D/step.log"
    if [[ -n "$3" ]]; then printf '%s' "$3" > "$D/resp.txt"; fi
    # The step hardcodes /tmp/infra-config-status-response.txt; point RESP at the fixture by
    # pre-seeding that path is not safe across parallel runs, so rewrite the one assignment.
    sed -i "s|^RESP=/tmp/infra-config-status-response.txt$|RESP=$D/resp.txt|" "$D/step.sh"
    grep -qF "RESP=$D/resp.txt" "$D/step.sh" || { bad "could not repoint RESP — driver is broken"; return 1; }
    STEP_LOG="$D/step.log" GITHUB_WORKSPACE="$D/ws" \
      GATE_OUTCOME="$1" APPLY_OUTCOME="$2" \
      bash --noprofile --norc -eo pipefail "$D/step.sh" >"$D/out.txt" 2>&1
    STEP_RC=$?
    STEP_OUT=$(cat "$D/step.log")
  }

  # (a) The gate never ran -> ungraded, and it must not fall through to the frame branches.
  drive_step skipped failure ""
  if grep -qF 'REACH=ungraded' <<<"$STEP_OUT"; then
    ok "a skipped gate alerts in the ungraded mode"
  else bad "a skipped gate did not alert as ungraded (rc=$STEP_RC, log=${STEP_OUT:-<empty>})"; fi
  if grep -qF 'terraform apply' <<<"$STEP_OUT"; then
    ok "the ungraded detail names the step that actually failed"
  else bad "the ungraded detail does not name the failing step"; fi

  # (b) The gate ran and failed on a frame with a failed FILE -> the file and reason reach the
  #     operator, rather than "go read the CI log".
  drive_step failure success '{"fatal_line":0,"fatal_rc":0,"fatal_cmd":"","files_written":18,"files_total":19,"files":[{"file":"/etc/webhook/hooks.json","status":"failed","reason":"hooks_json_unparseable"}],"restarts":[]}'
  if grep -qF '/etc/webhook/hooks.json' <<<"$STEP_OUT" && grep -qF 'hooks_json_unparseable' <<<"$STEP_OUT"; then
    ok "the failed file AND the host's reason reach the operator-facing detail"
  else bad "the failed file/reason never reached the detail (log=${STEP_OUT:-<empty>})"; fi

  # (c) Seam normalisation: fatal_cmd carries the handler's internal variable name.
  drive_step failure success '{"fatal_line":642,"fatal_rc":1,"fatal_cmd":"$SYSTEMCTL_PRIV daemon-reload","files_written":19,"files_total":19,"files":[],"restarts":[]}'
  if grep -qF 'sudo systemctl daemon-reload' <<<"$STEP_OUT"; then
    ok "the seam name is rendered as the command that actually ran"
  else bad "fatal_cmd still shows the raw seam variable (log=${STEP_OUT:-<empty>})"; fi
  if grep -qF 'SYSTEMCTL_PRIV' <<<"$STEP_OUT"; then
    bad "the raw \$SYSTEMCTL_PRIV seam name still leaks to the operator"
  else ok "no raw seam variable name leaks to the operator"; fi
fi

# --- ASSERTION FLOOR ----------------------------------------------------------------------
# Deleting a case from this file must be loud. Zero headroom, ratchet when adding cases.
ALERT_MIN_ASSERTIONS=45
if [[ "$PASS" -lt "$ALERT_MIN_ASSERTIONS" ]]; then
  echo "  FAIL: assertion-count floor — only $PASS assertions ran, expected >= $ALERT_MIN_ASSERTIONS"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] || exit 1
