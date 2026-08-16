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

# CASES is the INDEPENDENT counter, incremented at every verdict CALL SITE and never inside
# ok()/bad(). A counter that lives inside the verdict helpers moves WITH the verdict, so stubbing
# bad() to a no-op drops the row and its count together and the accounting identity at the bottom
# still holds. PASS alone cannot serve either: it DEFLATES when verdicts are discarded, so a floor
# reading it fires with "too few assertions" and names the wrong fault.
#
# The call-site set was enumerated with a WIDE pattern
# (`grep -nE '(^|[;{&|]|then |else |\|\| )[[:space:]]*(ok|bad) '`). The narrow `^\s*(ok|bad) `
# form misses two shapes that are both present here: the `|| { bad …; return 1; }` one-liner
# inside drive_step, and the lone `bad` in the `else` arm of the `[[ -f "$WF" ]]` guard.
#
# Never increment inside `$( )` — a subshell discards it.
CASES=0
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
CASES=$((CASES + 1))
if has "$MOCK_GH_FILE" 'ci/infra-config-red'; then
  ok "files under its OWN label, not ci/seccomp-unenforced"
else bad "did not use the ci/infra-config-red label"; fi
CASES=$((CASES + 1))
if grep -qF 'ci/seccomp-unenforced' "$MOCK_GH_FILE"; then
  bad "LEAKED the seccomp label — an open seccomp incident would swallow this alert"
else ok "never touches the seccomp label (no dedupe collision)"; fi
CASES=$((CASES + 1))
if grep -qiF 'seccomp' "$MOCK_GH_FILE"; then
  bad "issue text mentions seccomp — the fabricated-security-claim defect"
else ok "issue text makes no security claim"; fi
# jq -n pretty-prints, so the payload carries `"feature": "infra-config"` WITH a space —
# assert the rendered shape, whitespace-tolerant, rather than a compact form the code never emits.
CASES=$((CASES + 1))
if grep -qE '"feature":[[:space:]]*"infra-config"' "$MOCK_CURL_FILE"; then
  ok "Sentry tags feature:infra-config, not agent-sandbox"
else bad "Sentry payload did not carry feature:infra-config"; fi
CASES=$((CASES + 1))
if grep -qE '"feature":[[:space:]]*"agent-sandbox"' "$MOCK_CURL_FILE"; then
  bad "Sentry payload still tags agent-sandbox — would page the seccomp rule"
else ok "Sentry never tags agent-sandbox (no rule misroute)"; fi

# --- THE TWO-STATE SPLIT: reachable vs unreachable must NOT say the same thing ------------
run_alert "listener did not answer" unreachable
UNREACH_GH=$(cat "$MOCK_GH_FILE"); UNREACH_CURL=$(cat "$MOCK_CURL_FILE")
run_alert "died at a known line" reachable
REACH_GH=$(cat "$MOCK_GH_FILE")

CASES=$((CASES + 1))
if [[ "$UNREACH_GH" != "$REACH_GH" ]]; then
  ok "the two states produce DIFFERENT operator-facing output"
else bad "reachable and unreachable emit identical text — the contradiction defect"; fi
CASES=$((CASES + 1))
if grep -qF 'is not responding' <<<"$UNREACH_GH"; then
  ok "unreachable title says the channel is not responding"
else bad "unreachable state did not use its own title"; fi
# The load-bearing one: on 000/502/503 the gate PRESCRIBES -replace, so the alert must not
# assert app health or forbid the lever.
CASES=$((CASES + 1))
if grep -qiF 'app health is unaffected' <<<"$UNREACH_GH"; then
  bad "unreachable body asserts app health — it cannot know that when the listener is down"
else ok "unreachable body makes no app-health claim"; fi
CASES=$((CASES + 1))
if grep -qF 'Do NOT run' <<<"$UNREACH_GH"; then
  bad "unreachable body forbids -replace, contradicting the gate's own recovery guidance"
else ok "unreachable body does not contradict the gate on the -replace lever"; fi
CASES=$((CASES + 1))
if printf '%s' "$UNREACH_CURL" | grep -qF 'infra-config-listener-down'; then
  ok "unreachable Sentry op is distinguishable from the gate-red op"
else bad "unreachable state reused the gate-red Sentry op"; fi

# --- DEDUPE: comment on an open issue rather than filing a second -------------------------
T=$(mk_sandbox); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
PATH="$T:$PATH" MOCK_EXISTING_ISSUE=4242 bash "$SCRIPT" "recurred" reachable >/dev/null 2>&1
CASES=$((CASES + 1))
if has "$MOCK_GH_FILE" 'issue comment 4242' && ! has "$MOCK_GH_FILE" 'issue create'; then
  ok "comments on the open issue instead of filing a duplicate"
else bad "did not dedupe onto the existing open issue"; fi

# --- FAIL-OPEN: this runs on the failure path and must never abort the caller -------------
T=$(mk_sandbox); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
PATH="$T:$PATH" MOCK_GH_WRITE_FAIL=1 MOCK_CURL_FAIL=1 bash "$SCRIPT" "everything broken" reachable >/dev/null 2>&1
rc_failopen=$?   # captured BEFORE the counter touches $?
CASES=$((CASES + 1))
if [[ "$rc_failopen" -eq 0 ]]; then
  ok "returns 0 even when BOTH gh and curl fail (fail-open contract)"
else bad "non-zero exit on telemetry failure — would mask the real failure it reports"; fi

# Sentry is skipped, not fatal, when its env is absent.
T=$(mk_sandbox); mk_mocks "$T"
export MOCK_GH_FILE="$T/gh.log" MOCK_CURL_FILE="$T/curl.log"; : > "$MOCK_GH_FILE"; : > "$MOCK_CURL_FILE"
env -u SENTRY_INGEST_DOMAIN -u SENTRY_PROJECT_ID -u SENTRY_PUBLIC_KEY \
  PATH="$T:$PATH" bash "$SCRIPT" "no sentry env" reachable >/dev/null 2>&1
rc_nosentry=$?
CASES=$((CASES + 1))
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

CASES=$((CASES + 1))
if [[ "$UNGRADED_GH" != "$REACH_GH" && "$UNGRADED_GH" != "$UNREACH_GH" ]]; then
  ok "ungraded produces output distinct from BOTH other states"
else bad "ungraded reused another state's text — it would name a cause nothing measured"; fi
CASES=$((CASES + 1))
if grep -qF 'before it could be checked' <<<"$UNGRADED_GH"; then
  ok "ungraded title says the update was never checked"
else bad "ungraded state did not use its own title"; fi
# The two claims it must NOT make, because it cannot know either.
CASES=$((CASES + 1))
if grep -qF 'the files themselves reached the server' <<<"$UNGRADED_GH"; then
  bad "ungraded body asserts the files landed — nothing measured that"
else ok "ungraded body makes no delivery claim"; fi
CASES=$((CASES + 1))
if grep -qF 'did not answer' <<<"$UNGRADED_GH"; then
  bad "ungraded body asserts the channel did not answer — nothing asked it"
else ok "ungraded body makes no listener-down claim"; fi
CASES=$((CASES + 1))
if grep -qF 'infra-config-gate-ungraded' <<<"$UNGRADED_CURL"; then
  ok "ungraded Sentry op is distinguishable from both other ops"
else bad "ungraded state reused another Sentry op"; fi

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
  CASES=$((CASES + 1))
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
  CASES=$((CASES + 1))
  if [[ -z "$missing" ]]; then
    ok "the alert step exports every INFRA_CONFIG_ALERT_* variable the helper reads"
  else bad "the alert step never sets:${missing} — the issue body would omit the Commit/CI-run lines it promises"; fi

  # And the inverse half: the step must not be exporting the seccomp names INSTEAD, which is the
  # exact shape of the original defect.
  CASES=$((CASES + 1))
  if grep -qE '^[[:space:]]+SECCOMP_ALERT_' <<<"$alert_env"; then
    bad "the alert step still exports SECCOMP_ALERT_* — the helper does not read those"
  else ok "the alert step does not export the seccomp variable names"; fi

  # --- #7220 review: THE STEP'S CONDITION MUST COVER A GATE THAT NEVER RAN ------------------
  # `== 'failure'` excluded `skipped`, so a pre-gate failure notified nobody. Asserted on the
  # condition text because the branch it guards cannot be reached to observe otherwise.
  cond=$(awk '/^      - name: Alert on a red infra-config gate/{f=1;next} f&&/^        if: /{sub(/^        if: /,"");print;exit}' "$WF")
  CASES=$((CASES + 1))
  if [[ -n "$cond" ]] && grep -qF "!= 'success'" <<<"$cond"; then
    ok "the alert fires whenever the gate did not SUCCEED, not only when it failed"
  else bad "the alert condition is '${cond:-<unparseable>}' — a skipped gate would notify nobody"; fi
  CASES=$((CASES + 1))
  if grep -qF 'failure()' <<<"$cond"; then
    ok "the alert is still scoped to a failed job (a cancelled run does not page)"
  else bad "the alert condition lost its failure() guard"; fi
else
  CASES=$((CASES + 1))
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
  CASES=$((CASES + 1))
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
    grep -qF "RESP=$D/resp.txt" "$D/step.sh" || { CASES=$((CASES + 1)); bad "could not repoint RESP — driver is broken"; return 1; }
    STEP_LOG="$D/step.log" GITHUB_WORKSPACE="$D/ws" \
      GATE_OUTCOME="$1" APPLY_OUTCOME="$2" \
      bash --noprofile --norc -eo pipefail "$D/step.sh" >"$D/out.txt" 2>&1
    STEP_RC=$?
    STEP_OUT=$(cat "$D/step.log")
  }

  # (a) The gate never ran -> ungraded, and it must not fall through to the frame branches.
  drive_step skipped failure ""
  CASES=$((CASES + 1))
  if grep -qF 'REACH=ungraded' <<<"$STEP_OUT"; then
    ok "a skipped gate alerts in the ungraded mode"
  else bad "a skipped gate did not alert as ungraded (rc=$STEP_RC, log=${STEP_OUT:-<empty>})"; fi
  CASES=$((CASES + 1))
  if grep -qF 'terraform apply' <<<"$STEP_OUT"; then
    ok "the ungraded detail names the step that actually failed"
  else bad "the ungraded detail does not name the failing step"; fi

  # (b) The gate ran and failed on a frame with a failed FILE -> the file and reason reach the
  #     operator, rather than "go read the CI log".
  drive_step failure success '{"fatal_line":0,"fatal_rc":0,"fatal_cmd":"","files_written":18,"files_total":19,"files":[{"file":"/etc/webhook/hooks.json","status":"failed","reason":"hooks_json_unparseable"}],"restarts":[]}'
  CASES=$((CASES + 1))
  if grep -qF '/etc/webhook/hooks.json' <<<"$STEP_OUT" && grep -qF 'hooks_json_unparseable' <<<"$STEP_OUT"; then
    ok "the failed file AND the host's reason reach the operator-facing detail"
  else bad "the failed file/reason never reached the detail (log=${STEP_OUT:-<empty>})"; fi

  # (c) Seam normalisation: fatal_cmd carries the handler's internal variable name.
  drive_step failure success '{"fatal_line":642,"fatal_rc":1,"fatal_cmd":"$SYSTEMCTL_PRIV daemon-reload","files_written":19,"files_total":19,"files":[],"restarts":[]}'
  CASES=$((CASES + 1))
  if grep -qF 'sudo systemctl daemon-reload' <<<"$STEP_OUT"; then
    ok "the seam name is rendered as the command that actually ran"
  else bad "fatal_cmd still shows the raw seam variable (log=${STEP_OUT:-<empty>})"; fi
  CASES=$((CASES + 1))
  if grep -qF 'SYSTEMCTL_PRIV' <<<"$STEP_OUT"; then
    bad "the raw \$SYSTEMCTL_PRIV seam name still leaks to the operator"
  else ok "no raw seam variable name leaks to the operator"; fi
fi

# --- ACCOUNTING CONSERVATION ---------------------------------------------------------------
# Deliberately placed BEFORE the floor. This is the arm that catches a NEUTERED verdict helper,
# and the floor cannot: CASES keeps its full value when bad() is a no-op, so the floor stays quiet
# while the verdicts it was floored on have silently evaporated. Ordering matters because a floor
# reading a verdict-derived counter would otherwise fire first and blame "too few assertions" for
# what is really a discarded verdict.
#
# Every counted case records exactly one verdict, so PASS+FAIL MUST equal CASES. Reported with
# `printf >&2` + `exit 1` DIRECTLY, never through bad() or a bare `FAIL=$((FAIL + 1))`: both move
# the counter the exit status reads, and a check enforced through the suspect cannot witness the
# suspect.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != CASES (%d).\n' "$((PASS + FAIL))" "$CASES" >&2
  if [[ $((PASS + FAIL)) -lt "$CASES" ]]; then
    printf '  An assertion was counted but its verdict was not recorded — that is what a neutered ok()/bad() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `CASES=$((CASES + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
  exit 1
fi

# --- ASSERTION FLOOR ----------------------------------------------------------------------
# Deleting a case from this file must be loud. Zero headroom, ratchet when adding cases.
#
# Floored on CASES, not PASS. PASS deflates whenever a verdict is discarded, so a floor on it
# reports a vacuity that did not happen and hides the one that did. CASES moves only with the
# call sites, which is exactly what a floor is about.
#
# Reported directly for the same reason as the conservation check above: the old arm did
# `FAIL=$((FAIL + 1))`, which routes the floor through the very counter a neutered verdict helper
# is corrupting.
ALERT_MIN_ASSERTIONS=29
if [[ "$CASES" -lt "$ALERT_MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$ALERT_MIN_ASSERTIONS" >&2
  echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
  exit 1
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ($CASES assertions) ==="
[[ "$FAIL" -eq 0 ]] || exit 1
