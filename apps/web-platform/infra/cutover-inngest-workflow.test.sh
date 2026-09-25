#!/usr/bin/env bash
# Tests for .github/workflows/cutover-inngest.yml — the no-SSH cutover driver
# (#5450, AC5/Test-Scenario-5). The live workflow can only be exercised post-merge
# (a NEW workflow 404s on `gh workflow run --ref <feature-branch>`, R4), so these
# assert the YAML shape + the safety/poll invariants statically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF_YAML="$REPO_ROOT/.github/workflows/cutover-inngest.yml"
BODY_SH="$REPO_ROOT/scripts/cutover-inngest.sh"

PASS=0
FAIL=0

# Owning cleanup trap (ADR-129). This suite allocates eight scratch files/dirs across its
# sections and, until #6178, owned none of them: the explicit `rm -f` sat at the very END of
# the file, so any mid-suite death (`set -e`, a helper that exits non-zero) leaked every one.
# Paths are registered at creation and removed exactly once, here.
SCRATCH=()
scratch_cleanup() {
  (( ${#SCRATCH[@]} )) && rm -rf "${SCRATCH[@]}"
  # Render scratch dirs are created inside `$(…)` subshells (#8054 render_2_0), where a SCRATCH+=
  # would be lost; the render appends its dir to this file instead, and it is swept here.
  if [[ -n "${RENDER_TMPDS:-}" && -f "$RENDER_TMPDS" ]]; then xargs -r rm -rf < "$RENDER_TMPDS"; rm -f "$RENDER_TMPDS"; fi
  return 0
}
trap scratch_cleanup EXIT

# #7002: THE CUTOVER DEFINITION IS NOW TWO FILES — reconstruct the single-file view.
#
# The 118,722-byte `run:` body was extracted VERBATIM to scripts/cutover-inngest.sh because
# it deadlocked actionlint (a body over the 65,536-byte pipe buffer blocks the shellcheck
# integration forever, so the repo's only workflow linter reported nothing at all, on every
# file). Nothing about the cutover's behaviour changed.
#
# Every content assertion below was written against the pre-extraction file, and ~120 of them
# grep or awk that body — many ANCHORED ON ITS YAML INDENTATION (e.g. /^            verify\)$/,
# twelve spaces). A plain `cat` of the two files would silently break every one of those:
# YAML dedents a `|` block scalar, so the script holds the body at column 0 while the
# assertions expect it at the block-scalar indent.
#
# So $WF is rebuilt as the byte-equivalent of what the workflow used to be: the YAML as-is,
# plus the script body re-indented by the 10 spaces the `run: |` block carried. Every existing
# assertion then means exactly what it meant before the extraction, and a future edit to
# EITHER file is still covered.
#
# $WF_YAML remains the real workflow for the two structural assertions (file exists, YAML
# parses) — the reconstructed view is deliberately NOT valid YAML.
WF="$(mktemp)"
SCRATCH+=("$WF")
cat "$WF_YAML" > "$WF"
sed -n '/^set -euo pipefail$/,$p' "$BODY_SH" | sed 's/^./          &/' >> "$WF"

assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

# SELF-TEST of the assertion helper (#7462 review). Neutering `assert` — e.g. `eval "$cond" || true`
# — made the whole suite report 381 passed / 0 failed / exit 0 with real regressions injected, and
# the pass COUNT is not a tell because PASS increments on the same branch. Nothing downstream can
# be trusted unless the helper itself is shown to distinguish true from false, so prove both
# directions here and subtract the deliberate failure.
_ST_P=$PASS; _ST_F=$FAIL
assert "self-test: a TRUE condition passes" "true"
assert "self-test: a FALSE condition fails (expected FAIL below)" "false"
if [[ "$PASS" -ne $((_ST_P + 1)) || "$FAIL" -ne $((_ST_F + 1)) ]]; then
  echo "  FATAL: assert() does not distinguish true from false — every verdict in this file is void."
  exit 2
fi
FAIL=$((FAIL - 1))   # subtract the deliberate failure; the PASS from the true case is left as-is
echo "  (assert() self-test OK — deliberate FAIL above is expected and subtracted)"

echo "=== cutover-inngest.yml workflow tests ==="

assert "workflow file exists" "[[ -f '$WF_YAML' ]]"
assert "extracted cutover body exists (#7002)" "[[ -f '$BODY_SH' ]]"

# YAML parses
assert "YAML parses (pyyaml)" "python3 -c 'import yaml,sys; yaml.safe_load(open(\"$WF_YAML\"))'"

# op input is a constrained choice (NOT a free string → no run-step injection)
assert "op input is type: choice" "grep -qE 'type:[[:space:]]*choice' '$WF'"
assert "choice includes enumerate" "grep -qE '^[[:space:]]+-[[:space:]]*enumerate$' '$WF'"
assert "choice includes rearm" "grep -qE '^[[:space:]]+-[[:space:]]*rearm$' '$WF'"
assert "choice includes verify-wiped-volume" "grep -qE '^[[:space:]]+-[[:space:]]*verify-wiped-volume$' '$WF'"
assert "choice includes backup (#5509)" "grep -qE '^[[:space:]]+-[[:space:]]*backup$' '$WF'"
assert "choice includes inventory (#5509)" "grep -qE '^[[:space:]]+-[[:space:]]*inventory$' '$WF'"
assert "choice includes capture (#5542)" "grep -qE '^[[:space:]]+-[[:space:]]*capture$' '$WF'"
assert "capture arm POSTs mode=capture" "grep -qE '\"mode\":\"capture\"' '$WF'"

# op is passed via env, never interpolated into a run: command (injection-safe).
# FIX L2 — scan the WHOLE file, not `grep -A200 'run:'` from the FIRST run: (the body is
# ~640 lines, so the old window missed most of it). Assert there is EXACTLY ONE
# `${{ inputs.op }}` occurrence in the entire workflow AND it is the `env: OP:` assignment.
# Any other occurrence (e.g. a raw `${{ inputs.op }}` interpolated into a run shell — the
# injection vector) would push the count above 1 or move the sole ref off the OP: line.
OP_REFS=$(grep -cE '\$\{\{[[:space:]]*inputs\.op' "$WF" || true)
assert "exactly one \${{ inputs.op }} reference in the whole workflow (L2)" "[[ '$OP_REFS' -eq 1 ]]"
assert "op passed via env (the sole ref is OP: \${{ inputs.op }})" "grep -qE 'OP:[[:space:]]*\\\$\{\{[[:space:]]*inputs\.op[[:space:]]*\}\}' '$WF'"

# least privilege + registration + serialization
assert "permissions: contents: read" "grep -qE 'contents:[[:space:]]*read' '$WF'"
assert "push registration trigger scoped to self" "grep -qE 'cutover-inngest.yml' '$WF'"
assert "shares deploy/restart concurrency group (state-slot serialization)" "grep -qE 'group:[[:space:]]*deploy-inngest-restart' '$WF'"
assert "timeout-minutes present (>= poll budget)" "grep -qE 'timeout-minutes:[[:space:]]*[0-9]+' '$WF'"
assert "no-op on the registration push (workflow_dispatch guard)" "grep -qE \"github.event_name == 'workflow_dispatch'\" '$WF'"

# Rule D (#7873 / ADR-202, paid down at #8054 when this file left the lint's baseline): EVERY
# credentialed curl is transport-confined — `--disable` as the LITERAL FIRST argument, then
# `--noproxy '*'`. Counted against the curl count so a new call site cannot land unconfined.
BODY_CURLS=$(grep -vE '^[[:space:]]*#' "$BODY_SH" | grep -cE '\bcurl ' || true)
BODY_CONFINED=$(grep -vE '^[[:space:]]*#' "$BODY_SH" | grep -cE "\bcurl --disable --noproxy '\*' " || true)
assert "#8054 every curl in the body is transport-confined (curl=$BODY_CURLS confined=$BODY_CONFINED)" "[[ '$BODY_CURLS' -ge 20 && '$BODY_CURLS' -eq '$BODY_CONFINED' ]]"
assert "#8054 the body refuses to run under xtrace (it binds live credentials)" "grep -qE '^[[:space:]]*\*x\*\) printf .*refusing to run under xtrace.*exit 78' '$BODY_SH'"

# every curl carries --max-time (no unbounded network call)
CURL_LINES=$(grep -c 'curl ' "$WF" || true)
MAXTIME_LINES=$(grep -c -- '--max-time' "$WF" || true)
assert "at least one curl present" "[[ '$CURL_LINES' -ge 3 ]]"
assert "every curl has --max-time (count parity)" "[[ '$CURL_LINES' -eq '$MAXTIME_LINES' ]]"

# HMAC + CF-Access on the webhook calls (mirrors restart-inngest-server.yml)
assert "HMAC X-Signature-256 header" "grep -qE 'X-Signature-256: sha256=' '$WF'"
assert "CF-Access client id header" "grep -qE 'CF-Access-Client-Id' '$WF'"
assert "uses WEBHOOK_DEPLOY_SECRET (no new secret)" "grep -qE 'WEBHOOK_DEPLOY_SECRET' '$WF'"

# the destructive verify polls the DEDICATED verify-status (not deploy-status), with a freshness guard
assert "polls inngest-verify-status (dedicated responder)" "grep -qE 'inngest-verify-status' '$WF'"
assert "verify webhook expects async 202" "grep -qE '!= \"202\"' '$WF'"
assert "freshness guard present (TRIGGER_TS - 60)" "grep -qE 'FRESH_FLOOR=\\\$\(\(TRIGGER_TS - 60\)\)' '$WF'"

# enumerate surfaces counts/ids only, never comment bodies (P2-sec-a)
assert "enumerate emits reminder_id list, not bodies" "grep -qE 'reminder_id\] \| join' '$WF'"

# every webhook hook the workflow hits must be a real hook id in hooks.json.tmpl
# (a hook rename would otherwise 404 silently). Cross-check all 4 trigger URLs.
HOOKS_TMPL="$REPO_ROOT/apps/web-platform/infra/hooks.json.tmpl"
# #6178 — op=execute/verify add the registry-probe (2.0/precondition) and the
# doublefire-probe (2.6) web-host hooks; both MUST be real hook ids AND targeted.
HOOK_IDS=(inngest-enumerate-reminders inngest-rearm-reminders inngest-wiped-volume-verify inngest-verify-status inngest-inventory inngest-registry-probe inngest-doublefire-probe)
assert "hook-existence loop has >=1 hook (min-cardinality)" "[[ '${#HOOK_IDS[@]}' -ge 1 ]]"
for hook in "${HOOK_IDS[@]}"; do
  # #6919 — the doublefire URL now carries a ?from=&function_ids= query string, so the name may
  # be followed by `?` (query) OR `"` (bare). The char-class boundary still guards against a
  # longer hook name false-matching (e.g. a hypothetical inngest-doublefire-probe-2).
  assert "workflow targets \$BASE/$hook" "grep -qE 'BASE/${hook}[?\"]' '$WF'"
  assert "hook id '$hook' exists in hooks.json.tmpl" "grep -qE '\"id\": \"$hook\"' '$HOOKS_TMPL'"
done

# #5542 — the rearm hook bridges the cutover mode from the POST payload to the
# host script via pass-environment (capture vs rearm). Without this, op=capture
# cannot reach the script and the pre-deploy capture never persists.
assert "rearm hook bridges mode via pass-environment (INNGEST_REARM_MODE)" "grep -qE 'INNGEST_REARM_MODE' '$HOOKS_TMPL'"

# ============================================================================
# #6178 Phase D — op=execute / op=verify / op=rollback arms + quiesce hard-gate
# ============================================================================

# D.1 — the three new ops are in the constrained choice list (injection-safe).
assert "choice includes execute (#6178)" "grep -qE '^[[:space:]]+-[[:space:]]*execute$' '$WF'"
assert "choice includes verify (#6178)" "grep -qE '^[[:space:]]+-[[:space:]]*verify$' '$WF'"
assert "choice includes rollback (#6178)" "grep -qE '^[[:space:]]+-[[:space:]]*rollback$' '$WF'"

# D.1 — every new op is a real case arm in case \"\$OP\" (not just a menu label).
assert "case arm: execute)" "grep -qE '^[[:space:]]+execute\\)' '$WF'"
assert "case arm: verify)" "grep -qE '^[[:space:]]+verify\\)' '$WF'"
assert "case arm: rollback)" "grep -qE '^[[:space:]]+rollback\\)' '$WF'"

# D.1 — $CUTOVER_HOSTS is computed ONCE in the step env (P1-8/DI-C3): the same
# host-set drives 2.1 capture and 2.2 quiesce so they cannot drift.
assert "CUTOVER_HOSTS defined once in step env (P1-8)" "grep -qE 'CUTOVER_HOSTS:[[:space:]]*\"' '$WF'"

# D.2 / AC-EXEC2 — op=execute 2.0: calls the registry-probe hook and ABORTS
# (exit 1) when the dark registry is non-empty, before any flip.
assert "execute calls the registry-probe hook (2.0)" "grep -qE 'BASE/inngest-registry-probe\"' '$WF'"
assert "execute ABORTs on non-empty registry (registry_empty != true)" "grep -qE 'REG_EMPTY.*!=.*\"true\"' '$WF'"
assert "execute 2.0 abort carries P1-6 remediation text" "grep -qE 'Remediation \(P1-6\)' '$WF'"

# D.2 / AC-QUIESCE-GATE (P1-7) — the quiesce HARD GATE: assert zero inngest
# running across the host-set, WITHHOLD the SEAM and exit non-zero if any survives.
assert "execute has a QUIESCE HARD GATE (P1-7)" "grep -qE 'QUIESCE HARD GATE' '$WF'"
assert "quiesce gate tracks still-running hosts (STILL_RUNNING accumulator)" "grep -qE 'STILL_RUNNING' '$WF'"
assert "quiesce gate withholds the SEAM + exits non-zero on survivors" "grep -qE 'QUIESCE HARD GATE FAILED' '$WF'"
# `grep -qF`, not `-qE 'SEAM . operator'` (#7462): the separator is an EM-DASH (e2 80 94),
# and ERE `.` matches exactly one BYTE, so the regex form matches only under a UTF-8 locale.
# Measured — LC_ALL=C returns 0 matches, LC_ALL=en_US.UTF-8 returns 1 — which false-FAILED
# this assertion (and, via the count, the anti-deletion floor) inside preflight Check 10's
# `env -i` sandbox and would do the same on any CI runner with no LANG set. A fixed-string
# match is byte-exact and locale-independent.
assert "execute prints the operator SEAM only after the gate" "grep -qF 'SEAM — operator maintenance-window steps' '$WF'"
# The SEAM must gate the flip arm on Better Stack, NOT a host read (P0-2).
assert "SEAM confirms the flip via Better Stack, not a host cat (P0-2)" "grep -qE 'Better Stack' '$WF'"
# #6369 — the 2.2b/2.3 arm-flip is no longer a manual Doppler write in the SEAM; the SEAM now
# directs the operator to the no-SSH op=arm dispatch (the armed write itself is asserted in the
# op=arm case body section below).
assert "SEAM directs the arm-flip to the no-SSH op=arm dispatch (#6369)" "grep -qE 'dispatch the no-SSH op=arm verb|op=arm' '$WF'"

# D.3 / AC-VERIFY — op=verify: precondition registry NON-empty (2.4 landed,
# P1-9/P2-17), 2.6 via the doublefire hook, RunsFilterV2 + STARTED_AT bucketing,
# and NO scheduled_tick anywhere in the workflow.
assert "verify calls the doublefire-probe hook (2.6/P1-12)" "grep -qE 'BASE/inngest-doublefire-probe[?\"]' '$WF'"
assert "verify preconditions on registry NON-empty (P1-9/P2-17)" "grep -qE 'verify precondition' '$WF'"
assert "verify buckets by floor(startedAt / cron_period) (no scheduled_tick)" "grep -qE 'fromdateiso8601' '$WF'"
# (#6939: the old "verify auto-emits the missed-tick trigger-cron list" grep was retired — it
# matched `soleur:trigger-cron` anywhere, so the new OFF pointer satisfied it too. The executed
# ON/OFF cases in the #6939 block near the end of this file replace it.)
assert "workflow contains NO 'scheduled_tick' anywhere (AC-VERIFY)" "! grep -qE 'scheduled_tick' '$WF'"

# D.6 / AC-ROLLBACK (P1-13) — op=rollback re-enables inngest across the host-set via a
# SINGLE no-SSH `enable inngest _ _` fan-out (enable+start+verify in one flock-held handler,
# #6178) and POLLS deploy-status for the `enabled` verdict — NOT a two-POST enable+restart
# (flock race, arch P1-1) and NOT a bare inventory probe.
assert "rollback issues a SINGLE 'enable inngest _ _' fan-out (#6178)" "grep -qE 'enable inngest _ _' '$WF'"
assert "rollback does NOT POST 'restart inngest _ latest' (no two-POST flock race)" "! grep -qE 'restart inngest _ latest' '$WF'"
assert "rollback POLLS deploy-status for the enabled verdict" "grep -qE 'reason=enabled' '$WF'"
assert "rollback does NOT print an operator systemctl re-enable SEAM (#6178)" "! grep -qE 'systemctl enable inngest-server.service' '$WF'"
assert "rollback iterates the SAME \$CUTOVER_HOSTS set (P1-13)" "grep -qE 'reverse of 2.2 quiesce' '$WF'"

# #6178 — op=quiesce-web: the no-SSH stop+disable of the co-located web scheduler that
# closes the cutover 2.2 gap (operators have no SSH). It is a constrained choice + a real
# case arm; POSTs `quiesce inngest _ _` + peers to /hooks/deploy and POLLS deploy-status for
# the terminal `quiesced` verdict (NOT a bare inventory probe raced against the async stop).
assert "choice includes quiesce-web (#6178)" "grep -qE '^[[:space:]]+-[[:space:]]*quiesce-web\$' '$WF'"
assert "case arm: quiesce-web)" "grep -qE '^[[:space:]]+quiesce-web\\)' '$WF'"
assert "quiesce-web POSTs 'quiesce inngest _ _' with peers fan-out" "grep -qE '\"command\":\"quiesce inngest _ _\",\"peers\"' '$WF'"
assert "quiesce-web POLLS deploy-status for the quiesced verdict (not a bare inventory probe)" "grep -qE 'reason=quiesced' '$WF'"
assert "quiesce-web freshness-anchors the poll (FRESH_FLOOR)" "grep -qE 'FRESH_FLOOR=\\\$\\(\\(TRIGGER_TS - 60\\)\\)' '$WF'"
# 2.2 HARD GATE failure remediation now points at op=quiesce-web, NOT an operator host-shell step.
assert "2.2 gate failure remediation references op=quiesce-web (no-SSH)" "grep -qE 'op=quiesce-web' '$WF'"
assert "2.2 gate failure remediation no longer instructs an operator 'systemctl disable' host step" "! grep -qE 'stop \\+ systemctl disable inngest\\) on the LB-reachable host' '$WF'"
# quiesce-web's own failure verdicts each carry a no-SSH forward action (spec-flow F2).
assert "quiesce-web failure verdicts print a no-SSH forward action (Do NOT SSH)" "grep -qE 'Do NOT SSH the host' '$WF'"

# #6178 Fix-1 (observability P2) — BOTH deploy-status poll loops (quiesce-web + rollback)
# FAST-FAIL on a TERMINAL-but-unrecognized reason (exit_code != -1 yet matched no enumerated
# case branch) instead of polling to the full timeout. Without this a reason rename silently
# degrades to a $((MAX_POLLS * POLL_INTERVAL))s timeout with no actionable error. Assert both
# loops carry the fast-fail (count == 2, one per loop).
UNREC_N=$(grep -cE '::error::unrecognized terminal reason' "$WF" || true)
assert "both poll loops fast-fail on an unrecognized terminal reason (quiesce + rollback)" "[[ '$UNREC_N' -eq 2 ]]"

# AC-NOSSH — no ssh in any new command.
assert "no 'ssh ' command anywhere in the workflow (AC-NOSSH)" "! grep -qE '(^|[^[:alnum:]])ssh[[:space:]]' '$WF'"

# Data-driven loops (host-set fan-out) carry a min-cardinality guard so an empty
# CUTOVER_HOSTS cannot silently no-op the capture/quiesce/rollback fan-out.
assert "host-set loops guard against an empty CUTOVER_HOSTS (min-cardinality)" "grep -qE 'CUTOVER_HOSTS is empty' '$WF'"

# ============================================================================
# FIX H1 — CUTOVER_HOSTS parity guard. The value MUST EQUAL the canonical
# WEB_HOST_PRIVATE_IPS source of truth (its own comment says so), not merely be
# "defined once" / non-empty. Canonical SoT: variables.tf `web_hosts` private_ip
# values (Terraform), mirrored by WEB_HOST_PRIVATE_IPS in web-platform-release.yml.
# Derive both and assert CUTOVER_HOSTS is byte-identical (sorted) — a web host
# added/removed in variables.tf, or a typo in either list, then fails CI here.
# ============================================================================
VARIABLES_TF="$REPO_ROOT/apps/web-platform/infra/variables.tf"
RELEASE_YML="$REPO_ROOT/.github/workflows/web-platform-release.yml"
CUTOVER_HOSTS_VAL=$(grep -oP 'CUTOVER_HOSTS:[[:space:]]*"\K[^"]+' "$WF")
CUTOVER_SORTED=$(printf '%s' "$CUTOVER_HOSTS_VAL" | tr ',' '\n' | sort | paste -sd,)
# Canonical set from variables.tf web_hosts private_ip entries (the `default` map).
CANON_TF=$(grep -oE 'private_ip[[:space:]]*=[[:space:]]*"10\.0\.1\.[0-9]+"' "$VARIABLES_TF" \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd,)
# Canonical set from web-platform-release.yml WEB_HOST_PRIVATE_IPS.
CANON_RELEASE=$(grep -oP 'WEB_HOST_PRIVATE_IPS:[[:space:]]*"\K[^"]+' "$RELEASE_YML" \
  | tr ',' '\n' | sort | paste -sd,)
assert "CUTOVER_HOSTS is non-empty (parity precondition)" "[[ -n '$CUTOVER_HOSTS_VAL' ]]"
assert "variables.tf web_hosts private_ip set derived non-empty" "[[ -n '$CANON_TF' ]]"
assert "web-platform-release.yml WEB_HOST_PRIVATE_IPS derived non-empty" "[[ -n '$CANON_RELEASE' ]]"
assert "CUTOVER_HOSTS == variables.tf web_hosts private_ip set (canonical SoT parity, H1)" "[[ '$CUTOVER_SORTED' == '$CANON_TF' ]]"
assert "CUTOVER_HOSTS == WEB_HOST_PRIVATE_IPS (web-platform-release.yml parity, H1)" "[[ '$CUTOVER_SORTED' == '$CANON_RELEASE' ]]"
assert "canonical sources agree (variables.tf == web-platform-release.yml)" "[[ '$CANON_TF' == '$CANON_RELEASE' ]]"

# ============================================================================
# FIX M2 — F.2 disjointness drift-guard. The cutover-flip trio + guard live ONLY
# on the OCI/cloud-init bake surfaces; the two web-host probes live ONLY on the
# webhook-registration surfaces. A file drifting onto the wrong surface (the flip
# oneshot registered as a web-host webhook, or a probe baked into the OCI image) is
# a topology error this pins. Mirrors the DPF-gate style.
# ============================================================================
INFRA_DIR="$REPO_ROOT/apps/web-platform/infra"
BUILD_IMG="$REPO_ROOT/.github/workflows/build-inngest-bootstrap-image.yml"
OCI_SURFACES=("$BUILD_IMG" "$INFRA_DIR/inngest-bootstrap.sh" "$INFRA_DIR/cloud-init-inngest.yml")
WEBHOOK_SURFACES=("$INFRA_DIR/server.tf" "$INFRA_DIR/hooks.json.tmpl" "$INFRA_DIR/push-infra-config.sh" "$INFRA_DIR/infra-config-apply.sh" "$INFRA_DIR/infra-config-install.sh")
FLIP_TRIO=(inngest-cutover-flip.sh inngest-cutover-flip.service inngest-cutover-flip.timer cat-inngest-cutover-state.sh inngest-server-flip-guard.sh)
PROBES=(inngest-registry-probe.sh inngest-doublefire-probe.sh)
assert "disjointness: >=1 OCI surface + >=1 webhook surface (min-cardinality)" "[[ '${#OCI_SURFACES[@]}' -ge 1 && '${#WEBHOOK_SURFACES[@]}' -ge 1 ]]"
# (a) flip trio + guard PRESENT on the OCI surface union, ABSENT from every webhook surface.
for asset in "${FLIP_TRIO[@]}"; do
  assert "flip asset '$asset' present on an OCI/cloud-init surface" "grep -qF '$asset' ${OCI_SURFACES[*]}"
  for wfs in "${WEBHOOK_SURFACES[@]}"; do
    assert "flip asset '$asset' ABSENT from webhook surface $(basename "$wfs")" "! grep -qF '$asset' '$wfs'"
  done
done
# (b) the two probes PRESENT on the webhook surface union, ABSENT from every OCI surface.
for probe in "${PROBES[@]}"; do
  assert "probe '$probe' present on a webhook surface" "grep -qF '$probe' ${WEBHOOK_SURFACES[*]}"
  for ocis in "${OCI_SURFACES[@]}"; do
    assert "probe '$probe' ABSENT from OCI bake surface $(basename "$ocis")" "! grep -qF '$probe' '$ocis'"
  done
done

# ============================================================================
# #6258 — op=execute 2.-1 POOL PRE-CHECK (Test Scenario 3). The live gate can only
# run post-merge (a new workflow shape 404s on --ref <feature>), so assert the
# fail-closed shape statically. Anchors are UNIQUE code substrings from the
# ::error:: echo lines / the arithmetic guard — never the explanatory comment prose
# (which also contains "FAIL-CLOSED"), per the grep-over-body false-match trap.
# ============================================================================
assert "pool pre-check reads SUPABASE_ACCESS_TOKEN (read-only mgmt API)" "grep -qF 'secrets.SUPABASE_ACCESS_TOKEN' '$WF'"
# Ordering: the pre-check MUST run BEFORE the 2.0 registry probe (2.0 opens its own
# GQL→Postgres connection that would otherwise be counted against the readiness baseline).
PRECHECK_LN=$(grep -nF 'READINESS_CEILING=' "$WF" | head -1 | cut -d: -f1)
REGPROBE_LN=$(grep -nF '2.0 empty-registry pre-flight' "$WF" | head -1 | cut -d: -f1)
assert "case (a) 2.-1 pool pre-check runs BEFORE the 2.0 registry probe" "[[ -n '$PRECHECK_LN' && -n '$REGPROBE_LN' && '$PRECHECK_LN' -lt '$REGPROBE_LN' ]]"
assert "case (a) clean pool below ceiling emits ::notice:: and proceeds" "grep -qF '2.-1 pool pre-check CLEAN' '$WF'"
# (b) gates on readiness baseline + burst headroom, NOT the 80%-of-cap pressure line
assert "case (b) gates on readiness ceiling + burst headroom (not 80%)" "grep -qF 'INNGEST_CONNS + EXPECTED_BURST_COST > POOL_SIZE - SUPAVISOR_WARM_RESERVE' '$WF'"
assert "case (b) over-ceiling fails closed" "grep -qF 'exceeds readiness ceiling' '$WF'"
# (c) EMAXCONNSESSION in body → fail-closed
assert "case (c) EMAXCONNSESSION → fail-closed" "grep -qF 'pool ALREADY at the cap' '$WF'"
# (d) 401/403/non-2xx → fail-closed
assert "case (d) non-2xx HTTP (401/403/5xx) → fail-closed" "grep -qF '401/403 = token/scope; 5xx = pooler' '$WF'"
# (e) non-JSON / empty / curl-fail / token-unset → fail-closed (no false 0==0 clean)
assert "case (e1) non-JSON array body → fail-closed" "grep -qF 'body is not a JSON array' '$WF'"
assert "case (e2) curl failure → fail-closed" "grep -qF 'pool unverifiable, refusing to flip' '$WF'"
assert "case (e3) token unset → fail-closed" "grep -qF 'Refusing to flip against an unverifiable pool' '$WF'"
assert "case (e4) non-numeric count → fail-closed" "grep -qF 'inngest-attributable count non-numeric' '$WF'"
# Every non-clean state is a hard exit — >=6 distinct FAIL-CLOSED error paths.
FAILCLOSED_N=$(grep -cF '::error::2.-1 POOL PRE-CHECK FAIL-CLOSED' "$WF" || true)
assert "pre-check has >=6 fail-closed error paths (no silent clean on an unparsed count)" "[[ '$FAILCLOSED_N' -ge 6 ]]"

# ============================================================================
# #6258 (ADR-106) — pre-flight scan bounding: SUM-bounded timeout hierarchy,
# abort→webhook-non-200 mapping, and the tightly-scoped bounded transport retry.
# ============================================================================
INV_SH="$REPO_ROOT/apps/web-platform/infra/inngest-inventory.sh"
DF_SH="$REPO_ROOT/apps/web-platform/infra/inngest-doublefire-probe.sh"

# SUM bound (Deepen Finding 1): in_script_deadline + per_page ≤ outer_curl. The per-page
# clamp makes per_page = (deadline − elapsed) ≤ deadline, so it suffices to assert the
# in-script DEFAULT deadline < the outer curl --max-time for each op. inventory 22 < 30,
# doublefire 50 < 60 — an ordering-only check (deadline < outer) would be met even WITHOUT
# the clamp, so we ALSO assert the remaining-budget clamp exists in each script.
INV_DEADLINE=$(grep -oP 'PREFLIGHT_DEADLINE_S:-\K[0-9]+' "$INV_SH" | head -1)
DF_DEADLINE=$(grep -oP 'PREFLIGHT_DEADLINE_S:-\K[0-9]+' "$DF_SH" | head -1)
assert "inventory in-script deadline (22) < outer curl --max-time 30 (SUM bound)" "[[ -n '$INV_DEADLINE' && '$INV_DEADLINE' -lt 30 ]]"
# #6919 — the doublefire budget was raised (deadline 50→90, outer curl 60→120) + a per-page
# FLOOR added so late pages never starve to ~0s → empty → false "malformed". SUM bound stays
# airtight: deadline(90) + PAGE_MIN(8) = 98 < the 120s outer curl.
DF_PAGE_MIN=$(grep -oP 'PREFLIGHT_PAGE_MIN_S:-\K[0-9]+' "$DF_SH" | head -1)
assert "doublefire in-script deadline (90) < outer curl --max-time 120 (SUM bound, #6919)" "[[ -n '$DF_DEADLINE' && '$DF_DEADLINE' -lt 120 ]]"
assert "doublefire SUM bound airtight: deadline + PAGE_MIN < 120 (#6919)" "[[ -n '$DF_DEADLINE' && -n '$DF_PAGE_MIN' && \$(( DF_DEADLINE + DF_PAGE_MIN )) -lt 120 ]]"
assert "doublefire per-page budget is FLOORED to PREFLIGHT_PAGE_MIN_S (anti-starvation, #6919)" "grep -qE 'max_time < PREFLIGHT_PAGE_MIN_S \)\) && max_time=\\\$PREFLIGHT_PAGE_MIN_S' '$DF_SH'"
assert "inventory clamps per-page curl to the remaining budget (not a fixed const)" "grep -qE 'max-time \"\\\$max_time\"' '$INV_SH' && grep -qE 'remaining=\\\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' '$INV_SH'"
assert "doublefire clamps per-page curl to the remaining budget" "grep -qE 'max-time \"\\\$max_time\"' '$DF_SH' && grep -qE 'remaining=\\\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' '$DF_SH'"
# outer curl budgets present (the ceiling the sum must stay under).
assert "inventory outer curl --max-time 30 present" "grep -qE 'curl --disable --noproxy .\*. -s --max-time 30 -o /tmp/inv-body' '$WF'"
assert "doublefire outer curl --max-time 120 present (#6919)" "grep -qE 'curl --disable --noproxy .\*. -s --max-time 120 -o /tmp/verify-runs' '$WF'"

# ============================================================================
# #6919 — the op=verify HTTP 500 fix's plumbing: the doublefire hook reads a
# ?from= / ?function_ids= query string, and BOTH cutover arms forward a narrower-
# but-still-⊇-invariant window (cutover − 200d > the 182d floor) as the cost lever
# so the wide all-function scan completes within the probe's per-page budget.
# ============================================================================
# Hook side: the two url params bridge into the probe's env seams.
assert "#6919 doublefire hook forwards ?from → INNGEST_DOUBLEFIRE_FROM (pass-environment url)" "grep -qF '\"source\": \"url\", \"name\": \"from\", \"envname\": \"INNGEST_DOUBLEFIRE_FROM\"' '$HOOKS_TMPL'"
assert "#6919 doublefire hook forwards ?function_ids → INNGEST_DOUBLEFIRE_FUNCTION_IDS" "grep -qF '\"name\": \"function_ids\", \"envname\": \"INNGEST_DOUBLEFIRE_FUNCTION_IDS\"' '$HOOKS_TMPL'"
# Workflow side: a shared doublefire_from() computes the ⊇-invariant lower bound, and BOTH the
# op=verify (2.6) and standalone op=doublefire-probe arms forward it as ?from=.
assert "#6919 workflow defines doublefire_from() helper" "grep -qE 'doublefire_from\(\) \{' '$WF'"
assert "#6919 both doublefire calls forward the ?from= window cost lever (2 sites)" "[[ \"\$(grep -cF 'inngest-doublefire-probe?from=' '$WF')\" -eq 2 ]]"
assert "#6919 workflow wires the optional functionIDs cost lever (CUTOVER_DOUBLEFIRE_FUNCTION_IDS)" "grep -qF 'CUTOVER_DOUBLEFIRE_FUNCTION_IDS' '$WF'"
# #6919 review — doublefire_from()'s cutover-instant anchor (and the missed-tick auto-enum) read
# CUTOVER_WINDOW_UNTIL/FROM, which GitHub does not export to the shell unless the step env MAPS
# them. Assert the mapping exists so the anchor branch cannot silently go dead again.
assert "#6919 workflow maps CUTOVER_WINDOW_UNTIL into the step env (doublefire anchor not dead)" "grep -qE 'CUTOVER_WINDOW_UNTIL:\s*\\\$\{\{ vars.CUTOVER_WINDOW_UNTIL \}\}' '$WF'"
assert "#6919 workflow maps CUTOVER_WINDOW_FROM into the step env (missed-tick auto-enum not dead)" "grep -qE 'CUTOVER_WINDOW_FROM:\s*\\\$\{\{ vars.CUTOVER_WINDOW_FROM \}\}' '$WF'"
# INVARIANT (#6178 — RESTATED; this assertion used to require the opposite).
#
# It read: "doublefire_from is >= 200 days ... the TIME window is NEVER narrowed", pinned by
# grepping for the 200-day literals. Measurement retired it: at 728 runs/day a 200-day window
# is ~145,600 runs ~= 1,456 pages against a ~18-page budget, so op=verify could not exhaust it
# and — being fail-loud on non-exhaustion — emitted NO verdict at all. A test demanding an
# unscannable window is a test demanding the bug.
#
# The 182d figure was never the double-fire invariant; it was the FUNCTION-DISCOVERY term (wide
# enough that a quarterly cron appears at least once for the missed-tick loop). Discovery is
# deferred to ADR-146. The double-fire invariant is only:
#     window ⊇ [coexistence_start − 2×cron_period , now]
# which the transition-row anchor satisfies exactly. The per-arm split below is what keeps the
# PRE-cutover dark-host detector wide while letting op=verify narrow.
# ARM-SCOPED, COMMENT-STRIPPED. A file-scoped `grep -q 'doublefire_from 1 fsm'` cannot tell a
# CALL from a COMMENT: reverting op=verify to `doublefire_from 200 wide` while leaving a comment
# that quotes the old call keeps the whole suite green — i.e. the defect this PR exists to remove
# could be reinstated at 291/291. This file is dense with comments quoting these exact call forms,
# so the collision is not hypothetical. Extract each arm, strip comments, assert exact counts.
VERIFY_ARM_FILE="$(mktemp)"; SCRATCH+=("$VERIFY_ARM_FILE")
DFPROBE_ARM_FILE="$(mktemp)"; SCRATCH+=("$DFPROBE_ARM_FILE")
awk '/^            verify\)$/,/^              ;;$/' "$WF" | grep -vE '^[[:space:]]*#' > "$VERIFY_ARM_FILE"
awk '/^            doublefire-probe\)$/,/^              ;;$/' "$WF" | grep -vE '^[[:space:]]*#' > "$DFPROBE_ARM_FILE"
assert "#6178 verify) arm extraction is non-vacuous" "[[ \"\$(wc -l < '$VERIFY_ARM_FILE')\" -gt 40 ]]"
assert "#6178 doublefire-probe) arm extraction is non-vacuous" "[[ \"\$(wc -l < '$DFPROBE_ARM_FILE')\" -gt 20 ]]"
assert "#6178 op=verify calls doublefire_from 1 fsm EXACTLY once (non-comment)" "[[ \"\$(grep -cF 'doublefire_from 1 fsm' '$VERIFY_ARM_FILE')\" -eq 1 ]]"
assert "#6178 op=verify NEVER calls the wide 200d form" "! grep -qF 'doublefire_from 200 wide' '$VERIFY_ARM_FILE'"
assert "#6178 op=doublefire-probe calls doublefire_from 200 wide EXACTLY once (non-comment)" "[[ \"\$(grep -cF 'doublefire_from 200 wide' '$DFPROBE_ARM_FILE')\" -eq 1 ]]"
assert "#6178 op=doublefire-probe NEVER calls the narrowed fsm form" "! grep -qF 'doublefire_from 1 fsm' '$DFPROBE_ARM_FILE'"

# Abort → webhook NON-200 (Deepen Finding 6): a script exit 1 (deadline/ceiling loud-abort)
# maps to a webhook non-200 ONLY IF the hook has include-command-output-in-response-on-error.
# Then the workflow's CODE!=200 cause-branch surfaces the real SOLEUR_*_TIMEOUT text — NOT
# the 200-branch shape guard. Assert BOTH halves of that mapping.
assert "inventory hook returns output on error (exit 1 → non-200)" "grep -A4 '\"id\": \"inngest-inventory\"' '$HOOKS_TMPL' | grep -c 'include-command-output-in-response-on-error.*true' >/dev/null"
assert "doublefire hook returns output on error (exit 1 → non-200)" "grep -A4 '\"id\": \"inngest-doublefire-probe\"' '$HOOKS_TMPL' | grep -c 'include-command-output-in-response-on-error.*true' >/dev/null"
assert "registry-probe hook returns output on error (exit 1 → non-200)" "grep -A4 '\"id\": \"inngest-registry-probe\"' '$HOOKS_TMPL' | grep -c 'include-command-output-in-response-on-error.*true' >/dev/null"
assert "inventory arm surfaces the non-200 CAUSE body via CODE!=200 branch" "grep -qE 'inventory returned HTTP \\\$CODE after 2 attempts' '$WF'"
assert "verify registry-probe arm surfaces the non-200 CAUSE via CODE!=200 branch" "grep -qE 'registry-probe returned HTTP \\\$CODE after 2 attempts' '$WF'"
assert "verify doublefire arm surfaces the non-200 CAUSE via CODE!=200 branch" "grep -qE 'doublefire-probe returned HTTP \\\$CODE after 2 attempts' '$WF'"

# Bounded transport retry (Deepen Finding 11), tightly scoped: 2 attempts on the op=inventory
# curl + the op=verify transport curls, fail-closed. The scoping is load-bearing — it must NOT
# wrap the registry_empty precondition verdict, the DI-C3 gate (:565), or the health probe.
RETRY_N=$(grep -cE 'for attempt in 1 2; do' "$WF" || true)
assert "exactly 3 bounded transport retries (inventory + 2 verify curls)" "[[ '$RETRY_N' -eq 3 ]]"
assert "retry backoff gap present (sleep 5 between attempts)" "grep -qE 'retrying in 5s' '$WF'"
assert "retry fails CLOSED (still-non-200 after 2 attempts exits 1)" "grep -qE 'after 2 attempts' '$WF'"
# NEGATIVE scoping: the DI-C3 execute inventory gate (:565, /tmp/exec-inv) is NOT retried.
assert "DI-C3 execute inventory gate is NOT wrapped in a retry (single-shot)" "! grep -B2 'BASE/inngest-inventory\" || echo \"000\")' '$WF' | grep -c 'exec-inv.*for attempt' >/dev/null"
# The registry_empty VERDICT (registry_empty != false) is downstream of the retry loop, un-retried.
assert "registry_empty verdict is a separate downstream check (not inside the retry loop)" "grep -qE 'verify precondition FAILED' '$WF'"

# ============================================================================
# #6369 — op=arm (the no-SSH arm-flip) + op=rollback reverse flip-write. op=arm is
# FORWARD-ONLY (writes `armed`); the reverse `rollback` write lives in op=rollback
# (ADR-100 Decision 6b forward/reverse symmetry). AC-NOBODY: no source value is EVER echoed,
# every value ::add-mask::'d + written via stdin; the FSM is confirmed via Better Stack.
# Both verbs gate on the inngest-cutover environment (required-reviewer) + a conditional
# DOPPLER_TOKEN_INNGEST_ARM. Extract each case body to a temp file and grep it — asserting
# the awk range is NON-EMPTY first (security F6 — else every range grep passes vacuously).
# ============================================================================
assert "choice includes arm (#6369)" "grep -qE '^[[:space:]]+-[[:space:]]*arm\$' '$WF'"
assert "case arm: arm)" "grep -qE '^[[:space:]]+arm\\)' '$WF'"

ARM_FILE="$(mktemp)"; ROLLBACK_FILE="$(mktemp)"; SCRATCH+=("$ARM_FILE" "$ROLLBACK_FILE")
awk '/^            arm\)$/,/^              ;;$/' "$WF" > "$ARM_FILE"
awk '/^            rollback\)$/,/^              ;;$/' "$WF" > "$ROLLBACK_FILE"
RESUME_FILE="$(mktemp)"; SCRATCH+=("$RESUME_FILE")
awk '/^            resume\)$/,/^              ;;$/' "$WF" > "$RESUME_FILE"
RESUME_N=$(wc -l < "$RESUME_FILE" | tr -d '[:space:]')
assert "#7674 resume) awk range is a real block (non-vacuity for the G3 rows below, got $RESUME_N)" \
  "[[ '$RESUME_N' -gt 10 ]]"
ARM_N=$(wc -l < "$ARM_FILE"); ROLLBACK_N=$(wc -l < "$ROLLBACK_FILE")
# F6 non-vacuity: the arm) awk range must be a real block before any range grep is trusted.
assert "arm) case body is non-empty (>20 lines — F6 non-vacuity)" "[[ '$ARM_N' -gt 20 ]]"
assert "rollback) case body is non-empty (F6 non-vacuity)" "[[ '$ROLLBACK_N' -gt 20 ]]"

# AC6 (AC-NOBODY): no source value is echoed; ::add-mask:: per value; writes via stdin, never argv.
assert "arm) echoes NO source value (AC6/AC-NOBODY)" "! grep -qE 'echo[^\"]*\\\$\\{?(HB|PG|PG_DARK|POSTGRES|HEARTBEAT)' '$ARM_FILE'"
assert "arm) does NOT dump raw Better Stack rows (no 'jq .' — C6 mask bypass)" "! grep -qE 'jq \\.($|[^a-zA-Z_])' '$ARM_FILE'"
assert "arm) has no 'set -x' (would echo masked values — C8)" "! grep -qE 'set -x' '$ARM_FILE'"
ARM_MASK_N=$(grep -cE '::add-mask::' "$ARM_FILE" || true)
assert "arm) masks EACH source value (>=3 ::add-mask:: — PG/HB/PG_DARK, C8/F7)" "[[ '$ARM_MASK_N' -ge 3 ]]"
# stdin form: >=3 `doppler secrets set INNGEST_*` writes, each fed by a `printf` pipe (never NAME=value argv).
ARM_SET_N=$(grep -cE 'doppler secrets set INNGEST_' "$ARM_FILE" || true)
ARM_PRINTF_N=$(grep -cE "printf '%s'" "$ARM_FILE" || true)
assert "arm) performs >=3 doppler secrets set INNGEST_* writes" "[[ '$ARM_SET_N' -ge 3 ]]"
assert "arm) each write is stdin-fed (>=3 printf pipes — AC6 no-argv)" "[[ '$ARM_PRINTF_N' -ge 3 ]]"
assert "arm) NEVER writes a secret on argv (no 'secrets set INNGEST_*=value')" "! grep -qE 'secrets set INNGEST_[A-Z_]+=' '$ARM_FILE'"
assert "arm) writes target the ISOLATED soleur-inngest/prd config" "grep -qE 'doppler secrets set INNGEST_POSTGRES_URI -p soleur-inngest -c prd' '$ARM_FILE'"
# Source reads are read-through from prd_terraform (CTO 6b): no -p/-c on the source get, no seed name.
assert "arm) reads POSTGRES_URI read-through from prd_terraform (no -p/-c on the source get — CTO 6b)" "grep -qE 'doppler secrets get INNGEST_POSTGRES_URI --plain' '$ARM_FILE'"
assert "arm) does NOT reference a dropped operator seed (INNGEST_POSTGRES_URI_PROD)" "! grep -qE 'INNGEST_POSTGRES_URI_PROD' '$ARM_FILE'"

# AC7 write order: armed written AFTER both URIs.
PG_SET_LN=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | head -1 | cut -d: -f1)
FLIP_SET_LN=$(grep -nE 'secrets set INNGEST_CUTOVER_FLIP ' "$ARM_FILE" | head -1 | cut -d: -f1)
assert "arm) writes POSTGRES_URI BEFORE INNGEST_CUTOVER_FLIP=armed (write order AC7)" "[[ -n '$PG_SET_LN' && -n '$FLIP_SET_LN' && '$PG_SET_LN' -lt '$FLIP_SET_LN' ]]"

# AC8 / G3 positive prod-URI assertion + :6543 reject; G1 pre-write FSM-state guard (DI-C2).
# NOTE (#7462): the pooler-port PREDICATES moved into g3_decide, so grepping $ARM_FILE for
# ':6543'/':5432' now matches only the error-MESSAGE strings — it would pass with the
# predicates deleted. Behavioural coverage is the g3_decide block below (scenarios 2 and 3).
# What remains assertable here is that the arm still SURFACES the pooler remediation.
assert "arm) surfaces the :6543 transaction-pooler remediation to the operator" "grep -qE '::error::.*:6543 transaction pooler' '$ARM_FILE'"
assert "arm) names the :5432 session pooler in that remediation" "grep -qE '::error::.*:5432 session pooler' '$ARM_FILE'"
# #7462: prod == dark is a SKIP, not a refusal. The old assertion here grepped for
# `PG.*==.*PG_DARK` in the arm body — a comparison that has since moved into g3_decide, and
# which could not have distinguished a refusal from a skip even while it was present. The
# behavioural coverage is the g3_decide block further down; these assert the CONSUMER wiring.
assert "arm) has an idempotent skip arm (not a refusal) for already-current" "grep -qF 'skip-already-current' '$ARM_FILE'"
assert "arm) no longer claims an already-current value 'would flip onto the DARK backend'" "! grep -qF 'would flip onto the DARK backend' '$ARM_FILE'"

# AC6/AC7 (#7462 review). An earlier revision branched the G4 DSN write on the G3 outcome and
# asserted that branch with PRESENCE greps — which pass identically with the writes moved
# inside the guard, i.e. they could not fail. Three mutations went uncaught, one of which
# skipped the write on the FIRST-arm transition and armed the host onto the dark backend with
# the suite green. The branch is gone: all three prod writes are unconditional, which is the
# property to pin, and it is pinnable by ABSENCE rather than by position.
assert "arm) the G3-outcome skip flag is GONE (no conditional around a prod write)" "! grep -qE 'G3_SKIP_PG_WRITE' '$ARM_FILE'"
assert "arm) no same-line short-circuit gates a prod write" "! grep -qE '(&&|\\|\\|)[^|]*\\| DOPPLER_TOKEN=' '$ARM_FILE'"
# The three prod secret writes must sit at ONE indent depth, and there must be exactly three
# of them. Depth alone is degenerate at a single match (deleting two writes leaves one depth,
# which would pass), so the COUNT is asserted alongside it — together they fail on both the
# "conditionally nested" and the "silently dropped" mutation classes without needing a command
# seam. Anchored on the `| DOPPLER_TOKEN=` pipe, which a comment cannot emit. The whitespace
# class is [[:space:]] in the grep and must match the strip, so tabs are handled identically.
G4_WRITE_LINES=$(grep -cE '^[[:space:]]+(printf|echo)[^|]*\| DOPPLER_TOKEN=' "$ARM_FILE" || true)
G4_WRITE_DEPTHS=$(grep -oE '^[[:space:]]+(printf|echo)[^|]*\| DOPPLER_TOKEN=' "$ARM_FILE" | sed -E 's/[^[:space:]].*//' | awk '{print length}' | sort -u | wc -l) || true
assert "arm) exactly three prod secret writes remain (URI, heartbeat, flag)" "[[ '$G4_WRITE_LINES' -eq 3 ]]"
# Indent depth and token-absence are both defeated by an if/else that keeps the write at the same
# column (bash ignores indentation), which is the catastrophic mutation: `if [[ $G3_OUTCOME ==
# write ]]; then :; else <write>; fi` skips the DSN write on the FIRST-arm transition, so the host
# boots against the dark backend and the job exits 0. Measured: it satisfied every other assertion
# here. Pin the REGION instead — from the first prod write to the `armed` write there must be no
# branching at all, because all three writes are unconditional by design.
W_START=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
W_END=$(grep -nF "printf '%s' 'armed'" "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
W_BRANCH=$(awk -v a="$W_START" -v b="$W_END" 'NR>=a && NR<=b' "$ARM_FILE" | grep -cE '^[[:space:]]*(if|else|elif|fi)\b' || true)
assert "arm) the prod-write region is non-empty (F6 non-vacuity)" "[[ -n '$W_START' && -n '$W_END' && '$W_END' -gt '$W_START' ]]"
assert "arm) NO branching between the first prod write and the armed write" "[[ '$W_BRANCH' -eq 0 ]]"
assert "arm) all prod secret writes sit at one indent depth (none conditionally nested)" "[[ '$G4_WRITE_DEPTHS' -eq 1 ]]"
assert "arm) G1 reads the current INNGEST_CUTOVER_FLIP from soleur-inngest (pre-write state guard)" "grep -qE 'doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest' '$ARM_FILE'"
assert "arm) G1 refuses re-arm over a non-safe FSM state (DI-C2 REFUSING)" "grep -qE 'G1 REFUSING' '$ARM_FILE'"

# AC9 FSM confirm — the confirm logic is the SHARED confirm_flip_state() function (used by op=arm G6
# AND op=rollback). Extract it and assert it keys on the emitter's `flag` field, NOT `reason`: the
# on-host emitter (apps/web-platform/infra/inngest-cutover-flip.sh `emit_state exit_code dbsize reason
# flag`) puts the TERMINAL STATE in `flag` (done/aborted/rolled-back) and a CAUSE in `reason` (which
# NEVER equals done/aborted). A confirm keyed on `"reason":"done"` would match no row → every op=arm
# times out. This block is the cross-file parity that stops that silent drift.
CONFIRM_FILE="$(mktemp)"; SCRATCH+=("$CONFIRM_FILE")
awk '/^          confirm_flip_state\(\) \{$/,/^          \}$/' "$WF" > "$CONFIRM_FILE"
CONFIRM_N=$(wc -l < "$CONFIRM_FILE")
assert "confirm_flip_state() is defined + non-empty (F6 non-vacuity)" "[[ '$CONFIRM_N' -gt 5 ]]"
assert "confirm keys on the emitter FLAG field (\"flag\":\"done\" + exit_code:0 — NOT reason)" "grep -qF '\"flag\":\"done\"' '$CONFIRM_FILE' && grep -qF '\"exit_code\":0' '$CONFIRM_FILE'"
assert "confirm does NOT key on \"reason\":\"done\" (the field-mismatch bug the review caught)" "! grep -qF '\"reason\":\"done\"' '$CONFIRM_FILE'"
assert "confirm detects the aborted terminal flag (fail-loud path)" "grep -qF '\"flag\":\"aborted\"' '$CONFIRM_FILE'"
assert "confirm detects the rolled-back terminal flag" "grep -qF '\"flag\":\"rolled-back\"' '$CONFIRM_FILE'"
# #7674: the query itself moved into the shared _bs_query_rows helper (one reader, two
# callers). The no-SSH / no-deploy-status invariant is asserted on the HELPER below; what is
# assertable HERE is that confirm still routes through it rather than growing a second reader.
assert "confirm reads through the shared _bs_query_rows helper (no second reader)" "grep -qE '_bs_query_rows ' '$CONFIRM_FILE' && ! grep -qE 'deploy-status' '$CONFIRM_FILE'"
assert "confirm never dumps a raw Better Stack row (no 'jq .')" "! grep -qE 'jq \\.($|[^a-zA-Z_])' '$CONFIRM_FILE'"
assert "confirm distinguishes a query-path failure from FSM-not-terminal (::warning:: CONFIRM PATH)" "grep -qE 'CONFIRM PATH' '$CONFIRM_FILE'"
# Emitter parity: the on-host emitter MUST actually stamp the flag states the confirm greps for.
EMITTER="$REPO_ROOT/apps/web-platform/infra/inngest-cutover-flip.sh"
assert "emitter stamps flag 'done' (the confirm's success key) + an aborted path" "grep -qF 'flag_set \"done\"' '$EMITTER' && grep -qF 'aborted' '$EMITTER'"

# op=arm calls the shared confirm with a SPACE-form timestamp (the reader has normalised ISO T/Z to this
# form since #7761, but the space form stays the arm's contract — the P2 that once false-negatived it).
assert "arm) calls confirm_flip_state (AC9)" "grep -qF 'confirm_flip_state \"\$ARM_ISO\"' '$ARM_FILE'"
assert "arm) time-bounds via a SPACE-form timestamp, no ISO T/Z (the --since format P2)" "grep -qF \"+'%Y-%m-%d %H:%M:%S'\" '$ARM_FILE' && ! grep -qE 'ARM_ISO=.*T%H.*Z' '$ARM_FILE'"
assert "arm) branches on the confirm result (done vs aborted/rolled-back vs timeout, fail-loud)" "grep -qF 'G6_STATE' '$ARM_FILE'"
# NOTE (#7462): this used to grep $ARM_FILE for the bare prod ref. The pin moved into
# g3_decide, which is OUTSIDE $ARM_FILE, so the only surviving occurrence there is the
# refuse-not-prod-project error MESSAGE — deleting the pin entirely left this green. It is
# the third assertion invalidated by that move (see the :6543/:5432 note above) and the one
# guarding what the ADR calls the sole guard against arming onto a non-prod Postgres.
# Behavioural coverage is the g3_decide block below; what is assertable here is the message.
assert "arm) surfaces the prod-project-ref remediation to the operator" "grep -qE '::error::.*ref pigsfuxruiopinouvjwy' '$ARM_FILE'"
# And the pin itself is asserted where it actually lives, anchored on the case-arm shape a
# comment or an error string cannot produce.
# The pin is asserted where it lives, anchored on the authority-EXTRACTION shape a comment or an
# error string cannot produce. Behavioural coverage is the g3_case rows below; these pin that the
# implementation still parses rather than globbing (a glob over the whole DSN cannot express
# "the authority is X", which is how three earlier revisions were defeated).
assert "g3_decide extracts the authority before matching it" "grep -qF '_auth=\"\${_rest%%/*}\"' '$BODY_SH'"
assert "g3_decide matches host:port WHOLE, not by globbing the DSN" "grep -qE '^[[:space:]]+\\*\\.pooler\\.supabase\\.com:5432\\)' '$BODY_SH'"
assert "g3_decide rejects connection-parameter overrides case-insensitively" "grep -qE '\\*host=\\*\\|\\*host%3d\\*' '$BODY_SH'"
assert "g3_decide requires exactly one '@' inside the AUTHORITY" "grep -qF 'if [[ \"\${_auth//[!@]/}\" != \"@\" ]]' '$BODY_SH'"
assert "arm) G1 fail-CLOSED: probes config readability (DOPPLER_PROJECT) before trusting an empty flip" "grep -qF 'config-readability probe failed' '$ARM_FILE' && grep -qE 'doppler secrets get DOPPLER_PROJECT -p soleur-inngest' '$ARM_FILE'"
assert "arm) G3 fail-CLOSED on an empty PG_DARK read (no silent equality-pass)" "grep -qF 'could not read the current dark INNGEST_POSTGRES_URI' '$ARM_FILE'"
assert "arm) adds NO deploy-status poll (Better Stack read only — QMAX/RMAX untouched, AC9)" "! grep -qE 'deploy-status' '$ARM_FILE'"

# AC13 no ssh in the arm block.
assert "arm) contains no ssh (AC-NOSSH/AC13)" "! grep -qE '(^|[^[:alnum:]])ssh[[:space:]]' '$ARM_FILE'"

# ============================================================================
# #7462 — G3 DECISION FUNCTION (g3_decide): BEHAVIOURAL tests, not source-greps.
#
# Every other assertion in this file greps the script TEXT, which is structurally blind
# to a change in WHICH BRANCH the decision takes. The pre-#7462 assertion
# `grep -qE 'PG.*==.*PG_DARK'` still matches after the equality arm was inverted from a
# refusal into a skip — it cannot see this change at all. These tests EXECUTE the
# decision instead, so a mutation of any arm reddens the suite.
#
# The function is extracted from the REAL script ($BODY_SH) and sourced — never
# re-declared inline, or the suite would assert a known-good snippet is known-good while
# the shipped file regressed underneath it.
# ============================================================================
# The extraction is an awk range over the REAL script, so it is coupled to g3_decide's
# signature and closing brace both sitting at column 0. A truncated-but-parseable extraction
# fails the scenarios loudly and an empty one fails `declare -F` below, so this fails safe.
G3_FN="$(mktemp)"; SCRATCH+=("$G3_FN")
awk '/^g3_decide\(\) \{$/,/^\}$/' "$BODY_SH" > "$G3_FN"

# shellcheck disable=SC1090
. "$G3_FN"
assert "g3_decide() is defined after sourcing" "declare -F g3_decide >/dev/null"

# Synthesized fixtures ONLY (cq-test-fixtures-synthesized-only) — no real password or host.
# The project refs are public Supabase project identifiers, not secrets, and are the values
# the guard actually pins on.
G3_PROD_REF="pigsfuxruiopinouvjwy"
G3_DEV_REF="mlwiodleouzwniehynfz"
G3_PROD="postgresql://postgres.${G3_PROD_REF}:synth-pw-a@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"
G3_PROD_ALT="postgresql://postgres.${G3_PROD_REF}:synth-pw-b@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"
G3_PROD_TXN="postgresql://postgres.${G3_PROD_REF}:synth-pw-a@aws-0-eu-west-1.pooler.supabase.com:6543/postgres"
G3_PROD_NOPORT="postgresql://postgres.${G3_PROD_REF}:synth-pw-a@aws-0-eu-west-1.pooler.supabase.com/postgres"
G3_DEV="postgresql://postgres.${G3_DEV_REF}:synth-pw-c@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"

G3_EVALS=0
g3_case() { # $1 desc, $2 PG (to write), $3 PG_DARK (in place), $4 expected outcome
  local got
  got="$(g3_decide "$2" "$3")"
  G3_EVALS=$((G3_EVALS + 1))
  assert "g3_decide: $1 -> $4" "[[ '$got' == '$4' ]]"
}
# The eval counter and its assert are adjacent lines in one function, so a one-line excision of
# the assert leaves the counter satisfied while every row stops being checked (measured: 357
# passed / 0 failed / exit 0). Snapshot the verdict counters instead and require a real delta.
G3_VERDICTS_BEFORE=$((PASS + FAIL))

# HARNESS CANARY. Two measured mutations defeated every floor above: replacing g3_case's body with
# `got="$4"` (every row then asserts the fixture table against itself) and deleting only its
# assert line while keeping the counter increment. Both leave the suite green because the counters
# they feed do not distinguish "compared against the SUT" from "compared against nothing". So
# drive one row whose expectation is deliberately WRONG and require it to FAIL: a tautological or
# assert-less g3_case cannot produce that failure.
_HC_F=$FAIL
g3_case "harness canary: a deliberately wrong expectation MUST fail (expected FAIL below)" "$G3_PROD" "$G3_PROD" "write"
if [[ "$FAIL" -ne $((_HC_F + 1)) ]]; then
  echo "  FATAL: g3_case does not compare against g3_decide — every g3_decide row in this file is void."
  exit 2
fi
FAIL=$((FAIL - 1)); G3_EVALS=$((G3_EVALS - 1))
echo "  (g3_case harness canary OK — deliberate FAIL above is expected and subtracted)"

g3_case "empty dark value fails closed"            "$G3_PROD"        ""               "refuse-empty-dark"
g3_case "rejects the :6543 transaction pooler"     "$G3_PROD_TXN"    "$G3_PROD"       "refuse-txn-pooler"
g3_case "requires the :5432 session pooler"        "$G3_PROD_NOPORT" "$G3_PROD"       "refuse-not-session-pooler"
g3_case "refuses a non-prod project ref"           "$G3_DEV"         "$G3_DEV"        "refuse-not-prod-project"
g3_case "already-current is a SKIP, not a refusal" "$G3_PROD"        "$G3_PROD"       "skip-already-current"
g3_case "dark -> prod is the first-arm write"      "$G3_PROD"        "$G3_DEV"        "write"
g3_case "a DIFFERENT prod-project value writes"    "$G3_PROD"        "$G3_PROD_ALT"   "write"
# The pin is the SOLE guard against a non-prod target, so every row below is a must-REFUSE on
# an axis some weaker form of the pin waved through. All twelve were MEASURED against two
# earlier revisions of this guard and returned `write` (i.e. armed onto the wrong Postgres):
# a bare `*<ref>*` substring accepted the ref anywhere in the value, and pinning only the
# pooler USERNAME accepted the prod username in front of any host. Keep these rows: they are
# the difference between pinning a string and pinning a destination.
G3_H='aws-0-eu-west-1.pooler.supabase.com'
g3_case "refuses prod user @ attacker host"        "postgresql://postgres.${G3_PROD_REF}:pw@attacker.example.com:5432/postgres"  "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses prod user @ raw IPv4"             "postgresql://postgres.${G3_PROD_REF}:pw@203.0.113.9:5432/postgres"           "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses prod user @ IPv6 literal"         "postgresql://postgres.${G3_PROD_REF}:pw@[2001:db8::1]:5432/postgres"         "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses prod user @ the DEV project host" "postgresql://postgres.${G3_PROD_REF}:pw@db.${G3_DEV_REF}.supabase.co:5432/postgres" "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses a host= connection-param override" "postgresql://postgres.${G3_PROD_REF}:pw@${G3_H}:5432/postgres?host=attacker.example.com" "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses a host= unix-socket override"     "postgresql://postgres.${G3_PROD_REF}:pw@${G3_H}:5432/postgres?host=/tmp"     "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses a multi-host list"                "postgresql://postgres.${G3_PROD_REF}:pw@attacker.example.com:5432,${G3_H}:5432/postgres" "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses the prod ref smuggled in a query param"  "postgresql://postgres.${G3_DEV_REF}:pw@${G3_H}:5432/postgres?application_name=x://postgres.${G3_PROD_REF}:y" "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses the prod ref smuggled as @db.<ref>. in a param" "postgresql://postgres.${G3_DEV_REF}:pw@${G3_H}:5432/postgres?fallback_application_name=@db.${G3_PROD_REF}.z" "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses db.<ref>. as an attacker SUBDOMAIN"  "postgresql://u:pw@db.${G3_PROD_REF}.attacker.example.com:5432/postgres"   "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses a second '@' relocating the host"    "postgresql://u:p@db.${G3_PROD_REF}.x@attacker.example.com:5432/postgres"  "$G3_PROD" "refuse-not-prod-project"
g3_case "refuses :5432 present but not the authority port" "postgresql://postgres.${G3_PROD_REF}:pw@attacker.example.com:15432/postgres?application_name=a:5432" "$G3_PROD" "refuse-not-prod-project"

# G3's terminal action. Previously each refusal arm carried its own `exit 1` and nothing tested
# that a refusal aborts: stripping all four turned G3 into a logger that fell through to the prod
# write, at 381/0 green. The decision now lives in g3_action and is driven here.
ACT_FN="$(mktemp)"; SCRATCH+=("$ACT_FN")
awk '/^g3_action\(\) \{$/,/^\}$/' "$BODY_SH" > "$ACT_FN"
# shellcheck disable=SC1090
. "$ACT_FN"
assert "g3_action() is defined after sourcing" "declare -F g3_action >/dev/null"
ACT_EVALS=0
act_case() { local got; got="$(g3_action "$2")"; ACT_EVALS=$((ACT_EVALS + 1)); assert "g3_action: $1 -> $3" "[[ '$got' == '$3' ]]"; }
act_case "refuse-empty-dark aborts"          "refuse-empty-dark"         "abort"
act_case "refuse-txn-pooler aborts"          "refuse-txn-pooler"         "abort"
act_case "refuse-not-session-pooler aborts"  "refuse-not-session-pooler" "abort"
act_case "refuse-not-prod-project aborts"    "refuse-not-prod-project"   "abort"
act_case "skip-already-current proceeds"     "skip-already-current"      "proceed"
act_case "write proceeds"                    "write"                     "proceed"
act_case "an unknown token aborts (fail-closed)" "some-future-token"     "abort"
assert "g3_action scenarios actually dispatched (>=7)" "[[ '$ACT_EVALS' -ge 7 ]]"
# One abort gate, routed through the tested function, sitting before the first prod write.
assert "arm) has exactly one G3 abort gate routed through g3_action" "[[ \$(grep -cF 'if [[ \"\$(g3_action \"\$G3_OUTCOME\")\" == \"abort\" ]]; then exit 1; fi' '$ARM_FILE') -eq 1 ]]"
assert "arm) no G3 outcome arm carries its own exit (the gate decides)" "! grep -qE '^[[:space:]]+(refuse|skip|write)[a-z-]*\)[^#]*exit 1' '$ARM_FILE'"
G3ABORT_LN=$(grep -nF 'g3_action "$G3_OUTCOME"' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
G3ABORT_PGW=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
assert "arm) the G3 abort gate precedes the first prod write" "[[ -n '$G3ABORT_LN' && -n '$G3ABORT_PGW' && '$G3ABORT_LN' -lt '$G3ABORT_PGW' ]]"

# G3.6's decision, driven the same way. Greps over the arm body could not see this: adding
# '1' to the pass-arm (i.e. arming WHILE the diagnostic flag is set — the exact catastrophe
# the gate exists to prevent) left the suite green, because every message string survived.
DIAG_FN="$(mktemp)"; SCRATCH+=("$DIAG_FN")
awk '/^diag_boot_decide\(\) \{$/,/^\}$/' "$BODY_SH" > "$DIAG_FN"
# shellcheck disable=SC1090
. "$DIAG_FN"
assert "diag_boot_decide() is defined after sourcing" "declare -F diag_boot_decide >/dev/null"
DIAG_EVALS=0
diag_case() { # $1 desc, $2 raw value, $3 expected outcome
  local got; got="$(diag_boot_decide "$2")"
  DIAG_EVALS=$((DIAG_EVALS + 1))
  assert "diag_boot_decide: $1 -> $3" "[[ '$got' == '$3' ]]"
}
diag_case "unset is clear"                ""                "clear"
diag_case "'0' is clear"                  "0"               "clear"
diag_case "'false' is clear"              "false"           "clear"
diag_case "'1' is SET — must refuse"      "1"               "set"
diag_case "'true' is SET — must refuse"   "true"            "set"
diag_case "any other value is SET (fail-closed)" "yes"      "set"
diag_case "an unreadable read fails closed" "__UNREADABLE__" "unreadable"
assert "diag_boot_decide scenarios actually dispatched (>=7)" "[[ '$DIAG_EVALS' -ge 7 ]]"
assert "arm) routes G3.6 through diag_boot_decide (single chokepoint)" "grep -qE 'case \"\\\$\\(diag_boot_decide ' '$ARM_FILE'"

# ============================================================================
# #7462 review — G3.7 PRE-FLUSH-LATCH GATE. Behavioural, not grepped.
#
# WHY THIS GATE EXISTS. Making op=arm idempotent (this PR) removed the only thing that
# stopped a re-arm of an already-flushed host from running to completion. Such an arm is
# DOOMED — the monotonic latch on /mnt/data refuses it on-host and drives the flag to
# terminal `aborted` — but before it does, G4 has written both prod secrets and G5 has
# written `armed`, a value INSIDE inngest-server-flip-guard.sh's prod-start allowlist
# {armed,flipping,flushed,done}, while op=rollback has already re-enabled the co-located
# web schedulers. A reboot in that ~30-60s window starts a SECOND prod scheduler.
# G3.7 refuses the doomed arm BEFORE any write, closing that window at its source.
#
# Three independent axes are driven below, because each is blind to the others' defects:
#   (a) the DECISION (flush_latch_decide) — a pure token mapping;
#   (b) the READER (_flush_latch_count) EXECUTED against a stubbed `doppler`, including
#       its argv, so a reader that queries the WRONG thing is detectable;
#   (c) the ASSEMBLY — that the gate is wired into arm) ahead of the first prod write,
#       and that the remediation its message names is actually reachable by an operator.
# ============================================================================

FL_FN="$(mktemp)"; SCRATCH+=("$FL_FN")
awk '/^flush_latch_decide\(\) \{$/,/^\}$/' "$BODY_SH" > "$FL_FN"
FL_FN_N=$(wc -l < "$FL_FN" | tr -d '[:space:]')
# Harness self-check FIRST — an empty extraction makes every row below vacuous.
assert "#7462 flush_latch_decide extraction is non-vacuous (>3 lines, got $FL_FN_N)" "[[ '$FL_FN_N' -gt 3 ]]"
# shellcheck disable=SC1090
. "$FL_FN"
assert "flush_latch_decide() is defined after sourcing" "declare -F flush_latch_decide >/dev/null"
FL_EVALS=0
fl_case() { # $1 desc, $2 L (latch count), $3 H (liveness count), $4 expected outcome
  local got; got="$(flush_latch_decide "$2" "$3")"
  FL_EVALS=$((FL_EVALS + 1))
  assert "flush_latch_decide: $1 (L=$2,H=$3) -> $4" "[[ '$got' == '$4' ]]"
}
# THE TWO-SIGNAL TABLE (#7674). L alone cannot distinguish "no flush has happened" from
# "I cannot tell": measured 2026-08-25, G3.7's query returns 0 rows at 7d, 30d AND 365d while
# the host emits ~1.4 flip rows/min, so L=0 was reporting coverage the gate did not have.
# H — any inngest-cutover-flip row from THIS host inside a short window — is the host's own
# liveness witness, and (L=0,H=0) is now `silent`: absence proves nothing when the witness is
# also absent. Both non-decimal arms route to `unreadable`, never `silent`, because a
# non-decimal count is produced ONLY by a query failure and `silent` prints the host-dark
# remediation — the mis-remediation the outcome split exists to prevent.
fl_case "no latch + host reporting is clear — a genuine first arm proceeds" "0"  "20"  "clear"
fl_case "no latch + host SILENT refuses — absence proves nothing"           "0"  "0"   "silent"
fl_case "one latch row is LATCHED — must refuse"                            "1"  "20"  "latched"
fl_case "many latch rows is LATCHED"                                        "12" "20"  "latched"
fl_case "LATCHED even when the host is silent (L dominates)"                "1"  "0"   "latched"
# L's VALUE is decisive BEFORE H is consulted. Without this row the "L dominates H" claim was only
# tested against H=0, and (L>=1, H unreadable) printed the CREDENTIAL remediation for a state where
# a latch had actually been detected.
fl_case "LATCHED even when H is UNREADABLE (L dominates, not just over silence)" "1" "__UNREADABLE__" "latched"
fl_case "LATCHED even when H is non-numeric"                               "12" "n/a" "latched"
fl_case "an unreadable latch read fails closed"           "__UNREADABLE__"  "20"  "unreadable"
fl_case "an empty latch count fails closed"               ""                "20"  "unreadable"
fl_case "a non-numeric latch count fails closed"          "n/a"             "20"  "unreadable"
fl_case "a negative latch count fails closed"             "-1"              "20"  "unreadable"
fl_case "a latch count with whitespace fails closed"      " 1"              "20"  "unreadable"
fl_case "an unreadable LIVENESS read is unreadable, NOT silent" "0" "__UNREADABLE__" "unreadable"
fl_case "an empty liveness count is unreadable, NOT silent"     "0" ""               "unreadable"
fl_case "a non-numeric liveness count is unreadable, NOT silent" "0" "n/a"           "unreadable"
fl_case "a negative liveness count is unreadable, NOT silent"    "0" "-1"            "unreadable"
fl_case "a non-decimal L wins over a non-decimal H (both unreadable)" "x" "y"        "unreadable"
assert "flush_latch_decide scenarios actually dispatched (>=15)" "[[ '$FL_EVALS' -ge 15 ]]"
# HARNESS CANARY, mirroring g3_case's. A fl_case whose body stopped comparing against the real
# function would report every row above as a PASS; prove it can FAIL, then subtract.
_FL_P=$PASS; _FL_F=$FAIL
fl_case "harness canary: a deliberately wrong expectation MUST fail (expected FAIL below)" "0" "20" "latched"
if [[ "$FAIL" -ne $((_FL_F + 1)) || "$PASS" -ne "$_FL_P" ]]; then
  echo "  FATAL: fl_case does not compare against flush_latch_decide — every G3.7 decision row is void."
  exit 2
fi
FAIL=$((FAIL - 1))
echo "  (fl_case harness canary OK — deliberate FAIL above is expected and subtracted)"

# --- (b) THE READER, EXECUTED. -------------------------------------------------------------
# A gate is only as good as the question its reader asks. Stubbing `doppler` on the PRESENCE of a
# call would leave the query shape unpinned: a reader that dropped the --grep terms would match
# the ~2,880 noop-* heartbeat rows/day and report LATCHED forever, and one that dropped --since
# would silently change the window. The stub therefore RECORDS its argv and the argv is asserted.
FLC_FN="$(mktemp)"; SCRATCH+=("$FLC_FN")
awk '/^_flush_latch_count\(\) \{$/,/^\}$/' "$BODY_SH" > "$FLC_FN"
FLC_FN_N=$(wc -l < "$FLC_FN" | tr -d '[:space:]')
assert "#7462 _flush_latch_count extraction is non-vacuous (>5 lines, got $FLC_FN_N)" "[[ '$FLC_FN_N' -gt 5 ]]"
assert "#7462 extraction actually yields a callable _flush_latch_count" \
  "bash -c 'eval \"\$(cat \"$FLC_FN\")\"; declare -F _flush_latch_count >/dev/null'"

FL_ARGV="$(mktemp)"; SCRATCH+=("$FL_ARGV")
FL_CURL_CALLS="$(mktemp)"; SCRATCH+=("$FL_CURL_CALLS")
FLC_OUT=""; FLC_RC=0
call_flush_latch_count() { # $1 = rows | empty | fail
  local mode="$1"
  set +e
  FLC_OUT=$(
    eval "$(cat "$FLC_FN")"
    # Stub the ONLY external command the reader runs. Defined AFTER the eval so it wins.
    # shellcheck disable=SC2317  # invoked indirectly, by the _flush_latch_count eval'd above
    doppler() {
      printf '%s\n' "$*" > "$FL_ARGV"
      case "$mode" in
        rows)
          printf '%s\n' '{"dt":"2026-07-24 10:20:51.000000","raw":"r1"}'
          printf '%s\n' '{"dt":"2026-07-24 10:20:52.000000","raw":"r2"}'
          return 0 ;;
        empty) return 0 ;;
        *)     return 7 ;;
      esac
    }
    eval "$(cat "$GEN_FN")"
    # The latch is deliberately NOT generation-floored; if it ever reached the Hetzner anchor
    # this stub records it and fails, so no mutant can reach the real api.hetzner.cloud.
    # shellcheck disable=SC2317
    curl() { echo called >> "$FL_CURL_CALLS"; exit 99; }
    export FLUSH_LATCH_SINCE="365d"
    _flush_latch_count 2>/dev/null
  )
  FLC_RC=$?
  set -e
}

call_flush_latch_count rows
assert "#7462 reader counts matching rows (2 rows -> '2', got '$FLC_OUT')" "[[ '$FLC_OUT' == '2' ]]"
assert "#7462 reader always returns 0 so the DECISION owns the verdict (rc=$FLC_RC)" "[[ '$FLC_RC' -eq 0 ]]"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
FLC_ARGV_SEEN="$(cat "$FL_ARGV")"
# ARGV FIDELITY. Each of these is a way the gate could be silently defeated while still "working".
assert "#7462 reader queries via prd_terraform (the betterstack-query cred config)" \
  "grep -qF -- '-c prd_terraform' <<<\"\$FLC_ARGV_SEEN\""
assert "#7462 reader invokes betterstack-query.sh (no SSH, no new transport)" \
  "grep -qF -- 'scripts/betterstack-query.sh' <<<\"\$FLC_ARGV_SEEN\""
assert "#7462 reader bounds the window with --since \$FLUSH_LATCH_SINCE" \
  "grep -qF -- '--since 365d' <<<\"\$FLC_ARGV_SEEN\""
assert "#7462 reader greps the flip-complete reason (QUOTED form)" \
  "grep -qF -- '--grep \"reason\":\"flip-complete\"' <<<\"\$FLC_ARGV_SEEN\""
assert "#7462 reader greps the refuse-rearm-after-done reason (QUOTED form)" \
  "grep -qF -- '--grep \"reason\":\"refuse-rearm-after-done\"' <<<\"\$FLC_ARGV_SEEN\""
# The heartbeat firehose must NOT be in the query — matching it would pin the gate at LATCHED.
assert "#7462 reader does NOT grep the noop-* heartbeat reasons" \
  "! grep -qE '\"reason\":\"noop' <<<\"\$FLC_ARGV_SEEN\""

call_flush_latch_count empty
assert "#7462 an empty result is '0' (clear), not an error" "[[ '$FLC_OUT' == '0' ]]"
call_flush_latch_count fail
assert "#7462 a FAILED query yields __UNREADABLE__, never 0 (fail-closed)" "[[ '$FLC_OUT' == '__UNREADABLE__' ]]"

# The reader must never echo a raw Better Stack row — the standing purity contract of every
# Better Stack reader in this script (a value could ride along in `.raw`).
assert "#7462 reader extracts a COUNT only (no .raw, no jq over row bodies)" \
  "! grep -qE '\\.raw|\\.message' '$FLC_FN'"

# The window constant must carry an env-overridable default — a hardcoded literal makes the
# error message's remediation unperformable (the #6617 dead-remediation class).
assert "#7462 FLUSH_LATCH_SINCE is env-overridable with a default" \
  "grep -qE '^FLUSH_LATCH_SINCE=\"\\\$\\{FLUSH_LATCH_SINCE:-[0-9]+[a-z]\\}\"' '$BODY_SH'"

# --- (b2) THE LIVENESS READER (#7674), EXECUTED. ---------------------------------------------
# H is the signal that turns G3.7's `clear` from "no evidence" into "no evidence, from a host we
# can hear". Three ways it could be silently defeated, each asserted below:
#   1. counting on an enumerated `reason` set instead of the TAG — the catch-all arm emits
#      `noop-unset`, and that is the arm that fires in the very state G3.7 gates, so an
#      enumeration would read H=0 on a healthy host and refuse every legitimate first arm;
#   2. no host isolation — vector.toml: ALL hosts multiplex into ONE Logs source with host_name
#      the sole discriminator, so web-1's rows would count as the dedicated host's liveness;
#   3. matching the host on the OUTER row — `raw` is DOUBLE-ENCODED, so a literal
#      `"host_name":"..."` grep against the outer line matches NOTHING, EVER, which would pin
#      H at 0 and refuse every arm. The reader must decode before it matches.
FLV_FN="$(mktemp)"; SCRATCH+=("$FLV_FN")
awk '/^_flip_liveness_count\(\) \{$/,/^\}$/' "$BODY_SH" > "$FLV_FN"
FLV_FN_N=$(wc -l < "$FLV_FN" | tr -d '[:space:]')
assert "#7674 _flip_liveness_count extraction is non-vacuous (>5 lines, got $FLV_FN_N)" "[[ '$FLV_FN_N' -gt 5 ]]"

FLQ_FN="$(mktemp)"; SCRATCH+=("$FLQ_FN")
awk '/^_bs_query_rows\(\) \{$/,/^\}$/' "$BODY_SH" > "$FLQ_FN"
FLQ_FN_N=$(wc -l < "$FLQ_FN" | tr -d '[:space:]')
assert "#7674 _bs_query_rows extraction is non-vacuous (>3 lines, got $FLQ_FN_N)" "[[ '$FLQ_FN_N' -gt 3 ]]"
# The no-SSH invariant, migrated here from confirm_flip_state when the reader was extracted.
assert "#7674 the shared reader queries via betterstack-query.sh (no SSH, no new transport)" \
  "grep -qE 'betterstack-query.sh' '$FLQ_FN' && ! grep -qE 'deploy-status' '$FLQ_FN'"
assert "#7674 the shared reader queries via prd_terraform (the betterstack-query cred config)" \
  "grep -qF -- '-c prd_terraform' '$FLQ_FN'"

# --- GENERATION FIXTURES (2026-09-24 host-replace class). -------------------------------------
# Every liveness row now carries the two clocks the generation floor reads: the host's own event
# time (journald `__REALTIME_TIMESTAMP`, µs, inside the double-encoded `.raw`) and Better Stack's
# ingest time (`dt`). The mocked Hetzner `created` is ONE synthetic `+00:00` string, relative to
# the wall clock so the young/old and future bounds hold on any runner, and the floor is DERIVED
# from it here exactly once — never written twice as a literal.
FIX_NOW=$(date -u +%s)
FIX_CREATED_EPOCH=$(( (FIX_NOW - 7200) / 60 * 60 ))
FIX_CREATED="$(date -u -d "@$FIX_CREATED_EPOCH" '+%Y-%m-%dT%H:%M:%S+00:00')"
FIX_FLOOR="$(jq -rn --arg c "$FIX_CREATED" '$c | sub("\\+00:00$"; "Z") | fromdateiso8601')"
# fix_row <host> <host_name> <event µs | -> <ingest epoch s> — one Better Stack row, built with jq
# so the `.raw` double encoding is exactly what the warehouse returns. `-` omits the event time.
fix_row() {
  jq -cn --arg h "$1" --arg hn "$2" --arg ts "$3" \
     --arg dt "$(date -u -d "@$4" '+%Y-%m-%d %H:%M:%S.000000')" \
     '{dt: $dt, raw: ({host: $h, host_name: $hn, message: "ROWSENTINEL", _BOOT_ID: "b", _MACHINE_ID: "m",
                       __MONOTONIC_TIMESTAMP: "1000"}
                      + (if $ts == "-" then {} else {__REALTIME_TIMESTAMP: $ts} end) | tojson)}'
}
# The current server's rows: stamped and ingested AFTER created (first row measured +145 s).
FIX_CUR_1="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR + 145))000000" $((FIX_FLOOR + 146)))"
FIX_CUR_2="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR + 175))000000" $((FIX_FLOOR + 176)))"
# THE 2026-09-24 SHAPE: the destroyed predecessor carried the SAME host/host_name pair, and its
# rows were both stamped and ingested BEFORE the current server existed.
FIX_PRE_1="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR - 16000))000000" $((FIX_FLOOR - 15999)))"
FIX_PRE_2="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR - 15950))000000" $((FIX_FLOOR - 15949)))"
# foreign/spoofed keep POST-floor clocks, so their `0` stays attributable to the #6616 host
# conjunct and never to the generation floor.
FIX_FOREIGN_1="$(fix_row soleur-web-platform soleur-web-platform "$((FIX_FLOOR + 145))000000" $((FIX_FLOOR + 146)))"
FIX_FOREIGN_2="$(fix_row soleur-web-platform soleur-web-platform "$((FIX_FLOOR + 175))000000" $((FIX_FLOOR + 176)))"
FIX_SPOOF_1="$(fix_row soleur-web-platform soleur-inngest-prd "$((FIX_FLOOR + 145))000000" $((FIX_FLOOR + 146)))"
FIX_SPOOF_2="$(fix_row soleur-web-platform soleur-inngest-prd "$((FIX_FLOOR + 175))000000" $((FIX_FLOOR + 176)))"

# Mixed-generation, malformed and clock-edge rows for the Guard 1 matrix.
FIX_NOTS="$(fix_row soleur-inngest soleur-inngest-prd - $((FIX_FLOOR + 146)))"
FIX_LATE_1="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR - 30))000000" $((FIX_FLOOR + 146)))"
FIX_LATE_2="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR - 20))000000" $((FIX_FLOOR + 176)))"
FIX_AHEAD_1="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR + 30))000000" $((FIX_FLOOR - 300)))"
FIX_AHEAD_2="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR + 40))000000" $((FIX_FLOOR - 290)))"
# A row whose event time carries a trailing newline: jq's `$` matches before a final newline, so an
# unanchored decimal test admits it and `tonumber` then aborts the WHOLE count. Excluded, not fatal.
FIX_NLTS="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR + 150))000000"$'\n' $((FIX_FLOOR + 151)))"
# Ingest clock boundary: stamped after created, ingested ONE second before it -> excluded.
FIX_DTMINUS="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR + 30))000000" $((FIX_FLOOR - 1)))"
FIX_EDGE="$(fix_row soleur-inngest soleur-inngest-prd "${FIX_FLOOR}000000" "$FIX_FLOOR")"
FIX_EDGE_MINUS="$(fix_row soleur-inngest soleur-inngest-prd "$((FIX_FLOOR * 1000000 - 1))" "$FIX_FLOOR")"
# Non-canonical but valid: keys reordered, extra journald fields, a bare-seconds dt.
FIX_REORDER="$(jq -cn --arg ts "$((FIX_FLOOR + 145))000000" --arg dt "$(date -u -d "@$((FIX_FLOOR + 146))" '+%Y-%m-%d %H:%M:%S')" \
  '{raw: ({_SYSTEMD_UNIT: "inngest-cutover-flip.service", __REALTIME_TIMESTAMP: $ts, PRIORITY: "6",
           host_name: "soleur-inngest-prd", _PID: "42", host: "soleur-inngest"} | tojson), dt: $dt, extra: 1}')"

FLV_ARGV="$(mktemp)"; SCRATCH+=("$FLV_ARGV")
FLV_CURL_ARGV="$(mktemp)"; SCRATCH+=("$FLV_CURL_ARGV")
FLV_CURL_STDIN="$(mktemp)"; SCRATCH+=("$FLV_CURL_STDIN")
FLV_CURL_CALLS="$(mktemp)"; SCRATCH+=("$FLV_CURL_CALLS")
FLV_HC_READS="$(mktemp)"; SCRATCH+=("$FLV_HC_READS")
FLV_ERR="$(mktemp)"; SCRATCH+=("$FLV_ERR")
# Every request a stub did not expect is recorded here (never truncated per call) and asserted empty
# at the end of the section: a stub that answers ANY request cannot see a wrong one.
FLV_STUB_MISS="$(mktemp)"; SCRATCH+=("$FLV_STUB_MISS")
# The generation-anchor functions the readers call. Extracted here and eval'd inside every reader
# harness; an empty extraction would leave every mode reading __UNREADABLE__ via "command not
# found", which the non-vacuity rows below refuse.
GEN_FN="$(mktemp)"; SCRATCH+=("$GEN_FN")
for _gfn in _hcloud_created_epoch _inngest_server_created_epoch _current_instance_row_counts _generation_scoped_count; do
  awk -v f="$_gfn" '$0 == f "() {" {p=1} p {print} p && /^\}$/ {p=0}' "$BODY_SH" >> "$GEN_FN"
done
FLV_OUT=""; FLV_RC=0
# lv_rows <mode> — the Better Stack rows each mode returns. Shared by the flip and LUKS harnesses.
lv_rows() {
  case "$1" in
    rows|current) printf '%s\n' "$FIX_CUR_1" "$FIX_CUR_2" ;;
    foreign)      printf '%s\n' "$FIX_FOREIGN_1" "$FIX_FOREIGN_2" ;;
    # THE #6616 COLLISION, FIXTURED: a WEB host self-labelling with the dedicated node's
    # sed-rendered host_name literal (#6616 is OPEN precisely because this was observed).
    # host_name ALONE counts these as our liveness -> H>0 -> `clear` -> the exact fail-open
    # this gate exists to close. The `host` conjunct is what excludes them, so this fixture
    # is what makes the dual-field filter load-bearing rather than decorative.
    spoofed)      printf '%s\n' "$FIX_SPOOF_1" "$FIX_SPOOF_2" ;;
    predecessor)  printf '%s\n' "$FIX_PRE_1" "$FIX_PRE_2" ;;
    mixed-pc)     printf '%s\n' "$FIX_PRE_1" "$FIX_PRE_2" "$FIX_CUR_1" "$FIX_CUR_2" ;;
    mixed-cp)     printf '%s\n' "$FIX_CUR_1" "$FIX_CUR_2" "$FIX_PRE_1" "$FIX_PRE_2" ;;
    no-ts)        printf '%s\n' "$FIX_NOTS" ;;
    no-ts+2cur)   printf '%s\n' "$FIX_NOTS" "$FIX_CUR_1" "$FIX_CUR_2" ;;
    late-ingest)  printf '%s\n' "$FIX_LATE_1" "$FIX_LATE_2" ;;
    clock-ahead)  printf '%s\n' "$FIX_AHEAD_1" "$FIX_AHEAD_2" ;;
    edge)         printf '%s\n' "$FIX_EDGE" ;;
    nlts+2cur)    printf '%s\n' "$FIX_NLTS" "$FIX_CUR_1" "$FIX_CUR_2" ;;
    dt-minus)     printf '%s\n' "$FIX_DTMINUS" ;;
    fresh)        # rows from a server created seconds ago, stamped after it (young AND counted > 0)
                  local n; n=$(date -u +%s)
                  fix_row soleur-inngest soleur-inngest-prd "$((n - 20))000000" $((n - 19))
                  fix_row soleur-inngest soleur-inngest-prd "$((n - 10))000000" $((n - 9)) ;;
    edge-minus)   printf '%s\n' "$FIX_EDGE_MINUS" ;;
    reorder)      printf '%s\n' "$FIX_REORDER" ;;
    *)            : ;;
  esac
}
# lv_mocks <rows-mode> <anchor-mode> <token-mode> — the reader's three external commands, each
# replaying its real contract. `doppler` branches on its ARGUMENTS before the mode: a mode-only
# mock answered the HCLOUD token read with row JSON, which made a failure row pass for the wrong
# reason. `curl` (called without -f) returns rc 0 plus the body plus `\n<code>`, as
# `-w '\n%{http_code}'` does; a non-zero rc is a transport fault only.
lv_mocks() {
  LV_MODE="$1"; LV_ANCHOR="${2:-ok}"; LV_TOK="${3:-both}"
  : > "$FLV_ARGV"; : > "$FLV_CURL_ARGV"; : > "$FLV_CURL_STDIN"; : > "$FLV_CURL_CALLS"; : > "$FLV_HC_READS"
  # shellcheck disable=SC2317  # invoked indirectly, by the eval'd readers
  doppler() {
    case "$*" in
      "secrets get HCLOUD_TOKEN_READONLY -p soleur -c prd_terraform --plain")
        echo HCLOUD_TOKEN_READONLY >> "$FLV_HC_READS"
        case "$LV_TOK" in both|ro) printf '%s\n' 'RO-TOKEN-SENTINEL' ;; esac
        return 0 ;;
      "secrets get HCLOUD_TOKEN -p soleur -c prd_terraform --plain")
        echo HCLOUD_TOKEN >> "$FLV_HC_READS"
        case "$LV_TOK" in both|rw) printf '%s\n' 'RW-TOKEN-SENTINEL' ;; esac
        return 0 ;;
      "secrets get "*) echo "unexpected-doppler: $*" >> "$FLV_STUB_MISS"; return 1 ;;
    esac
    printf '%s\n' "$*" > "$FLV_ARGV"
    case "$LV_MODE" in
      fail) return 7 ;;
      *) lv_rows "$LV_MODE"; return 0 ;;
    esac
  }
  # shellcheck disable=SC2317  # invoked indirectly, by the eval'd anchor
  curl() {
    printf '%s\n' "$@" > "$FLV_CURL_ARGV"
    cat > "$FLV_CURL_STDIN"
    echo called >> "$FLV_CURL_CALLS"
    # Replay the real request contract; anything else is a request the vendor would answer
    # differently (a POST to /v1/servers CREATES a server; no -w means no status line).
    local a prev="" want_w=0 want_get=0 want_h=0 want_proto=0 want_mt=0 url=""
    [[ "${1:-}" == "--disable" ]] || { echo "unexpected-curl: --disable is not first" >> "$FLV_STUB_MISS"; return 2; }
    for a in "$@"; do
      case "$prev" in
        -w) [[ "$a" == '\n%{http_code}' ]] && want_w=1 ;;
        -H) [[ "$a" == '@-' ]] && want_h=1 ;;
        --proto) [[ "$a" == '=https' ]] && want_proto=1 ;;
        --max-time) [[ "$a" =~ ^[0-9]+$ ]] && (( a <= 30 )) && want_mt=1 ;;
      esac
      [[ "$a" == --get ]] && want_get=1
      [[ "$a" == https://* ]] && url="$a"
      prev="$a"
    done
    if (( ! want_w || ! want_get || ! want_h || ! want_proto || ! want_mt )) \
       || [[ "$url" != 'https://api.hetzner.cloud/v1/servers' ]]; then
      echo "unexpected-curl: w=$want_w get=$want_get h=$want_h proto=$want_proto mt=$want_mt url=$url" >> "$FLV_STUB_MISS"
      return 2
    fi
    local c="$FIX_CREATED"
    case "$LV_ANCHOR" in
      ok)       ;;
      young)    c="$(date -u -d "@$(( $(date -u +%s) - 60 ))" '+%Y-%m-%dT%H:%M:%S+00:00')" ;;
      age590)   c="$(date -u -d "@$(( $(date -u +%s) - 590 ))" '+%Y-%m-%dT%H:%M:%S+00:00')" ;;
      age610)   c="$(date -u -d "@$(( $(date -u +%s) - 610 ))" '+%Y-%m-%dT%H:%M:%S+00:00')" ;;
      late)     c="$(date -u -d "@$(( FIX_FLOOR + 3600 ))" '+%Y-%m-%dT%H:%M:%S+00:00')" ;;
      zform)    c="$(date -u -d "@$FIX_FLOOR" '+%Y-%m-%dT%H:%M:%SZ')" ;;
      pre2025)  c='2024-06-01T00:00:00+00:00' ;;
      future)   c="$(date -u -d "@$(( $(date -u +%s) + 3600 ))" '+%Y-%m-%dT%H:%M:%S+00:00')" ;;
      forged)   printf '%s\n200' "{\"servers\":[{\"name\":\"soleur-inngest\",\"created\":\"$(date -u -d "@$FIX_FLOOR" '+%Y-%m-%dT%H:%M:%SZ')\\n::error::FORGED\"}]}"; return 0 ;;
      absent)   printf '%s\n200' '{"servers":[],"meta":{"note":"BODYSENTINEL"}}'; return 0 ;;
      two)      printf '%s\n200' "{\"servers\":[{\"name\":\"soleur-inngest\",\"created\":\"$FIX_CREATED\"},{\"name\":\"soleur-inngest\",\"created\":\"$FIX_CREATED\"}]}"; return 0 ;;
      nonjson)  printf '%s\n200' 'BODYSENTINEL'; return 0 ;;
      xfield)   printf '%s\n200' "{\"x\":\"BODYSENTINEL\",\"servers\":[{\"name\":\"soleur-inngest\",\"created\":\"$FIX_CREATED\",\"labels\":{\"k\":\"BODYSENTINEL\"}}]}"; return 0 ;;
      strsrv)   printf '%s\n200' '{"servers":"BODYSENTINEL"}'; return 0 ;;
      garbage)  printf '%s\n200' '{"servers":[{"name":"soleur-inngest","created":"BODYSENTINEL"}]}'; return 0 ;;
      http401)  printf '%s\n401' '{"error":{"code":"unauthorized","message":"BODYSENTINEL"}}'; return 0 ;;
      http429)  printf '%s\n429' '{"error":{"code":"rate_limit_exceeded","message":"BODYSENTINEL"}}'; return 0 ;;
      http503)  printf '%s\n503' 'BODYSENTINEL upstream unavailable'; return 0 ;;
      rc28)     return 28 ;;
      rc6)      return 6 ;;
    esac
    printf '{"servers":[{"id":167310350,"name":"soleur-inngest-old","created":"2020-01-01T00:00:00+00:00"},{"id":167310351,"name":"soleur-inngest","created":"%s","status":"running"}],"meta":{"pagination":{"page":1},"note":"BODYSENTINEL"}}\n200' "$c"
  }
}
call_flip_liveness_count() { # $1 = rows mode, $2 = anchor mode (default ok), $3 = token mode (default both)
  set +e
  FLV_OUT=$(
    eval "$(cat "$FLQ_FN")"
    eval "$(cat "$GEN_FN")"
    eval "$(cat "$FLV_FN")"
    lv_mocks "$1" "${2:-ok}" "${3:-both}"
    # DO NOT export FLIP_LIVENESS_SINCE here (#7674 review). Exporting it made the `--since 15m`
    # argv assertion measure the TEST'S OWN value, so widening the SUT to 365d — the fail-open
    # direction the SUT comment warns about — survived with the suite green. Source the real
    # assignment line from the script instead, so the argv assertion measures what ships.
    eval "$(grep -E '^FLIP_LIVENESS_SINCE=' "$BODY_SH")"
    export FLIP_LIVENESS_SINCE
    # Both live at script scope, outside the extracted functions, so the eval'd harness must
    # supply them. INNGEST_HOST_NAME empty would make the host filter match nothing and pin the
    # reader at 0 — the exact fail-shape the isolation assertions below exist to catch.
    export INNGEST_HOST="soleur-inngest"
    export INNGEST_HOST_NAME="soleur-inngest-prd"
    _flip_liveness_count 2>"$FLV_ERR"
  )
  FLV_RC=$?
  set -e
}

call_flip_liveness_count rows
assert "#7674 liveness reader counts THIS host's rows (2 -> '2', got '$FLV_OUT')" "[[ '$FLV_OUT' == '2' ]]"
assert "#7674 liveness reader always returns 0 so the DECISION owns the verdict (rc=$FLV_RC)" "[[ '$FLV_RC' -eq 0 ]]"
call_flip_liveness_count foreign
assert "#7674 HOST ISOLATION: another host's rows count 0, not as our liveness (got '$FLV_OUT')" "[[ '$FLV_OUT' == '0' ]]"
call_flip_liveness_count empty
assert "#7674 an empty liveness result is '0' (-> silent), not an error" "[[ '$FLV_OUT' == '0' ]]"
call_flip_liveness_count fail
assert "#7674 a FAILED liveness query yields __UNREADABLE__, never 0 (fail-closed)" "[[ '$FLV_OUT' == '__UNREADABLE__' ]]"
call_flip_liveness_count spoofed
assert "#6616 a web host SPOOFING our host_name counts 0, NOT as our liveness (got '$FLV_OUT')" \
  "[[ '$FLV_OUT' == '0' ]]"
call_flip_liveness_count predecessor
assert "G3 generation: the DESTROYED predecessor's same-name rows count 0 — the 2026-09-24 pass (got '$FLV_OUT')" \
  "[[ '$FLV_OUT' == '0' ]]"

call_flip_liveness_count spoofed
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
FLV_ARGV_SEEN="$(cat "$FLV_ARGV")"
assert "#7674 liveness reader bounds the window with --since \$FLIP_LIVENESS_SINCE" \
  "grep -qF -- '--since 15m' <<<\"\$FLV_ARGV_SEEN\""
assert "#7674 liveness reader requests a full page (--limit 1 would cap H and break confirm)" \
  "grep -qF -- '--limit 50' <<<\"\$FLV_ARGV_SEEN\""
assert "#7674 liveness reader keys on the TAG, not an enumerated reason set" \
  "grep -qF -- '--grep inngest-cutover-flip' <<<\"\$FLV_ARGV_SEEN\""
assert "#7674 liveness reader does NOT enumerate noop-* reasons (would read H=0 on a healthy host)" \
  "! grep -qE 'noop-' <<<\"\$FLV_ARGV_SEEN\""
# The host filter must NOT ride --grep: betterstack-query.sh OR-combines --grep terms, so a host
# term there WIDENS the query instead of narrowing it — a fail-open wearing a filter's clothes.
assert "#7674 host isolation is NOT attempted via --grep (which is OR-combined, so it would widen)" \
  "! grep -qE '\\-\\-grep[= ]*[\"'\'']?host_name' <<<\"\$FLV_ARGV_SEEN\""
assert "#7674 the liveness reader decodes .raw before matching the host (raw is double-encoded; since the generation scope, in the floored filter it calls)" \
  "grep -vE '^[[:space:]]*#' '$GEN_FN' | grep -cE '\\(\\.raw \\| if type == \"string\" then \\(fromjson' >/dev/null"
# DELIBERATELY A LITERAL, not env-overridable (#7674 review): it is not mapped into
# cutover-inngest.yml's step env, so an override would be an unperformable remediation (the
# #6617 dead-remediation class), and widening this window is the FAIL-OPEN direction.
assert "#7674 FLIP_LIVENESS_SINCE is the literal 15m (shape alone let 365d pass — fail-open)" \
  "grep -qE '^FLIP_LIVENESS_SINCE=\"15m\"$' '$BODY_SH'"
assert "#7674 FLIP_LIVENESS_SINCE is NOT plumbed into the workflow env (would be a dead knob)" \
  "! grep -qF 'FLIP_LIVENESS_SINCE' '$WF_YAML'"

# --- (b2g) GENERATION SCOPE (2026-09-24 host replace) -------------------------------------------
# "Audible" = audible from the server that exists NOW. host/host_name are identical across a
# replace (AP-027), so the readers anchor on the Hetzner API's `created` and count a row only when
# its event time AND its Better Stack ingest dt are both at or after it.
echo "--- G3 generation scope ---"
for _gfn in _hcloud_created_epoch _inngest_server_created_epoch _current_instance_row_counts _generation_scoped_count; do
  assert "G3 generation: extraction yields a callable $_gfn (an empty one reads every mode as __UNREADABLE__)" \
    "bash -c 'eval \"\$(cat \"$GEN_FN\")\"; declare -F $_gfn >/dev/null'"
done
# jq self-check: if the runner's jq parses either clock differently, this fails FIRST.
assert "G3 generation: jq parses Hetzner created (Z and +00:00) and the Better Stack dt form to the expected epochs" \
  "[[ \"\$(jq -rn '\"2026-09-24T18:57:33+00:00\" | sub(\"\\\\+00:00\$\"; \"Z\") | strptime(\"%Y-%m-%dT%H:%M:%SZ\") | mktime')\" == 1790276253 && \"\$(jq -rn '\"2026-09-24 19:08:26.1\" | sub(\"\\\\.[0-9]+\$\"; \"\") | strptime(\"%Y-%m-%d %H:%M:%S\") | mktime')\" == 1790276906 ]]"
# H1: foreign/spoofed must stay POST-floor on both clocks, so their 0 is the #6616 host conjunct's.
H1_CHECKED=0; H1_BAD=0
for _r in "$FIX_FOREIGN_1" "$FIX_FOREIGN_2" "$FIX_SPOOF_1" "$FIX_SPOOF_2"; do
  H1_CHECKED=$((H1_CHECKED + 1))
  jq -e --argjson f "$FIX_FLOOR" '(.raw | fromjson | .__REALTIME_TIMESTAMP | tonumber) >= ($f * 1000000)
      and ((.dt | sub("\\.[0-9]+$"; "") | strptime("%Y-%m-%d %H:%M:%S") | mktime) >= $f)' <<<"$_r" >/dev/null || H1_BAD=$((H1_BAD + 1))
done
assert "G3 generation H1: the foreign/spoofed fixtures are post-floor on both clocks (checked=$H1_CHECKED bad=$H1_BAD)" \
  "[[ '$H1_CHECKED' -eq 4 && '$H1_BAD' -eq 0 ]]"

# Guard 1 — the row predicate, executed through the real reader.
lv_case() { # $1 desc, $2 rows mode, $3 anchor mode, $4 expected token
  call_flip_liveness_count "$2" "$3"
  assert "G3 generation: $1 ($2/$3 -> '$4', got '$FLV_OUT')" "[[ '$FLV_OUT' == '$4' ]]"
  assert "G3 generation: $1 — no row or response byte on stdout/stderr" \
    "! grep -qE 'ROWSENTINEL|BODYSENTINEL' '$FLV_ERR' && [[ '$FLV_OUT' != *SENTINEL* ]]"
}
lv_case "the current server's rows count"                         current     ok     2
lv_case "predecessor rows then current rows: only the current count" mixed-pc  ok     2
lv_case "current rows then predecessor rows: only the current count" mixed-cp  ok     2
lv_case "a row with no event time is excluded, never defaulted"   no-ts       ok     0
grep -qE 'host_pair=1 pre_floor=0 malformed=1 ' "$FLV_ERR"; NOTS_M=$?
assert "G3 generation: the no-event-time row is reported as malformed=1 in the notice" "[[ '$NOTS_M' -eq 0 ]]"
lv_case "one malformed row does not abort the count"              no-ts+2cur  ok     2
lv_case "rows ingested after created but stamped before it do not count" late-ingest ok 0
grep -qE 'skew_suspect=2$' "$FLV_ERR"; LATE_K=$?
assert "G3 generation: late-ingest rows are reported as skew_suspect=2 (the current clock is behind)" "[[ '$LATE_K' -eq 0 ]]"
lv_case "a predecessor whose clock ran ahead is caught by the ingest clock" clock-ahead ok 0
lv_case "the floor comes from the anchor: the same rows before a LATER created count 0" current late 0
lv_case "a Z-form created parses"                                  current     zform  2
lv_case "boundary: event time == created and dt == created counts" edge        ok     1
lv_case "boundary: one microsecond before created does not"        edge-minus  ok     0
lv_case "boundary: ingested ONE second before created does not, whatever it is stamped" dt-minus ok 0
lv_case "a top-level extra field and a sentinel-bearing label do not disturb the decode" current xfield 2
lv_case "non-canonical row (reordered keys, extra fields, bare-seconds dt) counts" reorder ok 1
call_flip_liveness_count predecessor ok
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
PRE_NOTICE="$(grep -F '::notice::' "$FLV_ERR" || true)"
assert "G3 generation: the predecessor notice carries all six counters and the age" \
  "grep -qE 'created [0-9TZ:-]+ \\([0-9]+s ago\\): rows=2 counted=0 host_pair=2 pre_floor=2 malformed=0 skew_suspect=0$' <<<\"\$PRE_NOTICE\" && grep -qF \"created \$(date -u -d @$FIX_FLOOR '+%Y-%m-%dT%H:%M:%SZ') (\" <<<\"\$PRE_NOTICE\""
assert "G3 generation: an OLD server with nothing counted gets NO wait-don't-replace warning" \
  "! grep -qF 'do NOT replace it' '$FLV_ERR'"
call_flip_liveness_count predecessor young
assert "G3 generation: a YOUNG server with nothing counted reads 0" "[[ '$FLV_OUT' == '0' ]]"
assert "G3 generation: a YOUNG server with nothing counted gets the WAIT, do NOT replace warning" \
  "grep -qF 'WAIT and re-dispatch; do NOT replace it' '$FLV_ERR'"
call_flip_liveness_count predecessor age590
assert "G3 generation: the wait warning still fires at 590 s (the 600 s threshold, pinned from below)" \
  "grep -qF 'WAIT and re-dispatch' '$FLV_ERR'"
call_flip_liveness_count predecessor age610
assert "G3 generation: the wait warning is gone at 610 s (the 600 s threshold, pinned from above)" \
  "! grep -qF 'WAIT and re-dispatch' '$FLV_ERR'"
call_flip_liveness_count fresh young
assert "G3 generation: a young server that HAS shipped counts and gets no wait warning" \
  "[[ '$FLV_OUT' == '2' ]] && ! grep -qF 'WAIT and re-dispatch' '$FLV_ERR'"
call_flip_liveness_count current ok
assert "G3 generation: the stdout token is a bare decimal (the notice stays on stderr)" "[[ '$FLV_OUT' =~ ^[0-9]+\$ ]]"

# Guard 1 row 6 + Guard 2: every anchor failure fails closed AND skips the Better Stack read.
AF_N=0
for _am in absent two nonjson strsrv garbage http401 http429 http503 rc28 rc6 forged pre2025 future; do
  call_flip_liveness_count current "$_am"
  AF_N=$((AF_N + 1))
  assert "G3 generation anchor $_am: the reader fails closed (__UNREADABLE__, got '$FLV_OUT')" "[[ '$FLV_OUT' == '__UNREADABLE__' ]]"
  assert "G3 generation anchor $_am: the Better Stack read was skipped" "[[ ! -s '$FLV_ARGV' ]]"
  assert "G3 generation anchor $_am: exactly one named ::warning::, never the Better Stack remedy" \
    "[[ \"\$(grep -c '::warning::G3 generation anchor:' '$FLV_ERR')\" -eq 1 ]] && ! grep -qF 'BETTERSTACK_QUERY' '$FLV_ERR'"
  assert "G3 generation anchor $_am: no response byte reaches stdout or stderr" \
    "! grep -qE 'BODYSENTINEL|::error::FORGED' '$FLV_ERR' && [[ '$FLV_OUT' != *BODYSENTINEL* ]]"
done
assert "G3 generation: every anchor failure mode ran (13)" "[[ '$AF_N' -eq 13 ]]"
call_flip_liveness_count current absent
assert "G3 generation anchor absent: the warning names the queried server and the token's project" \
  "grep -qF 'no server named soleur-inngest in the Hetzner project this token is scoped to' '$FLV_ERR'"
call_flip_liveness_count current http401
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
W401="$(grep -F '::warning::' "$FLV_ERR" || true)"
call_flip_liveness_count current http429
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
W429="$(grep -F '::warning::' "$FLV_ERR" || true)"
call_flip_liveness_count current http503
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
W503="$(grep -F '::warning::' "$FLV_ERR" || true)"
assert "G3 generation anchor: 401, 429 and 503 name three DIFFERENT causes, none of them absent" \
  "grep -qF 'REJECTED the token' <<<\"\$W401\" && grep -qF 'rate-limited' <<<\"\$W429\" && grep -qF 'server error (HTTP 503)' <<<\"\$W503\" && ! grep -qF 'no server named' <<<\"\$W401\$W429\$W503\""
call_flip_liveness_count current rc28
assert "G3 generation anchor: a timeout names the timeout (not the egress class)" "grep -qF 'read timed out (transport rc=28)' '$FLV_ERR'"
call_flip_liveness_count current rc6
assert "G3 generation anchor: a DNS/connect failure names that class" "grep -qF 'unreachable from the runner (transport rc=6' '$FLV_ERR'"
call_flip_liveness_count current ok none
assert "G3 generation anchor: no token resolved -> __UNREADABLE__, curl never called" \
  "[[ '$FLV_OUT' == '__UNREADABLE__' && ! -s '$FLV_CURL_CALLS' ]] && grep -qF 'doppler returned nothing for HCLOUD_TOKEN_READONLY or HCLOUD_TOKEN' '$FLV_ERR'"

lv_case "a timestamp with a trailing newline is excluded, not fatal to the count" nlts+2cur ok 2
call_flip_liveness_count late-ingest ok
assert "G3 generation: counted=0 with skew_suspect>0 warns that the server IS shipping with a clock behind (never 'replace')" \
  "grep -qF 'IS shipping (2 row(s) ingested after it was created) but its clock is behind' '$FLV_ERR' && grep -qF 'do NOT replace it' '$FLV_ERR'"
call_flip_liveness_count no-ts ok
assert "G3 generation: counted=0 with malformed>0 warns of a schema change, which a replace will not fix" \
  "grep -qF 'carried no parseable __REALTIME_TIMESTAMP or dt' '$FLV_ERR' && ! grep -qF 'WAIT and re-dispatch' '$FLV_ERR'"
call_flip_liveness_count current ok rw
assert "G3 generation anchor: the read/write fallback is announced by NAME (never value)" \
  "grep -qF '::notice::G3 generation anchor: using the read/write HCLOUD_TOKEN' '$FLV_ERR'"
assert "G3 generation anchor: the read/write token is masked too, and reaches stderr only as the mask" \
  "grep -qxF '::add-mask::RW-TOKEN-SENTINEL' '$FLV_ERR' && [[ \"\$(grep -c 'RW-TOKEN-SENTINEL' '$FLV_ERR')\" -eq 1 ]]"
call_flip_liveness_count current http401 rw
assert "G3 generation anchor: a rejected token names the variable that was sent" \
  "grep -qF 'the one sent was HCLOUD_TOKEN;' '$FLV_ERR'"
# A local filter fault must warn, so the `unreadable` refusal never points at a warning that is absent.
FILTER_OUT="$( eval "$(cat "$GEN_FN")"; export INNGEST_HOST=soleur-inngest INNGEST_HOST_NAME=soleur-inngest-prd
  _current_instance_row_counts() { printf '%s' 'garbage'; }
  printf '%s\n' "$FIX_CUR_1" | _generation_scoped_count "$FIX_FLOOR" test 2>"$FLV_ERR" )"
assert "G3 generation: a filter that does not yield six integers -> __UNREADABLE__ WITH a warning naming it" \
  "[[ '$FILTER_OUT' == '__UNREADABLE__' ]] && grep -qF 'row-count filter did not yield six integers' '$FLV_ERR'"
FILTER_OUT="$( eval "$(cat "$GEN_FN")"; export INNGEST_HOST=soleur-inngest INNGEST_HOST_NAME=soleur-inngest-prd
  _current_instance_row_counts() { printf '%s' '2 2 2 0 0 0 9'; }
  printf '%s\n' "$FIX_CUR_1" | _generation_scoped_count "$FIX_FLOOR" test 2>"$FLV_ERR" )"
assert "G3 generation: a SEVENTH token from the filter is refused, not silently absorbed" \
  "[[ '$FILTER_OUT' == '__UNREADABLE__' ]]"
# Closure: the host-pair predicate lives in exactly ONE place, and both write-gating readers reach it.
HP_SITES=$(grep -cF '.r.host == $h and .r.host_name == $hn' "$BODY_SH" || true)
OLD_HP=$(grep -cF 'select(.host == $h and .host_name == $hn)' "$BODY_SH" || true)
GSC_CALLS=$(awk '/^_(flip|luks)_liveness_count\(\) \{$/,/^\}$/' "$BODY_SH" | grep -cE '\| _generation_scoped_count "\$floor"' || true)
assert "G3 generation closure: one host-pair predicate (in the floored filter), no unfloored copy, both readers call it (sites=$HP_SITES old=$OLD_HP calls=$GSC_CALLS)" \
  "[[ '$HP_SITES' -eq 1 && '$OLD_HP' -eq 0 && '$GSC_CALLS' -eq 2 ]]"
# The harness evals the FIRST multi-line definition of each function; bash runs the LAST. A second
# (e.g. one-line) definition later in the file would silently replace what the suite verified.
for _gfn in _hcloud_created_epoch _inngest_server_created_epoch _current_instance_row_counts _generation_scoped_count _flip_liveness_count _luks_liveness_count _flush_latch_count; do
  _defs=$(grep -cE "^[[:space:]]*(function[[:space:]]+)?${_gfn}[[:space:]]*(\(\))?[[:space:]]*\{" "$BODY_SH" || true)
  assert "G3 generation: $_gfn is defined exactly once, so the harness runs what the script runs (got $_defs)" "[[ '$_defs' -eq 1 ]]"
done
LATCH_REFS=$(awk '/^_flush_latch_count\(\) \{$/,/^\}$/' "$BODY_SH" | grep -vE '^[[:space:]]*#' | grep -cE '_inngest_server_created_epoch|_generation_scoped_count|_current_instance_row_counts' || true)
assert "G3 generation: the flush latch body never reaches the generation anchor or filter (refs=$LATCH_REFS)" "[[ '$LATCH_REFS' -eq 0 ]]"

# Guard 2 — token hygiene and transport, on a successful read.
call_flip_liveness_count current ok both
assert "G3 generation anchor: Tier A first — only HCLOUD_TOKEN_READONLY is read when it resolves" \
  "[[ \"\$(tr '\\n' ' ' < '$FLV_HC_READS')\" == 'HCLOUD_TOKEN_READONLY ' ]]"
assert "G3 generation anchor: the token travels on curl's stdin as the Authorization header" \
  "grep -qxF 'Authorization: Bearer RO-TOKEN-SENTINEL' '$FLV_CURL_STDIN'"
assert "G3 generation anchor: the token is NEVER on curl's argv" "! grep -qF 'TOKEN-SENTINEL' '$FLV_CURL_ARGV'"
assert "G3 generation anchor: the token reaches stderr exactly once, as ::add-mask::" \
  "[[ \"\$(grep -c 'TOKEN-SENTINEL' '$FLV_ERR')\" -eq 1 ]] && grep -qxF '::add-mask::RO-TOKEN-SENTINEL' '$FLV_ERR' && [[ '$FLV_OUT' != *SENTINEL* ]]"
assert "G3 generation anchor: transport pins (--disable first, --noproxy, --proto =https, --max-time, -H @-, --data-urlencode name=soleur-inngest)" \
  "[[ \"\$(head -1 '$FLV_CURL_ARGV')\" == '--disable' ]] && grep -qxF -- '--noproxy' '$FLV_CURL_ARGV' && grep -qxF -- '=https' '$FLV_CURL_ARGV' && grep -qxF -- '--max-time' '$FLV_CURL_ARGV' && grep -qxF -- '@-' '$FLV_CURL_ARGV' && grep -qxF -- 'name=soleur-inngest' '$FLV_CURL_ARGV' && grep -qxF -- 'https://api.hetzner.cloud/v1/servers' '$FLV_CURL_ARGV'"
assert "G3 generation anchor: no --retry, no -f/--fail, no -S (the HTTP class must stay readable; curl's error text is not an egress path)" \
  "! grep -qxE -- '--retry.*|-f|--fail.*|-S|-sS|-fsS|--show-error' '$FLV_CURL_ARGV'"
call_flip_liveness_count current ok rw
assert "G3 generation anchor: falls back to HCLOUD_TOKEN only after an empty read-only read" \
  "[[ \"\$(tr '\\n' ' ' < '$FLV_HC_READS')\" == 'HCLOUD_TOKEN_READONLY HCLOUD_TOKEN ' && '$FLV_OUT' == '2' ]] && grep -qxF 'Authorization: Bearer RW-TOKEN-SENTINEL' '$FLV_CURL_STDIN'"
# The wrapper returns 0 on every failure, so a caller's `x="$(…)"` under set -e never dies mute.
AR_REACHED=0
for _am in rc28 http503 absent nonjson; do
  _o="$( set -euo pipefail; eval "$(cat "$GEN_FN")"; lv_mocks current "$_am" both; export INNGEST_HOST=soleur-inngest INNGEST_HOST_NAME=soleur-inngest-prd; x="$(_inngest_server_created_epoch 2>/dev/null)"; echo "reached:$x" )" || true
  [[ "$_o" == reached:__* ]] && AR_REACHED=$((AR_REACHED + 1))
done
assert "G3 generation anchor: returns 0 under set -e in every failure mode (reached=$AR_REACHED/4)" "[[ '$AR_REACHED' -eq 4 ]]"

# The pure decoder, as a table.
HCE_N=0
hce_case() { local got; got="$( eval "$(cat "$GEN_FN")"; _hcloud_created_epoch "$2" soleur-inngest )"; HCE_N=$((HCE_N + 1))
  assert "_hcloud_created_epoch: $1 -> '$3' (got '$got')" "[[ '$got' == '$3' ]]"; }
hce_case "Z form"                    '{"servers":[{"name":"soleur-inngest","created":"2026-09-24T18:57:33Z"}]}'      1790276253
hce_case "+00:00 form"               '{"servers":[{"name":"soleur-inngest","created":"2026-09-24T18:57:33+00:00"}]}' 1790276253
hce_case "non-matching first"        '{"servers":[{"name":"soleur-inngest-old","created":"2020-01-01T00:00:00Z"},{"name":"soleur-inngest","created":"2026-09-24T18:57:33Z"}]}' 1790276253
hce_case "no match"                  '{"servers":[{"name":"soleur-inngest-old","created":"2026-09-24T18:57:33Z"}]}' __ABSENT__
hce_case "empty list"                '{"servers":[]}'                                                                   __ABSENT__
hce_case "two matches"               '{"servers":[{"name":"soleur-inngest","created":"2026-09-24T18:57:33Z"},{"name":"soleur-inngest","created":"2026-09-24T18:57:34Z"}]}' __UNREADABLE__
hce_case "missing created"           '{"servers":[{"name":"soleur-inngest"}]}'                                          __UNREADABLE__
hce_case "garbage created"           '{"servers":[{"name":"soleur-inngest","created":"yesterday"}]}'                    __UNREADABLE__
hce_case "created with a forged tail" '{"servers":[{"name":"soleur-inngest","created":"2026-09-24T18:57:33Z\n::error::FORGED"}]}' __UNREADABLE__
hce_case "non-JSON"                  'BODYSENTINEL'                                                                     __UNREADABLE__
hce_case "servers is a string"       '{"servers":"x"}'                                                                  __UNREADABLE__
hce_case "empty input"               ''                                                                                 __UNREADABLE__
assert "_hcloud_created_epoch: every decode case ran (12)" "[[ '$HCE_N' -eq 12 ]]"

# LUKS G3 reads the same generation-scoped count.
LKL_FN="$(mktemp)"; SCRATCH+=("$LKL_FN")
awk '/^_luks_liveness_count\(\) \{$/,/^\}$/' "$BODY_SH" > "$LKL_FN"
LKL_OUT=""
call_luks_liveness_count() {
  set +e
  LKL_OUT=$(
    eval "$(cat "$FLQ_FN")"; eval "$(cat "$GEN_FN")"; eval "$(cat "$LKL_FN")"
    lv_mocks "$1" "${2:-ok}" both
    eval "$(grep -E '^LUKS_LIVENESS_SINCE=' "$BODY_SH")"
    export INNGEST_HOST="soleur-inngest" INNGEST_HOST_NAME="soleur-inngest-prd"
    _luks_liveness_count 2>"$FLV_ERR"
  )
  set -e
}
call_luks_liveness_count predecessor
assert "G3 generation: LUKS liveness does not count the predecessor (got '$LKL_OUT')" "[[ '$LKL_OUT' == '0' ]]"
call_luks_liveness_count current
assert "G3 generation: LUKS liveness counts the current server (got '$LKL_OUT')" "[[ '$LKL_OUT' == '2' ]]"
assert "G3 generation: LUKS liveness keeps its own tag" "grep -qF -- '--grep inngest-luks-cutover' '$FLV_ARGV'"
call_luks_liveness_count current absent
assert "G3 generation: LUKS liveness fails closed on an unreadable anchor and skips Better Stack" \
  "[[ '$LKL_OUT' == '__UNREADABLE__' && ! -s '$FLV_ARGV' ]]"

# The latch is deliberately unfloored and never reaches Hetzner.
: > "$FL_CURL_CALLS"
call_flush_latch_count rows
assert "G3 generation: the flush latch stays UNFLOORED (2 rows -> '2') and never calls the Hetzner API" \
  "[[ '$FLC_OUT' == '2' && ! -s '$FL_CURL_CALLS' ]]"

# Invariants the floor rests on.
INNGEST_TF="$REPO_ROOT/apps/web-platform/infra/inngest-host.tf"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
INNGEST_SRV_BLOCK="$(awk '/^resource "hcloud_server" "inngest" \{/,/^\}/' "$INNGEST_TF")"
assert "G3 generation invariant: hcloud_server.inngest exists, is named soleur-inngest, and has NO create_before_destroy" \
  "grep -qE '^[[:space:]]*name[[:space:]]*=[[:space:]]*\"soleur-inngest\"' <<<\"\$INNGEST_SRV_BLOCK\" && ! grep -qE '^[[:space:]]*create_before_destroy' <<<\"\$INNGEST_SRV_BLOCK\""
assert "G3 generation invariant: vector.toml never ships previous boots (no current_boot_only = false)" \
  "[[ -f '$REPO_ROOT/apps/web-platform/infra/vector.toml' ]] && ! grep -qE '^[[:space:]]*current_boot_only[[:space:]]*=[[:space:]]*false' '$REPO_ROOT/apps/web-platform/infra/vector.toml'"
# The bracketed first letter keeps this pin from matching its own source line.
assert "G3 generation invariant: nothing rebuilds a server in place (no API or CLI server-rebuild call in scripts/, .github/, apps/, plugins/)" \
  "! grep -rqE 'actions/[r]ebuild|server [r]ebuild' '$REPO_ROOT/scripts' '$REPO_ROOT/.github' '$REPO_ROOT/apps' '$REPO_ROOT/plugins' --include='*.sh' --include='*.yml' --include='*.yaml' --include='*.tf' --include='*.ts' --include='*.py'"
assert "G3 generation: the workflow YAML carries no knob that could weaken the floor" \
  "! grep -vE '^[[:space:]]*#' '$WF_YAML' | grep -cE 'INNGEST_HOST|FLOOR|SKEW|HCLOUD' >/dev/null"
assert "G3 generation: resume's silent refusal makes the replace advice conditional on the server's age" \
  "grep -qF 'Only if that ::notice:: shows the server is more than 600s old with counted=0, skew_suspect=0 AND malformed=0 is an inngest-host-replace the path forward' '$RESUME_FILE'"
assert "G3 generation: the unreadable refusals point at the ::warning:: naming the failed read (resume, LUKS, arm)" \
  "grep -qF 'the Hetzner generation anchor (follow that warning — including the case where the anchor found NO server named' '$RESUME_FILE' && [[ \"\$(grep -c 'the Hetzner generation anchor (follow that warning — including the case where the anchor found NO server named' '$BODY_SH')\" -eq 2 ]] && grep -qF 'Better Stack, the Hetzner generation anchor — including no server named' '$BODY_SH'"

# Every request the section made matched the real contract (checked BEFORE the controls below,
# which deliberately write to the ledger).
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
STUB_MISSES="$(cat "$FLV_STUB_MISS")"
assert "G3 generation: no curl/doppler request in this section deviated from the real contract (${STUB_MISSES:-none})" \
  "[[ ! -s '$FLV_STUB_MISS' ]]"
# Positive controls: the stubs must be able to REJECT, or the ledger above proves nothing.
( lv_mocks current ok both; printf 'x' | curl --disable --noproxy '*' -s --proto =https --max-time 20 -H @- -w '\n%{http_code}' https://api.hetzner.cloud/v1/servers >/dev/null ) || true
( lv_mocks current ok both; doppler secrets get HCLOUD_TOKEN -p soleur -c prd --plain >/dev/null ) || true
assert "G3 generation: stub control — curl without --get and doppler with the wrong config are both recorded as misses" \
  "grep -qF 'unexpected-curl: w=1 get=0' '$FLV_STUB_MISS' && grep -qF 'unexpected-doppler: secrets get HCLOUD_TOKEN -p soleur -c prd --plain' '$FLV_STUB_MISS'"

# --- (b3) op=resume's G3 HOST-AUDIBILITY GATE (#7674, CTO ruling) -----------------------------
# `flushed` is acted on ONLY by the on-host 30s timer. Writing it to a dark host recovers nothing
# and parks the flag where resume's own G1 rejects it as IN-FLIGHT while op=arm is refused by
# G3.7 — stranding the only dispatchable re-entry. A DELIVERABILITY gate, not an evidence one.
RSL_FN="$(mktemp)"; SCRATCH+=("$RSL_FN")
awk '/^resume_liveness_decide\(\) \{$/,/^\}$/' "$BODY_SH" > "$RSL_FN"
RSL_N=$(wc -l < "$RSL_FN" | tr -d '[:space:]')
assert "#7674 resume_liveness_decide extraction is non-vacuous (>3 lines, got $RSL_N)" "[[ '$RSL_N' -gt 3 ]]"
# shellcheck disable=SC1090
. "$RSL_FN"
RSL_EVALS=0
rsl_case() { local got; got="$(resume_liveness_decide "$2")"; RSL_EVALS=$((RSL_EVALS + 1))
  assert "resume_liveness_decide: $1 (H=$2) -> $3" "[[ '$got' == '$3' ]]"; }
rsl_case "an audible host proceeds"                 "20"             "audible"
rsl_case "a SILENT host refuses (would strand the re-entry)" "0"     "silent"
rsl_case "an unreadable read fails closed"          "__UNREADABLE__" "unreadable"
rsl_case "an empty count fails closed"              ""               "unreadable"
rsl_case "a non-numeric count fails closed"         "n/a"            "unreadable"
rsl_case "a negative count fails closed"            "-1"             "unreadable"
assert "#7674 resume_liveness_decide scenarios dispatched (>=6)" "[[ '$RSL_EVALS' -ge 6 ]]"
# DELIBERATELY NOT flush_latch_decide: L's polarity INVERTS between the verbs (L>=1 REFUSES at
# arm, SATISFIES the precondition at resume), so sharing the function would leave `latched`
# meaning opposite things at its two call sites.
assert "#7674 resume does NOT reuse flush_latch_decide (L's polarity inverts between the verbs)" \
  "! grep -qF 'flush_latch_decide' '$RESUME_FILE'"
# A refusal that does not abort is just a logger: the gate must be read BEFORE the prod write.
# Pin the CALL, not the assignment: `RS_LIVE_N="20"` satisfies a bare `RS_LIVE_N=` grep and
# severs the gate from its signal entirely (mutation-verified — this exact edit survived until
# this row existed). The gate must be fed by the real reader.
assert "#7674 resume) feeds G3 from _flip_liveness_count, not a literal (severing it must red)" \
  "grep -qF 'RS_LIVE_N=\"\$(_flip_liveness_count)\"' '$RESUME_FILE'"
RSL_RD=$(grep -nF 'RS_LIVE_N="$(_flip_liveness_count)"' "$RESUME_FILE" | sed -n '1p' | cut -d: -f1) || true
RSL_WR=$(grep -nE "secrets set INNGEST_CUTOVER_FLIP " "$RESUME_FILE" | sed -n '1p' | cut -d: -f1) || true
assert "#7674 resume) reads liveness BEFORE writing flushed (got read=$RSL_RD write=$RSL_WR)" \
  "[[ -n '$RSL_RD' && -n '$RSL_WR' && '$RSL_RD' -lt '$RSL_WR' ]]"
assert "#7674 resume) routes through resume_liveness_decide exactly once" \
  "[[ \$(grep -cF 'resume_liveness_decide \"\$RS_LIVE_N\"' '$RESUME_FILE') -eq 1 ]]"

# --- (c) EMITTER PARITY (cross-file), in the SUBSET direction. -------------------------------
# The two reasons this gate keys on are a vocabulary owned by inngest-cutover-flip.sh. If either
# is renamed there, the grep silently matches nothing and the gate reports CLEAR forever — a
# fail-open on the only question it asks. Assert each is a literal that file actually emits.
FL_EMITTER_SH="$REPO_ROOT/apps/web-platform/infra/inngest-cutover-flip.sh"
assert "#7462 the flip emitter exists (G3.7 parity source)" "[[ -f '$FL_EMITTER_SH' ]]"
assert "#7462 EMITTER PARITY: flip-complete is a real emit_state literal" \
  "grep -qE 'emit_state [^ ]+ [^ ]+ \"flip-complete\"' '$FL_EMITTER_SH'"
assert "#7462 EMITTER PARITY: refuse-rearm-after-done is a real emit_state literal" \
  "grep -qE 'emit_state [^ ]+ [^ ]+ \"refuse-rearm-after-done\"' '$FL_EMITTER_SH'"
# And that both are genuinely evidence of a flush: the first is the arm that records the durable
# latch, the second is the arm the latch itself takes.
assert "#7462 flip-complete is emitted on the flag:done arm (a COMPLETED flip)" \
  "grep -qE 'emit_state 0 .* \"flip-complete\" \"done\"' '$FL_EMITTER_SH'"
assert "#7462 refuse-rearm-after-done is emitted by the latch refusal itself" \
  "grep -qF 'refuse_rearm_after_done() {' '$FL_EMITTER_SH'"

# --- (d) ASSEMBLY: the gate is wired into arm), ahead of every prod write. --------------------
assert "arm) routes G3.7 through flush_latch_decide exactly once (single chokepoint)" \
  "[[ \$(grep -cE '^[[:space:]]+FL_OUTCOME=\"?\\\$\\(flush_latch_decide ' '$ARM_FILE') -eq 1 ]]"
assert "arm) reads the latch via _flush_latch_count exactly once" \
  "[[ \$(grep -cE '^[[:space:]]+FLUSH_LATCH_N=\"?\\\$\\(_flush_latch_count' '$ARM_FILE') -eq 1 ]]"
# PROCEED ONLY ON `clear`. Written as a positive-allowlist gate, not a blocklist of refusals:
# a future outcome token then fails CLOSED by construction instead of falling through.
assert "arm) G3.7 aborts unless the outcome is exactly 'clear' (fail-closed by construction)" \
  "[[ \$(grep -cF 'if [[ \"\$FL_OUTCOME\" != \"clear\" ]]; then exit 1; fi' '$ARM_FILE') -eq 1 ]]"
# `silent` is in this alternation deliberately (#7674): the assertion was blind to a NEW arm,
# so without it the no-per-arm-exit contract would be unenforced for exactly the arm being added.
# SINGLE-CHOKEPOINT + ORDERING (#7674, AC3/AC4). The shared reader must have exactly the two
# callers it was extracted for — a third would be the duplicated reader the extraction exists to
# prevent, and drift between them is how the confirm path and the gate path stop asking the same
# question. The liveness read must also be INVOKED BEFORE the decide: a decider handed a stale or
# unset H is the fail-open this gate was built to close.
FLQ_SITES=$(grep -cE '^[[:space:]]*(rows=\$\(|[A-Z_]+_RC=0;[[:space:]]+)?_bs_query_rows ' "$BODY_SH") || true
# 4 -> 6 at #6894: the LUKS cutover FSM added its OWN confirm + liveness readers. They are extra
# CALLERS of the shared reader, not a second reader — which is the property this row protects. They
# are a separate pair on purpose: they query a different tag, because a flip row proves nothing
# about a unit that may never have installed (see the luks) rows below).
assert "#7674/#8054/#6894/#8079 the shared reader has exactly 8 call sites (flip confirm + flip liveness + execute 2.0 probe + heartbeat + LUKS confirm + LUKS liveness + registry-probe probe + heartbeat), got $FLQ_SITES" \
  "[[ '$FLQ_SITES' -eq 8 ]]"
FLQ_LUKS_SITES=$(grep -cE '^[[:space:]]*(rows=\$\()?_bs_query_rows "\$[A-Za-z_]+" inngest-luks-cutover [0-9]+\)' "$BODY_SH") || true
assert "#6894 the two LUKS call sites pass the CUTOVER tag (never the flip tag), got $FLQ_LUKS_SITES" \
  "[[ '$FLQ_LUKS_SITES' -eq 2 ]]"
FLQ_FLIP_SITES=$(grep -cE '^[[:space:]]*(rows=\$\()?_bs_query_rows "\$[A-Za-z_]+" inngest-cutover-flip 50\)' "$BODY_SH") || true
assert "#7674 the confirm + liveness call sites pass the flip tag and the one-page limit unchanged, got $FLQ_FLIP_SITES" \
  "[[ '$FLQ_FLIP_SITES' -eq 2 ]]"
FLV_SITES=$(grep -cE '^[[:space:]]+FLIP_LIVENESS_N="?\$\(_flip_liveness_count' "$ARM_FILE") || true
assert "arm) reads liveness via _flip_liveness_count exactly once, got $FLV_SITES" \
  "[[ '$FLV_SITES' -eq 1 ]]"
FLV_LN=$(grep -nE '^[[:space:]]+FLIP_LIVENESS_N=' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
FLD_LN=$(grep -nE '^[[:space:]]+FL_OUTCOME=' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
assert "arm) the liveness reader is invoked BEFORE flush_latch_decide (H is never stale/unset)" \
  "[[ -n '$FLV_LN' && -n '$FLD_LN' && '$FLV_LN' -lt '$FLD_LN' ]]"
assert "arm) flush_latch_decide is called with BOTH signals (a one-arg call is the old fail-open)" \
  "grep -qE 'flush_latch_decide \"\\\$FLUSH_LATCH_N\" \"\\\$FLIP_LIVENESS_N\"' '$ARM_FILE'"
assert "arm) no G3.7 outcome arm carries its own exit (the gate decides)" \
  "! grep -qE '^[[:space:]]+(clear|latched|unreadable|silent)\\)[^#]*exit 1' '$ARM_FILE'"
# shellcheck disable=SC2016  # literal search pattern, not an expansion (G3ABORT_LN precedent)
FL_GATE_LN=$(grep -nF 'if [[ "$FL_OUTCOME" != "clear" ]]; then exit 1; fi' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
FL_PGW_LN=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
FL_ARMW_LN=$(grep -nE "secrets set INNGEST_CUTOVER_FLIP " "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
assert "arm) the G3.7 gate precedes the first prod write (pre-G4, not merely pre-G5)" \
  "[[ -n '$FL_GATE_LN' && -n '$FL_PGW_LN' && '$FL_GATE_LN' -lt '$FL_PGW_LN' ]]"
assert "arm) the G3.7 gate precedes the 'armed' write (the double-fire window it closes)" \
  "[[ -n '$FL_GATE_LN' && -n '$FL_ARMW_LN' && '$FL_GATE_LN' -lt '$FL_ARMW_LN' ]]"
# It must run AFTER G3.6 — both are pre-write refusals, and the cheaper Doppler read should not
# be gated behind a Better Stack round-trip.
FL_DIAG_LN=$(grep -nE 'case "\$\(diag_boot_decide ' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
assert "arm) G3.7 runs after G3.6 (ordering is stated, not incidental)" \
  "[[ -n '$FL_DIAG_LN' && -n '$FL_GATE_LN' && '$FL_DIAG_LN' -lt '$FL_GATE_LN' ]]"
# The refusal must name the durable latch and forbid SSH, like every other refusal in this file.
assert "arm) the G3.7 refusal names the monotonic latch as the authority" \
  "grep -qF 'G3.7 REFUSING' '$ARM_FILE' && grep -qE 'G3\\.7 REFUSING.*/mnt/data' '$ARM_FILE'"
assert "arm) the G3.7 refusal forbids SSH (hr-no-ssh-fallback-in-runbooks)" \
  "grep -qE 'G3\\.7 REFUSING.*Do NOT SSH the host' '$ARM_FILE'"
# DEAD-REMEDIATION GUARD (#6617 class). The refusal tells the operator to re-dispatch with
# FLUSH_LATCH_SINCE set. GitHub does not export repo vars to a step unless the workflow NAMES
# them, so without this mapping the remediation is unperformable and the message is a lie.
assert "#7462 the G3.7 remediation is REACHABLE: FLUSH_LATCH_SINCE is mapped into the step env" \
  "grep -qE '^[[:space:]]+FLUSH_LATCH_SINCE:[[:space:]]*\\\$\{\{[[:space:]]*vars\.FLUSH_LATCH_SINCE[[:space:]]*\}\}' '$WF_YAML'"
assert "arm) the G3.7 refusal names the variable the workflow actually exports" \
  "grep -qE 'G3\\.7 REFUSING.*FLUSH_LATCH_SINCE' '$ARM_FILE'"

# Anti-vacuity floor (harness row H1): a suite whose scenario dispatch silently stopped
# would otherwise report success having evaluated nothing. This counts EVALUATIONS, not
# assertion calls, so gutting g3_case's body cannot satisfy it.
assert "g3_decide scenarios actually dispatched (>=19 evaluations)" "[[ '$G3_EVALS' -ge 19 ]]"
G3_VERDICTS=$((PASS + FAIL - G3_VERDICTS_BEFORE))
assert "g3_decide rows produced >=19 VERDICTS, not just evaluations" "[[ '$G3_VERDICTS' -ge 19 ]]"

# The arm) case must route through the function exactly once — the Assembly contract.
# Anchored on the call shape, not the bare name (which also appears in comments).
G3_CALLS=$(grep -cE '^[[:space:]]+G3_OUTCOME="?\$\(g3_decide ' "$ARM_FILE" || true)
assert "arm) calls g3_decide exactly once (single chokepoint)" "[[ '$G3_CALLS' -eq 1 ]]"

# ============================================================================
# #6178 durability — G3.5 CHANNEL-KEY PARITY HARD GATE. INNGEST_EVENT_KEY +
# INNGEST_SIGNING_KEY are a SHARED app<->host channel token (ADR-100 §4 Amendment),
# NOT isolation-sensitive; op=arm must REFUSE the flip if the app (soleur/prd) and
# host (soleur-inngest/prd) copies diverge — the exact #6178 cutover-502. AC-NOBODY:
# the gate compares via sha256 and NEVER echoes a key value. Asserted against the
# extracted arm) case body (ARM_FILE) so the gate can only pass by living in op=arm.
# ============================================================================
assert "arm) has a G3.5 channel-key parity gate (#6178 durability)" "grep -qF 'G3.5 channel-key parity' '$ARM_FILE'"
assert "arm) G3.5 checks BOTH channel keys (event + signing)" "grep -qE 'for CK in INNGEST_EVENT_KEY INNGEST_SIGNING_KEY' '$ARM_FILE'"
assert "arm) G3.5 compares by sha256 (never by echoing the value — AC-NOBODY)" "grep -qF 'sha256sum' '$ARM_FILE'"
assert "arm) G3.5 reads the HOST key from soleur-inngest/prd via the arm token" "grep -qE 'DOPPLER_TOKEN=\"\\\$DOPPLER_TOKEN_INNGEST_ARM\" doppler secrets get \"\\\$CK\" -p soleur-inngest -c prd --plain' '$ARM_FILE'"
assert "arm) G3.5 reads the APP key read-through from prd_terraform (no -p/-c on the app get)" "grep -qE 'APP_CK=\\\$\(doppler secrets get \"\\\$CK\" --plain' '$ARM_FILE'"
# Value-silent: both copies masked; NEITHER raw value is ever echoed.
ARM_CK_MASK_N=$(grep -cE '::add-mask::.*(APP_CK|HOST_CK)' "$ARM_FILE" || true)
assert "arm) G3.5 masks BOTH the app + host key values (>=2 ::add-mask::)" "[[ '$ARM_CK_MASK_N' -ge 2 ]]"
assert "arm) G3.5 NEVER echoes a raw channel-key value (no echo of \$APP_CK/\$HOST_CK — AC-NOBODY)" "! grep -qE 'echo[^\"]*\\\$\\{?(APP_CK|HOST_CK)([^_H]|\$)' '$ARM_FILE'"
# The gate is HARD: a mismatch (or unreadable key) fails op=arm closed.
assert "arm) G3.5 is a HARD GATE — a divergence exits op=arm non-zero (PARITY_FAIL)" "grep -qE 'PARITY_FAIL' '$ARM_FILE' && grep -qF 'CHANNEL-KEY PARITY GATE FAILED' '$ARM_FILE'"
# G3.6 (#7462): the diagnostic-boot precondition inngest-bootstrap.sh states in prose and
# nothing enforced. Arming with it set cuts over to a host that adopts no registry.
assert "arm) has a G3.6 diagnostic-boot hard gate" "grep -qF 'G3.6 REFUSING' '$ARM_FILE'"
assert "arm) G3.6 reads INNGEST_DIAGNOSTIC_BOOT from the isolated config via the arm token" "grep -qE 'doppler secrets get INNGEST_DIAGNOSTIC_BOOT -p soleur-inngest -c prd' '$ARM_FILE'"
assert "arm) G3.6 fails CLOSED on an unreadable diagnostic flag" "grep -qF '__UNREADABLE__' '$ARM_FILE'"
G36_LN=$(grep -nF 'G3.6 REFUSING' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
G36_PGW_LN=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | sed -n '1p' | cut -d: -f1) || true
assert "arm) G3.6 refuses BEFORE the first prod write (G4)" "[[ -n '$G36_LN' && -n '$G36_PGW_LN' && '$G36_LN' -lt '$G36_PGW_LN' ]]"
assert "arm) G3.5 cites the #6178 cutover-502 condition in its remediation" "grep -qF 'cutover-502' '$ARM_FILE'"
# The parity gate runs BEFORE the arm writes (G4/G5) — a divergent channel must
# block the flip, never be written past.
PARITY_LN=$(grep -nF 'G3.5 CHANNEL-KEY PARITY GATE FAILED' "$ARM_FILE" | head -1 | cut -d: -f1)
G4_WRITE_LN=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | head -1 | cut -d: -f1)
assert "arm) G3.5 parity gate precedes the G4 POSTGRES_URI write (blocks before arming)" "[[ -n '$PARITY_LN' && -n '$G4_WRITE_LN' && '$PARITY_LN' -lt '$G4_WRITE_LN' ]]"

# D5/C4 environment required-reviewer gate + C5 conditional token env (repo-level, not in the case body).
assert "job gates op=arm/op=rollback on the inngest-cutover environment (D5/C4)" "grep -qE \"environment: .*inputs.op == 'arm'.*inputs.op == 'rollback'.*inngest-cutover\" '$WF'"
assert "DOPPLER_TOKEN_INNGEST_ARM injected conditionally (empty for other ops — C5)" "grep -qE \"DOPPLER_TOKEN_INNGEST_ARM: .*inputs.op == 'arm'.*secrets.DOPPLER_TOKEN_INNGEST_ARM\" '$WF'"

# D1/C1 — op=rollback owns the reverse flip write; op=arm stays FORWARD-ONLY.
assert "rollback writes INNGEST_CUTOVER_FLIP=rollback via stdin to soleur-inngest/prd (D1/C1)" "grep -qE \"printf '%s' 'rollback'\" '$ROLLBACK_FILE' && grep -qE 'doppler secrets set INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd' '$ROLLBACK_FILE'"
assert "rollback G1' writes only when the forward flip is armed/progressed (armed/flipping/flushed/done)" "grep -qE 'armed\\|flipping\\|flushed\\|done' '$ROLLBACK_FILE'"
assert "rollback calls the shared confirm BLOCKING before web re-enable" "grep -qF 'confirm_flip_state \"\$RB_ISO\"' '$ROLLBACK_FILE'"
# ARCH P1 fix: Half (B) web re-enable runs UNCONDITIONALLY for a non-forward state (aborted/unset) —
# the documented P0-3 recovery. Assert the rollback body reaches the web re-enable AND the non-forward
# branch proceeds there (no exit 1 in that branch).
assert "rollback reaches Half (B) web re-enable" "grep -qE 're-enabling inngest across host-set' '$ROLLBACK_FILE'"
assert "rollback non-forward branch (aborted/unset) proceeds to Half B — P0-3 recovery, no exit 1" "grep -qF 'documented P0-3 aborted-state recovery; proceeding to the web re-enable' '$ROLLBACK_FILE'"
assert "rollback withholds web re-enable on an unconfirmed rolled-back (no double-fire)" "grep -qF 'WITHHOLDING the web re-enable' '$ROLLBACK_FILE'"
assert "rollback never re-writes POSTGRES_URI/HEARTBEAT (reverse writes ONLY the flip value)" "! grep -qE 'secrets set INNGEST_(POSTGRES_URI|HEARTBEAT_URL)' '$ROLLBACK_FILE'"
assert "op=arm is FORWARD-ONLY: the arm block never writes the reverse flip 'rollback'" "! grep -qE \"printf '%s' 'rollback'\" '$ARM_FILE'"

# #6552 — op=rollback DELETES the armed INNGEST_HEARTBEAT_URL (inverse of op=arm G4, :760) so a
# rolled-back dark host stops being a SECOND pusher on the shared Better Stack heartbeat monitor.
# The delete MUST be UNCONDITIONAL: op=arm writes the URL BEFORE the FSM runs, so it persists in
# aborted / partial-arm / re-dispatch states that the forward-state inner case arm skips. This suite
# is static, so "runs on an aborted-state rollback" is proven structurally: the delete lives in the
# Half-B tail (after the inner Half-A esac) and NOT inside the armed|flipping|flushed|done) arm.
FWD_ARM_FILE="$(mktemp)"; SCRATCH+=("$FWD_ARM_FILE")
awk '/^[[:space:]]+armed\|flipping\|flushed\|done\)$/,/^[[:space:]]+;;$/' "$WF" > "$FWD_ARM_FILE"
FWD_ARM_N=$(wc -l < "$FWD_ARM_FILE" | tr -d '[:space:]')
TAIL_FILE="$(mktemp)"; SCRATCH+=("$TAIL_FILE")
awk '/^[[:space:]]*esac$/,0' "$ROLLBACK_FILE" > "$TAIL_FILE"
TAIL_N=$(wc -l < "$TAIL_FILE" | tr -d '[:space:]')
assert "#6552 rollback DELETEs INNGEST_HEARTBEAT_URL from soleur-inngest/prd (inverse of arm G4)" "grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL -p soleur-inngest -c prd' '$ROLLBACK_FILE'"
assert "#6552 delete is value-silent (--yes + stdout redirected)" "grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL.*--yes.*>/dev/null' '$ROLLBACK_FILE'"
assert "#6552 forward-state inner arm extraction is non-vacuous (F6)" "[[ '$FWD_ARM_N' -gt 3 ]]"
assert "#6552 delete is UNCONDITIONAL — NOT nested in the armed|flipping|flushed|done) case arm" "! grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL' '$FWD_ARM_FILE'"
assert "#6552 after-inner-esac tail is non-vacuous" "[[ '$TAIL_N' -gt 3 ]]"
assert "#6552 delete runs in the unconditional Half-B tail (after inner esac) — reached for aborted/unset/re-dispatch" "grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL' '$TAIL_FILE'"

# --- #7228: op=rollback PAUSES the consumer heartbeat -----------------------------------------
# THE FALSE PAGE. betteruptime_heartbeat.inngest_consumer is fed by inngest-consumer-probe.timer
# on the WEB host, which pings ONLY while 10.0.1.40 serves a non-empty registry and suppresses
# otherwise — the property that makes it detect #7228, and the reason a DELIBERATE rollback trips
# it. The rollback exists to stop the dedicated scheduler; the probe correctly suppresses; and
# ~4min later (period 180 + grace 60) the operator is paged for the state they just requested. A
# monitor that pages on intended operator actions is one the operator learns to ignore.
#
# Same UNCONDITIONAL requirement as the delete above, and proven the same structural way: op=arm
# can leave the system in aborted / partial-arm / re-dispatch states that the forward-state inner
# case arm skips, and the feeder is silenced in all of them.
# Asserted per-token, NOT as one `PATCH.*heartbeats/` regex: grep is line-oriented and the call
# is wrapped across continuations, so the combined pattern can only ever match by accident of
# formatting — it would go RED on a `terraform fmt`-style rewrap of correct code, and it proved
# exactly that during authoring.
assert "#7228 rollback PAUSEs the consumer heartbeat (else a deliberate rollback pages the operator)" \
  "grep -qE '^[[:space:]]*(elif )?curl .*-X PATCH' '$ROLLBACK_FILE' && grep -qF 'api/v2/heartbeats/' '$ROLLBACK_FILE' && grep -qF '\"paused\":true' '$ROLLBACK_FILE'"
assert "#7228 the pause targets the consumer monitor BY NAME (survives a terraform recreate that changes the id)" \
  "grep -qF 'soleur-inngest-consumer-prd' '$ROLLBACK_FILE'"
assert "#7228 pause is UNCONDITIONAL — NOT nested in the armed|flipping|flushed|done) case arm" \
  "! grep -qF 'soleur-inngest-consumer-prd' '$FWD_ARM_FILE'"
assert "#7228 pause runs in the unconditional Half-B tail — reached for aborted/unset/re-dispatch" \
  "grep -qF 'soleur-inngest-consumer-prd' '$TAIL_FILE'"
# Fail-OPEN, matching the URL delete: an un-paused monitor pages the operator, which is strictly
# less severe than withholding the safety-critical web re-enable. A `curl -f` whose failure
# aborted the script would invert that trade.
assert "#7228 a failed pause WARNs and does not block the web re-enable" \
  "grep -qE '::warning::op=rollback: PATCH paused=true' '$ROLLBACK_FILE'"
# The API token is masked before any use — the same F7 discipline as the PG/HB captures at G2.
# -A4, not -A1: the mask is now preceded by its own rationale comment. The property is that the
# mask lands BEFORE any use, not that it is literally the next line.
assert "#7228 BETTERSTACK_API_TOKEN is masked immediately after capture, before any use" \
  "grep -A4 'BS_API=\$(doppler secrets get BETTERSTACK_API_TOKEN' '$ROLLBACK_FILE' | grep -cF '::add-mask::' >/dev/null"
# The read must be SCOPED: this was the only Doppler read in the file without -p/-c, so it
# depended on ambient config the workflow does not document, while the warning beneath it named
# prd_terraform explicitly. Fail-open is right here; an unscoped read made it the likely path.
assert "#7228 the BETTERSTACK_API_TOKEN read is explicitly scoped to soleur/prd_terraform" \
  "grep -qF 'doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform' '$ROLLBACK_FILE'"
# And the mask is guarded: an unconditional add-mask on an empty read emits a bare directive.
assert "#7228 the mask is guarded on a non-empty read (no bare ::add-mask:: on failure)" \
  "grep -qF '[[ -n \"\$BS_API\" ]] && printf '\"'\"'::add-mask::' '$ROLLBACK_FILE'"
# THE ASYMMETRY IS DELIBERATE. op=arm must NOT unpause: ADR-117 unpauses only after a REAL beat
# is measured, and arming before the FSM runs is the green-but-inert monitor #6537 spent nine days
# as. This asserts the arm path contains no unpause, so a future edit "restoring symmetry" reds.
assert "#7228 op=arm does NOT unpause the consumer heartbeat (ADR-117: never armed ahead of a real beat)" \
  "! grep -qE '\"paused\":[[:space:]]*false' '$ARM_FILE'"

# ===========================================================================
# #6617 — standalone read-only probe ops (registry-probe, doublefire-probe)
#
# These exist so double-scheduler state is provable BEFORE the maintenance
# window. Previously the only route to the registry signal was op=execute,
# which then proceeds to capture + quiesce.
#
# Anchoring is LOAD-BEARING: `registry-probe` already appears many times as
# the hook NAME `inngest-registry-probe`, so an unanchored grep false-passes
# against a file where the op was never added. Every assertion below anchors
# on the enum-item shape (`^  - <op>$`) or the case-arm shape (`^  <op>)`),
# neither of which the hook name can produce.
# ===========================================================================
PROBE_ARMS_FILE="$(mktemp)"; SCRATCH+=("$PROBE_ARMS_FILE")
awk '/^[[:space:]]+registry-probe\)$/,/^[[:space:]]+rearm\)$/' "$WF" > "$PROBE_ARMS_FILE"
PROBE_ARMS_N=$(wc -l < "$PROBE_ARMS_FILE" | tr -d '[:space:]')
# #8079 D7 — the read-only contract is about what these arms EXECUTE, and the dark arm's
# remedies legitimately NAME tools in prose ("gh run list …", "doppler run … inngest-host-state.sh").
# A regex over the raw region conflates a tool named in prose with a tool invoked. So every
# tool/body/loop predicate below reads PROBE_ARMS_CODE: comment lines dropped, the quoted argument
# of every `echo "…"` / `printf "…"` emptied, escaped-quote aware (the LINE survives — the guarded
# `source … || { echo "::error::…"; exit 1; }` is one physical line and line-stripping would hide a
# real invocation), and backslash continuations joined so a multi-line curl is one logical line.
# Positive control two lines down: the strip must have REMOVED something, or it is a no-op that
# reads as coverage.
# The emptier REFUSES a string carrying `$(` or a backtick: a command substitution inside an
# annotation argument is a real invocation (review of #8079 found `echo "… $(gh run list …)"`
# scored 0 by the first regex). Single-sourced here; the mutation rows' code view uses the same.
_ECHO_EMPTY_RE='s/(echo|printf)[[:space:]]+"([^"\\$`]|\\.|\$[^(`])*"/\1 "…"/g'
_probe_arms_code_of() {  # $1 = arms file → stdout: comment-stripped, echo-args emptied, continuations joined
  grep -v '^[[:space:]]*#' "$1" \
    | sed -E "$_ECHO_EMPTY_RE" \
    | sed -e ':a' -e '/\\$/N; s/\\\n//; ta'
}
PROBE_ARMS_CODE="$(mktemp)"; SCRATCH+=("$PROBE_ARMS_CODE")
_probe_arms_code_of "$PROBE_ARMS_FILE" > "$PROBE_ARMS_CODE"
_PAC_STRIPPED=$(( $(wc -c < "$PROBE_ARMS_FILE") - $(wc -c < "$PROBE_ARMS_CODE") ))
assert "#8079 PROBE_ARMS_CODE strip is non-vacuous (removed $_PAC_STRIPPED bytes of comments/annotation prose)" "[[ '$_PAC_STRIPPED' -gt 2000 ]]"
assert "#8079 the emptier keeps a \$(…) inside an annotation string (a nested tool call stays visible to the tool census) and empties a plain one" \
  "[[ \$(printf '%s\n' 'echo \"a \$(gh api x) b\"' | sed -E \"\$_ECHO_EMPTY_RE\") == *'gh api x'* && \$(printf '%s\n' 'echo \"plain gh api x\"' | sed -E \"\$_ECHO_EMPTY_RE\") == 'echo \"…\"' ]]"

assert "#6617 choice includes registry-probe" "grep -qE '^[[:space:]]+-[[:space:]]*registry-probe\$' '$WF'"
assert "#6617 choice includes doublefire-probe" "grep -qE '^[[:space:]]+-[[:space:]]*doublefire-probe\$' '$WF'"
assert "#6617 registry-probe case arm exists" "grep -qE '^[[:space:]]+registry-probe\)' '$WF'"
assert "#6617 doublefire-probe case arm exists" "grep -qE '^[[:space:]]+doublefire-probe\)' '$WF'"
assert "#6617 probe-arm extraction is non-vacuous" "[[ '$PROBE_ARMS_N' -gt 20 ]]"

# --- Read-only contract, expressed as EFFECTS not curl SPELLING (B-AC5) ---
#
# An earlier revision asserted absence of specific TOKENS. Each pinned one
# spelling, so all of these survived with the suite fully green:
#   wget --post-data=...          (a different tool entirely)
#   doppler --project X ...       (an interposed flag breaks the token adjacency)
#   while [ $n -lt 3 ]            (a different loop keyword)
#   PAYLOAD=<the JSON capture form the workflow ACTUALLY uses> — the bare
#     mode=capture token occurs ONLY in comments, so that assertion could never
#     have fired: vacuous by construction.
# The contract is "these arms cause no side effects", so assert that directly —
# a WHITELIST of permitted network calls, plus denials of egress tools and of
# any request-body flag.

# 1. Exactly two network calls, both bounded GET curls. Counting the whitelist
#    AND the total tool invocations together means an added call of ANY shape
#    fails one of them: not-a-bounded-GET, or an extra tool.
assert "#6617 probe arms make exactly 2 network/tool calls" "[[ \"\$(grep -cE '(^|[^a-z-])(curl|wget|nc|ncat|socat|python3?|perl|gh|aws|doppler|hcloud)[[:space:]]' '$PROBE_ARMS_CODE')\" == '2' ]]"
assert "#6617 both are curl -X GET" "[[ \"\$(grep -c -- '-X GET' '$PROBE_ARMS_FILE')\" == '2' ]]"
assert "#6617 both are bounded (--max-time)" "[[ \"\$(grep -c -- '--max-time' '$PROBE_ARMS_FILE')\" == '2' ]]"

# 2. No request body, by any tool or flag spelling.
assert "#6617 probe arms send NO request body (long forms anywhere; -d/-T only judged on a curl line — mktemp -d is not a body)" "! grep -qE '(^|[[:space:]])(--data|--data-binary|--data-raw|--data-urlencode|--post-data|--post-file|--upload-file)([[:space:]]|=)' '$PROBE_ARMS_CODE' && ! grep -E '(^|[^a-z-])curl[[:space:]]' '$PROBE_ARMS_CODE' | grep -cE '[[:space:]](-d|-T)([[:space:]]|=)' >/dev/null"
assert "#6617 probe arms use NO non-GET method flag" "! grep -qE '(-X|--request)[[:space:]]*(POST|PUT|PATCH|DELETE)' '$PROBE_ARMS_FILE'"

# 3. No mutating tool present at all, whatever its flag order.
# Since #8079 the dark path performs two Better Stack reads THROUGH `_bs_query_rows` (a function
# defined outside these arms); the dark render's doppler.argv row pins those two and no more. This
# row therefore measures the arms' OWN code: no literal doppler invocation, i.e. no read this
# suite has not pinned by argv and no `doppler secrets set` write.
assert "#6617 probe arms' own code carries NO literal doppler invocation (the two dark-path reads go through _bs_query_rows, pinned by argv)" "! grep -qE '(^|[^a-z-])doppler([[:space:]]|\$)' '$PROBE_ARMS_CODE'"
assert "#6617 probe arms invoke NO wget/nc/socat egress" "! grep -qE '(^|[^a-z-])(wget|ncat|socat)([[:space:]]|\$)' '$PROBE_ARMS_CODE'"

# 4. No cutover-state transition — matching the JSON form the workflow uses,
#    not the bare token that only ever appears in prose.
assert "#6617 probe arms perform NO reminder capture" "! grep -qE '\"mode\"[[:space:]]*:[[:space:]]*\"capture\"|mode=capture' '$PROBE_ARMS_FILE'"
assert "#6617 probe arms perform NO deploy-hook write" "! grep -qE 'hooks/deploy' '$PROBE_ARMS_FILE'"
assert "#6617 probe arms touch NO flip/quiesce/rearm hook" "! grep -qE 'inngest-(arm|flip|quiesce|rearm|wiped)' '$PROBE_ARMS_FILE'"

# --- Single-shot: no retry loop, whatever the keyword (B-AC4) ---
# Anchored at LINE START: a loop keyword only ever begins a statement there.
# The unanchored form matched the word "for" inside this arm's own comments —
# the same comment-vs-code collision cq-assert-anchor-not-bare-token warns about.
assert "#6617 probe arms add NO retry loop (the one emit-file read loop is allowlisted by its exact header)" "! grep -vF 'while IFS= read -r _rpg_line; do' '$PROBE_ARMS_CODE' | grep -cE '^[[:space:]]*(for|while|until)[[:space:]]' >/dev/null"

# --- Reviewer-gate membership (B-AC3, amended #7228) -----------------------------------------
# This was a byte-identity pin on the environment: expression, whose purpose is to stop the
# approval gate being WIDENED — i.e. to stop ops being added that write prod without review.
# #7228 adds op=resume, which writes INNGEST_CUTOVER_FLIP=flushed and therefore AUTHORIZES a prod
# scheduler start: it must be INSIDE the gate, not outside it. A byte-identity pin cannot express
# "this set may only grow toward MORE review", so it is replaced by a membership assertion in
# both directions — every prod-writing op is gated, and the read-only probe ops still are not.
# That is strictly stronger than the byte pin: it would also catch a REMOVAL, which byte identity
# only caught incidentally.
ENV_EXPR=$(grep -E '^[[:space:]]+environment:' "$WF" | sed -n '1p' || true)
assert "#7228 the environment: expression was located (else these pins are vacuous)" \
  "[[ -n \"\$ENV_EXPR\" ]]"
for _op in arm rollback resume; do
  assert "#7228 prod-writing op '\$_op' is INSIDE the required-reviewer gate" \
    "printf '%s' \"\$ENV_EXPR\" | grep -cF \"inputs.op == '\$_op'\" >/dev/null"
done
assert "#7228 the gate still resolves to the inngest-cutover environment" \
  "printf '%s' \"\$ENV_EXPR\" | grep -cF \"'inngest-cutover'\" >/dev/null"
# THE OP SET IS DUPLICATED IN TWO EXPRESSIONS AND NOTHING TIED THEM TOGETHER (#7674 review).
# `environment:` decides WHO MUST APPROVE; the DOPPLER_TOKEN_INNGEST_ARM expression decides WHO
# GETS THE PROD-WRITE TOKEN. Adding an op to the token expression but not the environment one
# hands that op an arm-capable credential with NO required reviewer — and every pre-existing
# assertion here passed, because they check the two expressions independently. Pin the SETS equal.
ENV_OPS=$(printf '%s' "$ENV_EXPR" | grep -oE "inputs\.op == '[a-z-]+'" | sort -u) || true
TOK_EXPR=$(grep -E 'DOPPLER_TOKEN_INNGEST_ARM:' "$WF" | sed -n '1p') || true
TOK_OPS=$(printf '%s' "$TOK_EXPR" | grep -oE "inputs\.op == '[a-z-]+'" | sort -u) || true
assert "#7674 the token expression was located (else the parity row below is vacuous)" \
  "[[ -n '$TOK_EXPR' ]]"
assert "#7674 the reviewer-gated op set is non-empty (anti-vacuity for the parity row)" \
  "[[ -n '$ENV_OPS' ]]"
assert "#7674 environment: and DOPPLER_TOKEN_INNGEST_ARM gate the SAME op set (no ungated arm token)" \
  "[[ '$ENV_OPS' == '$TOK_OPS' ]]"
# A single `continue-on-error: true` on the one run: step turns EVERY guard's exit 1 into a green
# job — the whole gate sequence tolerated at once. Nothing forbade it.
assert "#7674 no step tolerates failure (a continue-on-error would green-light every refused gate)" \
  "! grep -qE '^[[:space:]]*continue-on-error:' '$WF_YAML'"

assert "#6617 neither probe op appears in the environment: expression" "! grep -E '^[[:space:]]+environment:' '$WF' | grep -cE 'registry-probe|doublefire-probe' >/dev/null"

# --- Scope caveat carried verbatim from op=verify 2.6 (B-AC7) ---
# #6921 D5: the caveat names the web HOST (web-1's colocated scheduler), not web-2 — the cattle web-2
# was born with web_colocate_inngest=false and has no scheduler to double-fire.
assert "#6617 doublefire-probe carries the 2.6 scope caveat" "grep -qF 'NOT a web-host double-fire detector' '$PROBE_ARMS_FILE'"

# --- (#6178) registry_empty is a BOOLEAN — never read it with jq `//`. `false // "true"` = "true"
# in jq (it treats boolean false as empty), so `.registry_empty // "<default>"` makes a HEALTHY
# non-empty registry (registry_empty:false) read as EMPTY, and the op=rearm/op=verify
# precondition can NEVER pass against the real post-2.4 backend. The correct shape reads the
# boolean directly behind a has() guard. Assert the anti-pattern is absent anywhere in the WF. ---
# Strip shell-comment lines first — the fix's own explanatory comment quotes the anti-pattern
# as the thing NOT to do (cq-assert-anchor-not-bare-token), so a raw file-wide grep false-matches
# the documentation. Then match `.registry_empty` immediately followed by jq `//` ANYWHERE on a
# real line — quote-style-agnostic and leading-whitespace-tolerant (a narrower `jq...'` anchor is
# evaded by ` .registry_empty`, a double-quoted program, or a pipe prefix). No legitimate line
# reads this boolean with `//`; the only correct read is bare `.registry_empty`. (Single-line
# only — a jq program split across lines is an accepted residual gap, not a realistic hand-edit.)
assert "no jq '//'-on-boolean read of registry_empty (false // x == x bug, #6178)" \
  "! grep -vE '^[[:space:]]*#' '$WF' | grep -cE '\.registry_empty[[:space:]]*//' >/dev/null"
# And assert BOTH consumer preconditions read the boolean directly (parity — they had drifted).
assert "registry_empty read directly (bare, no //) at least twice (op=rearm + op=verify)" \
  "[[ \"\$(grep -cE \"jq -r '\.registry_empty'\" '$WF')\" -ge 2 ]]"

# ===========================================================================
# #6178 — doublefire_from() EXECUTED, not grepped.
#
# op=verify has never produced a verdict. The window it scanned (cutover - 200d)
# holds ~145,600 runs (measured: 728/day) against a ~18-page budget, and the probe
# is fail-loud on non-exhaustion, so every dispatch died on reason=deadline emitting
# nothing. The fix narrows the window and anchors it on an instant that is actually
# trustworthy -- which means the anchor arithmetic is now load-bearing and a static
# grep is not enough to pin it. This harness EXTRACTS the function and RUNS it,
# mirroring call_build_request_body in the probe suite.
#
# THE ANCHOR IS A TRANSITION ROW, NOT "THE EARLIEST FLIP ROW". inngest-cutover-flip
# runs on a ~30s on-host timer and emits flag:"done" reason:"noop-done" on EVERY
# tick (~2,880 rows/day; a 400-row query spans ~4 hours). Anchoring on the earliest
# row in any practical --limit window would therefore resolve to a few hours ago
# instead of the coexistence start -- a window NARROWER than truth, which is the
# unsafe direction and exactly the vacuous-clean AC-V3 exists to prevent. The
# transition reasons (flip-complete / flushed-resume-no-reflush / rolled-back /
# dbsize-nonzero / flushall-failed / refuse-rearm-after-done) are disjoint from the
# noop-* heartbeat reasons. Measured 2026-07-24: exactly ONE transition row exists
# (done/flip-complete @ 2026-07-24 10:20:51Z) against thousands of heartbeats.
# ===========================================================================
DF_HARNESS_SRC="$(mktemp)"; SCRATCH+=("$DF_HARNESS_SRC")
{
  sed -n '/^          _flip_transition_dt() {$/,/^          }$/p' "$WF"
  sed -n '/^          doublefire_from() {$/,/^          }$/p' "$WF"
} > "$DF_HARNESS_SRC"
DF_HARNESS_N=$(wc -l < "$DF_HARNESS_SRC" | tr -d '[:space:]')

df_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}
# Tolerance form for the now-relative cases (floor / wide), which cannot be pinned to a
# literal without re-deriving the implementation inside its own test.
df_near() {  # $1=desc $2=actual_iso $3=expected_epoch $4=tol_s
  local a d
  a=$(date -u -d "$2" +%s 2>/dev/null || echo 0)
  d=$(( a - $3 )); (( d < 0 )) && d=$(( -d ))
  if (( d <= $4 )); then echo "  PASS: $1"; PASS=$((PASS + 1));
  else echo "  FAIL: $1 (actual=$2, delta=${d}s > ${4}s)"; FAIL=$((FAIL + 1)); fi
}

# $1=fallback_days $2=mode $3=CRON_PERIOD $4=CUTOVER_WINDOW_FROM $5=stub FSM dt ("" => no row)
DF_OUT=""; DF_RC=0
# $6 = CUTOVER_ANCHOR_FROM override. It is an explicit PARAMETER, not a `VAR=x call_...`
# prefix: bash persists assignment prefixes across FUNCTION calls (unlike external commands),
# so the prefix form would leak the override into every later case in this file.
call_doublefire_from() {
  local fb="$1" mode="$2" period="$3" winfrom="$4" stubdt="$5" anchorfrom="${6:-}"
  # `set +e` must be in the CALLING shell: under `set -e` a failing command substitution
  # aborts the suite at the assignment, so the fail-closed cases (which fail BY DESIGN)
  # would kill the runner instead of being asserted.
  set +e
  DF_OUT=$(
    eval "$(cat "$DF_HARNESS_SRC")"
    # Stub the Better Stack read AFTER the eval so it overrides the real definition --
    # the suite must never touch doppler or the network.
    _flip_transition_dt() {
      [[ -n "$stubdt" ]] || return 1
      printf '%s\n' "$stubdt"
    }
    export CUTOVER_CRON_PERIOD_SECONDS="$period"
    export CUTOVER_WINDOW_FROM="$winfrom"
    export CUTOVER_ANCHOR_FROM="$anchorfrom"
    doublefire_from "$fb" "$mode" 2>&1
  )
  DF_RC=$?
  set -e
}

echo "--- #6178 doublefire_from() executed harness ---"

# Harness self-check FIRST: without it every assertion below could pass vacuously
# against an empty extraction (the v1 lesson, generalized).
assert "#6178 doublefire_from harness extraction is non-vacuous (>20 lines)" "[[ '$DF_HARNESS_N' -gt 20 ]]"
assert "#6178 extraction actually yields a callable doublefire_from" \
  "bash -c 'eval \"\$(cat \"$DF_HARNESS_SRC\")\"; declare -F doublefire_from >/dev/null'"
assert "#6178 extraction actually yields a callable _flip_transition_dt" \
  "bash -c 'eval \"\$(cat \"$DF_HARNESS_SRC\")\"; declare -F _flip_transition_dt >/dev/null'"

# --- FSM-derived anchor x CRON_PERIOD. The anchor is deliberately far in the past so
# bucket_floor(anchor) - 2*period is strictly earlier than the now-relative floor and
# therefore WINS the min() -- which makes the expected ISO a deterministic literal
# rather than a re-derivation of the implementation. ---
call_doublefire_from 1 fsm 1200 "" "2026-01-15 12:34:56.123456"
df_eq "fsm anchor, period=1200 -> bucket_floor - 2*period, source=fsm" "2026-01-15T11:40:00Z fsm" "$DF_OUT"
call_doublefire_from 1 fsm 3600 "" "2026-01-15 12:34:56.123456"
df_eq "fsm anchor, period=3600 -> bucket_floor - 2*period, source=fsm" "2026-01-15T10:00:00Z fsm" "$DF_OUT"

# --- var-sourced anchor (no FSM row: Better Stack retention miss) ---
call_doublefire_from 1 fsm 1200 "2026-02-20T08:05:00Z" ""
df_eq "var anchor, period=1200, source=var" "2026-02-20T07:20:00Z var" "$DF_OUT"
call_doublefire_from 1 fsm 3600 "2026-02-20T08:05:00Z" ""
df_eq "var anchor, period=3600, source=var" "2026-02-20T06:00:00Z var" "$DF_OUT"

# --- precedence: the FSM row WINS over the operator variable. The FSM instant is stamped
# on 10.0.1.40's journald -- the same clock that stamps startedAt -- which collapses the
# operator-clock-skew class entirely. ---
call_doublefire_from 1 fsm 1200 "2026-02-20T08:05:00Z" "2026-01-15 12:34:56.123456"
df_eq "fsm takes precedence over CUTOVER_WINDOW_FROM" "2026-01-15T11:40:00Z fsm" "$DF_OUT"

# --- FAIL CLOSED: no anchor derivable. There is NO safe wide fallback -- a 7-day window is
# ~5,100 runs ~= 51 pages ~= 214s, so scanning it would trade a deadline abort for a
# deadline abort while LOOKING safer. ---
call_doublefire_from 1 fsm 1200 "" ""
assert "#6178 no anchor at all -> FAILS CLOSED (non-zero)" "[[ '$DF_RC' -ne 0 ]]"
assert "#6178 fail-closed names the operator remedy (CUTOVER_WINDOW_FROM)" "grep -q 'CUTOVER_WINDOW_FROM' <<<\"\$(cat <<'EOF'
$DF_OUT
EOF
)\""
call_doublefire_from 1 fsm 1200 "not-a-timestamp" ""
assert "#6178 malformed CUTOVER_WINDOW_FROM -> FAILS CLOSED (never a silent 365d probe default)" "[[ '$DF_RC' -ne 0 ]]"

# --- min() floor is the SKEW clamp: an operator anchor in the FUTURE can only ever WIDEN
# the window, never narrow it below now - FALLBACK. ---
NOW_E=$(date -u +%s)
call_doublefire_from 1 fsm 1200 "" "$(date -u -d '+2 days' '+%Y-%m-%d %H:%M:%S')"
# The floor must RECORD which source it clamped, not overwrite it. With a 1-day fallback the
# floor wins on every dispatch within ~24h of the cutover — the intended usage — so a bare
# `floor` would make "was an fsm anchor derivable at all?" unanswerable in exactly the regime
# AC-V3 asks the operator to demonstrate it in.
df_eq "future (skewed) anchor clamps to the floor, provenance PRESERVED" "floor(fsm)" "${DF_OUT##* }"
df_near "future-anchor clamp lands at now - 1d" "${DF_OUT%% *}" "$(( NOW_E - 86400 ))" 120
call_doublefire_from 1 fsm 1200 "$(date -u -d '+2 days' '+%Y-%m-%dT%H:%M:%SZ')" ""
df_eq "floor clamp records a var-sourced anchor distinctly" "floor(var)" "${DF_OUT##* }"

# --- CUTOVER_ANCHOR_FROM is the operator's NARROWING lever and must OUTRANK the fsm row.
# Without precedence it is inert on the normal path, which made the page-1 gate's remediation
# dead advice — the same defect class this change removed from the deadline surfaces. ---
call_doublefire_from 1 fsm 1200 "2026-02-20T08:05:00Z" "2026-01-15 12:34:56.123456" "2026-03-10T04:00:00Z"
df_eq "CUTOVER_ANCHOR_FROM overrides BOTH the fsm row and CUTOVER_WINDOW_FROM" "2026-03-10T03:20:00Z override" "$DF_OUT"
call_doublefire_from 1 fsm 1200 "" "2026-01-15 12:34:56.123456" "not-a-timestamp"
df_eq "an unparseable override falls through to the fsm row (never silently wide)" "2026-01-15T11:40:00Z fsm" "$DF_OUT"

# --- mode fails CLOSED on an unrecognized value (fail-open on the safety-relevant arg would
# route a typo onto the UNANCHORED wide path). ---
call_doublefire_from 1 "" 1200 "" "2026-01-15 12:34:56.123456"
assert "#6178 empty mode FAILS CLOSED (no silent wide default)" "[[ '$DF_RC' -ne 0 ]]"
call_doublefire_from 1 FSM 1200 "" "2026-01-15 12:34:56.123456"
assert "#6178 a typo'd mode FAILS CLOSED rather than selecting the wide path" "[[ '$DF_RC' -ne 0 ]]"

# --- per-arm fallback: the pre-cutover dark-host detector keeps its wide window. There is
# no coexistence anchor to derive BEFORE the cutover, so mode=wide must not attempt one
# (and must make no doppler call). ---
call_doublefire_from 200 wide 1200 "" ""
df_eq "op=doublefire-probe (mode=wide) reports source=wide" "wide" "${DF_OUT##* }"
df_near "mode=wide keeps the 200-day window" "${DF_OUT%% *}" "$(( NOW_E - 200 * 86400 ))" 120
assert "#6178 mode=wide exits 0 (never fail-closed -- no anchor exists pre-cutover)" "[[ '$DF_RC' -eq 0 ]]"

# --- invalid fallback_days is a programming error, not an operator input: fail loud. ---
call_doublefire_from "" fsm 1200 "" "2026-01-15 12:34:56.123456"
assert "#6178 missing fallback_days -> non-zero (arg is REQUIRED, not an ambient global)" "[[ '$DF_RC' -ne 0 ]]"

# --- PURITY (the function's standing contract is 'NEVER echoes a raw Better Stack row').
# _flip_transition_dt must surface ONLY the dt field. ---
# The negative must NOT be `jq[^|]*\.raw` — `[^|]` cannot cross a pipe, and the live
# expression IS piped (`jq -r 'select(type=="object") | .dt'`), so mutating .dt -> .raw
# left that guard green. Any `.raw` at all is a purity violation here.
assert "#6178 _flip_transition_dt extracts ONLY .dt (never .raw, pipe-crossing safe)" \
  "grep -qE '\\.dt' '$DF_HARNESS_SRC' && ! grep -qE '\\.raw' '$DF_HARNESS_SRC'"
assert "#6178 _flip_transition_dt greps TRANSITION reasons, not the noop-* heartbeat" \
  "grep -qF 'flip-complete' '$DF_HARNESS_SRC' && ! grep -qE '\"reason\":\"noop' '$DF_HARNESS_SRC'"
assert "#6178 _flip_transition_dt uses the QUOTED reason form (noop-rolled-back contains rolled-back)" \
  "grep -qF '\"reason\":\"rolled-back\"' '$DF_HARNESS_SRC'"

# --- EMITTER PARITY (cross-file). ------------------------------------------------------------
# The deriver's reason set is a COPY of a vocabulary owned by inngest-cutover-flip.sh. Spot-checks
# for individual reasons ("does it grep flip-complete?") cannot detect a MISSING member — which is
# exactly how `unexpected-exit` was omitted. That one matters most: it is the ERR-trap terminal
# transition, and the ONLY row emitted on the path where `start_server` SUCCEEDS (coexistence
# begins) but the following `flag_set` — a Doppler network write — fails. Skipping it makes the
# deriver return a LATER row, i.e. a window NARROWER than the coexistence region: the unsafe
# direction, and precisely the vacuous clean AC-V3 exists to reject.
#
# Including a reason can only move the anchor EARLIER (earliest(A ∪ B) ≤ earliest(A)), so a
# SUPERSET is always safe — hence the assertion is one-directional: emitter ⊆ grep set.
# Precedent: the "Emitter parity" assert already used for confirm_flip_state's FLAG keys.
EMITTER_SH="$REPO_ROOT/apps/web-platform/infra/inngest-cutover-flip.sh"
assert "#6178 the flip emitter exists (parity source)" "[[ -f '$EMITTER_SH' ]]"
EMIT_REASONS_FILE="$(mktemp)"; SCRATCH+=("$EMIT_REASONS_FILE")
# emit_state <exit_code> <dbsize> <reason> <flag> — take the 3rd positional, strip the
# interpolated `(from=…)` suffix, drop the noop-* heartbeats.
grep -oE 'emit_state [^ ]+ [^ ]+ "[^"]*"' "$EMITTER_SH" \
  | grep -oE '"[^"]*"$' | tr -d '"' | sed 's/(from=.*//' \
  | grep -vE '^noop-' | grep -vE '^$' | sort -u > "$EMIT_REASONS_FILE"
EMIT_REASON_N=$(wc -l < "$EMIT_REASONS_FILE" | tr -d '[:space:]')
# Min-cardinality: an extraction that silently yields nothing would make the parity loop vacuous.
assert "#6178 emitter-reason extraction is non-vacuous (>=6 non-noop reasons, found $EMIT_REASON_N)" "[[ '$EMIT_REASON_N' -ge 6 ]]"
MISSING_REASONS=""
while IFS= read -r _reason; do
  [[ -z "$_reason" ]] && continue
  grep -qF -- "\"reason\":\"$_reason" "$DF_HARNESS_SRC" || MISSING_REASONS="$MISSING_REASONS $_reason"
done < "$EMIT_REASONS_FILE"
assert "#6178 EMITTER PARITY: every non-noop emit_state reason is anchored (missing:${MISSING_REASONS:- none})" \
  "[[ -z '$MISSING_REASONS' ]]"
# Named explicitly as well, so the regression that motivated the parity gate is self-documenting.
# Anchored on the QUOTED grep form, not the bare token: the function's own explanatory comment
# names `unexpected-exit`, so a bare-token check is satisfied by the prose that describes the
# fix even after the fix itself is deleted (measured: deleting the --grep left a bare-token
# assert green while only the parity loop went red).
assert "#6178 the ERR-trap terminal transition (unexpected-exit) is anchored as a GREP, not just named in prose" \
  "grep -qF -- '--grep '\\''\"reason\":\"unexpected-exit'\\''' '$DF_HARNESS_SRC'"
# NEGATIVE control: the parity loop must be able to FAIL. A reason the emitter does not emit
# must not be found in the grep set by accident, proving the loop compares real strings.
assert "#6178 parity loop is discriminating (a non-existent reason is NOT anchored)" \
  "! grep -qF '\"reason\":\"this-reason-does-not-exist' '$DF_HARNESS_SRC'"
# --- (#7761) THE SAME EXTRACTION PINS THE FOLLOW-THROUGH PROBE'S DRIFT GREP SET. -------------
# scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh defines drift as ANY flip-FSM row
# since the boundary other than the op=resume shape, found by one sparse OR-query over a FIXED
# inline term set (DRIFT_GREPS). A reason the emitter gains and the probe does not grep is
# invisible to that query over the whole interval — the runtime cannot fail safe on it, so THIS
# loop is the guard. Read ONLY the `DRIFT_GREPS=( … )` block (a flag-based awk), never the whole
# file: the probe's header table and comments name every reason, and would satisfy a whole-file
# grep with the term itself deleted.
# The probe's set is WIDER than the deriver's: it also greps the off-state heartbeats (every
# `noop-*` except the steady `noop-done`), because a host RESTING off `done` after the cutover is
# drift. So its expected set is extracted separately, keeping those. Each term must be a whole,
# UNCOMMENTED line of the block — a commented-out term, or one that is only a prefix of another,
# satisfies nothing. The probe's absence FAILS: the PR that retires it deletes this block too.
PROBE_7761="$REPO_ROOT/scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh"
PROBE_REASONS_FILE="$(mktemp)"; SCRATCH+=("$PROBE_REASONS_FILE")
grep -oE 'emit_state [^ ]+ [^ ]+ "[^"]*"' "$EMITTER_SH" \
  | grep -oE '"[^"]*"$' | tr -d '"' | sed 's/(from=.*//' \
  | grep -vxF 'noop-done' | grep -vE '^$' | sort -u > "$PROBE_REASONS_FILE"
PROBE_REASON_N=$(wc -l < "$PROBE_REASONS_FILE" | tr -d '[:space:]')
assert "#7761 probe-reason extraction keeps the off-state heartbeats (>= EMIT+3, found $PROBE_REASON_N vs $EMIT_REASON_N)" \
  "[[ '$PROBE_REASON_N' -ge $(( EMIT_REASON_N + 3 )) ]] && grep -qxF 'noop-aborted' '$PROBE_REASONS_FILE'"
_probe_drift_missing() { # <probe-file> -> missing reasons (space-separated), or __NO_BLOCK__
  local block r miss=""
  block="$(awk '/^DRIFT_GREPS=\($/ { f = 1; next } f && /^\)$/ { exit } f' "$1" | grep -vE '^[[:space:]]*#' || true)"
  [[ -n "$block" ]] || { printf '__NO_BLOCK__'; return; }
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    grep -qxF -- "  '\"reason\":\"$r'" <<<"$block" || miss="$miss $r"
  done < "$PROBE_REASONS_FILE"
  printf '%s' "$miss"
}
assert "#7761 the follow-through probe exists (retiring it must delete this block in the same PR)" "[[ -f '$PROBE_7761' ]]"
PROBE_MISSING="$(_probe_drift_missing "$PROBE_7761")"
assert "#7761 PROBE PARITY: every emit_state reason except noop-done is a DRIFT_GREPS term (missing:${PROBE_MISSING:- none})" \
  "[[ -z '$PROBE_MISSING' ]]"
# NEGATIVE controls: deleting a term, or COMMENTING one out, must each red.
_probe_neg="$(mktemp)"; SCRATCH+=("$_probe_neg")
sed "/^  '\"reason\":\"flip-complete'\$/d" "$PROBE_7761" > "$_probe_neg"
PROBE_NEG_MISSING="$(_probe_drift_missing "$_probe_neg")"
assert "#7761 probe parity is discriminating (deleting flip-complete from the block is caught)" \
  "[[ '$PROBE_NEG_MISSING' == *flip-complete* && '$PROBE_NEG_MISSING' != __NO_BLOCK__ ]]"
sed "s/^  '\"reason\":\"noop-aborted'\$/  # '\"reason\":\"noop-aborted'/" "$PROBE_7761" > "$_probe_neg"
PROBE_NEG_MISSING="$(_probe_drift_missing "$_probe_neg")"
assert "#7761 probe parity sees a COMMENTED-OUT off-state term (noop-aborted) as missing" \
  "[[ '$PROBE_NEG_MISSING' == *noop-aborted* ]]"
# The guard revision the emitter stamps and the one the probe demands are one value. Bumping the
# emitter's GUARD_REV while #7761 is open would otherwise post a false `stale_image` FAIL.
EMIT_GUARD=$(sed -nE 's/^readonly GUARD_REV="([0-9]+)"$/\1/p' "$EMITTER_SH")
PROBE_GUARD=$(sed -nE 's/^EXPECTED_GUARD="([0-9]+)"$/\1/p' "$PROBE_7761")
assert "#7761 the probe's EXPECTED_GUARD equals the emitter's GUARD_REV (emitter=$EMIT_GUARD probe=$PROBE_GUARD)" \
  "[[ -n '$EMIT_GUARD' && '$EMIT_GUARD' == '$PROBE_GUARD' ]]"
# --- _flip_transition_dt EXECUTED against a stubbed row source. A static grep for "limit"
# survived a mutation that DELETED the truncation guard outright, which is the whole reason
# this runs the function instead of reading it. `doppler` is stubbed on PATH, so the real
# parsing, the truncation guard and the shape guard all execute with no network. ---
FTD_OUT=""; FTD_RC=0
call_flip_transition_dt() {  # $1 = number of rows the stubbed query returns
  local nrows="$1" bindir; bindir=$(mktemp -d); SCRATCH+=("$bindir")
  cat > "$bindir/doppler" <<STUB
#!/usr/bin/env bash
for ((i=0; i<$nrows; i++)); do
  printf '{"dt":"2026-01-15 12:%02d:56.000000","raw":"{\\\\"message\\\\":{\\\\"flag\\\\":\\\\"done\\\\",\\\\"reason\\\\":\\\\"flip-complete\\\\"}}"}\n' "\$i"
done
STUB
  chmod +x "$bindir/doppler"
  set +e
  FTD_OUT=$(PATH="$bindir:$PATH" bash -c "eval \"\$(cat '$DF_HARNESS_SRC')\"; _flip_transition_dt" 2>&1)
  FTD_RC=$?
  set -e
  rm -rf "$bindir"
}

call_flip_transition_dt 1
df_eq "_flip_transition_dt returns the EARLIEST transition dt" "2026-01-15 12:00:56.000000" "$FTD_OUT"
assert "#6178 _flip_transition_dt exits 0 on a derivable anchor" "[[ '$FTD_RC' -eq 0 ]]"

call_flip_transition_dt 3
df_eq "_flip_transition_dt picks the earliest of several transitions (ascending dt)" "2026-01-15 12:00:56.000000" "$FTD_OUT"

call_flip_transition_dt 0
assert "#6178 _flip_transition_dt fails (no row) when the query returns nothing — caller widens" "[[ '$FTD_RC' -ne 0 ]]"

# TRUNCATION: a FULL page means betterstack-query.sh's newest-N LIMIT may have hidden the
# earliest transition, so the row we would pick is LATER than truth — a NARROWER window,
# the unsafe direction. It must refuse rather than derive an under-covering anchor.
FTD_LIMIT=$(grep -oE 'local limit=[0-9]+' "$DF_HARNESS_SRC" | grep -oE '[0-9]+' | head -1)
assert "#6178 the truncation limit was extracted from the SUT (not hardcoded here)" "[[ '$FTD_LIMIT' =~ ^[0-9]+$ && '$FTD_LIMIT' -gt 1 ]]"
# BOUNDARY PAIR, derived: limit-1 must be accepted, limit must be refused. Sampling only
# {0,1,3,50} left `-ge $limit` indistinguishable from `-ge 4`.
call_flip_transition_dt "$(( FTD_LIMIT - 1 ))"
assert "#6178 a page one row BELOW the limit is still trusted (boundary, limit-1)" "[[ '$FTD_RC' -eq 0 ]]"
call_flip_transition_dt "$FTD_LIMIT"
assert "#6178 _flip_transition_dt REFUSES a full page (truncation could hide the earliest transition)" "[[ '$FTD_RC' -ne 0 ]]"
assert "#6178 a truncated page yields NO anchor (never an under-covering one)" "! grep -qE '^2026-' <<<\"\$(cat <<'EOF'
$FTD_OUT
EOF
)\""

# PURITY: only the dt escapes — never any part of the raw Better Stack row.
call_flip_transition_dt 1
assert "#6178 _flip_transition_dt NEVER echoes a raw row (no reason/flag/message text)" "! grep -qE 'flip-complete|\"flag\"|message' <<<\"\$(cat <<'EOF'
$FTD_OUT
EOF
)\""

# --- Wiring: the harness proves the function BEHAVES, not that anything CALLS it correctly.
# Both arms must pass their fallback EXPLICITLY as $1 (never read an ambient global). ---
# The field split must be CONSUMED, not merely emitted. `DF_FROM="$DF_RAW"` (dropping
# DF_ANCHOR_SOURCE) is invisible to the executed harness, and the shape guard below is what
# makes it fail closed.
assert "#6178 both arms split the two-field emission via read -r (2 sites)" \
  "[[ \"\$(grep -cE 'read -r DF_FROM DF_ANCHOR_SOURCE' '$WF')\" -eq 2 ]]"
# BOTH arms must fail closed on a malformed lower bound. This is the REACHABLE failure the
# previous revision left open: doublefire_from used to end `|| true`, so an empty DF_FROM
# built `?from=` and the probe fell back to its OWN 365-day default — silently restoring the
# unscannable window. `date -u -d ''` SUCCEEDS (today's midnight), so emptiness is not
# self-announcing and a `2>/dev/null` is not a guard.
assert "#6178 BOTH arms carry the fail-closed DF_FROM shape guard (2 sites)" \
  "[[ \"\$(grep -cE 'DF_FROM\" =~ \\^\\[0-9\\]\\{4\\}-\\[0-9\\]\\{2\\}-\\[0-9\\]\\{2\\}T' '$WF')\" -eq 2 ]]"
assert "#6178 BOTH arms abort (exit 1) rather than scanning on a malformed bound" \
  "[[ \"\$(grep -cE 'computed window lower bound is malformed' '$WF')\" -eq 2 ]]"

# --- AC7: the 200-day literal must NOT live in the function body -- it is now a per-arm
# CALLER argument. A file-scoped grep is vacuous here (CUTOVER_WINDOW_FROM alone appears 4x). ---
assert "#6178 AC7: doublefire_from BODY carries no 200-day literal (baseline on main: 2)" \
  "[[ \"\$(grep -cE '200 \\* 86400|200 days ago' '$DF_HARNESS_SRC')\" -eq 0 ]]"

# --- AC8: the window stays OPEN-TOPPED. Passing until= looks like a free cost saving and
# removes the highest-risk region (post-repoint + post-rollback lie AFTER the recorded
# CUTOVER_WINDOW_UNTIL). Do not "tidy" it. ---
assert "#6178 AC8: DF_URL carries no until= parameter (open-topped invariant)" "! grep -qE 'inngest-doublefire-probe\?[^\"]*until=' '$WF'"
assert "#6178 AC8: the open-topped invariant is documented at BOTH call sites" "[[ \"\$(grep -ciE 'open-topped' '$WF')\" -ge 2 ]]"

# --- anchor_source reaches the run log, so a var-sourced or floor-clamped window is
# visible off-box rather than being an invisible property of a green run. ---
assert "#6178 op=verify surfaces anchor_source= (arm-scoped, non-comment)" "grep -qF 'anchor_source=' '$VERIFY_ARM_FILE'"
assert "#6178 op=doublefire-probe surfaces anchor_source= (arm-scoped, non-comment)" "grep -qF 'anchor_source=' '$DFPROBE_ARM_FILE'"

# ===========================================================================
# #6178 SECOND DEFECT — the bucketing jq dies on a null startedAt.
#
# The probe projects {functionID, startedAt} from EVERY returned node. A run that is
# queued, running, or cancelled-before-start carries startedAt:null, and
# fromdateiso8601 throws on it ("strptime/1 requires string inputs", jq exit 5).
# This sat directly behind the window defect on the critical path: narrowing the
# window alone would have moved the failure from reason=deadline to a jq crash, and
# AC-V4 would have recorded "the fix did not work". It was invisible until now only
# because the scan had never once completed far enough to REACH the bucketing step.
#
# Extracted by SHAPE (every single-quoted jq program mentioning fromdateiso8601), so
# a fourth site added later is covered automatically rather than silently missed.
# ===========================================================================
BUCKET_PROGS_DIR="$(mktemp -d)"; SCRATCH+=("$BUCKET_PROGS_DIR")
# Extraction is anchored on the jq INVOCATION, not on bare single-quote pairing across the
# whole file. An earlier draft paired quotes globally and silently mis-sliced the moment a
# nearby comment contained an apostrophe ("jq's runtime error"), yielding programs that
# failed to COMPILE (jq exit 3) and would have been misread as the runtime crash (exit 5)
# this block is about. Anchoring on `jq -c --argjson period "$CRON_PERIOD"` cannot drift
# into prose: a comment cannot produce a jq call.
cat > "$BUCKET_PROGS_DIR/extract.pl" <<'PERL'
local $/; my $s = <>;
my $i = 0;
while ($s =~ /jq[^']{0,160}'([^']*fromdateiso8601[^']*)'/gs) {
  $i++;
  open(my $fh, '>', "$ENV{OUTDIR}/prog-$i.jq") or die $!;
  print $fh $1;
  close $fh;
}
PERL
OUTDIR="$BUCKET_PROGS_DIR" perl "$BUCKET_PROGS_DIR/extract.pl" "$WF"
BUCKET_PROG_N=$(find "$BUCKET_PROGS_DIR" -name 'prog-*.jq' | wc -l | tr -d '[:space:]')

echo "--- #6178 null-startedAt bucketing (all $BUCKET_PROG_N sites) ---"
# Min-cardinality: an extraction that silently yields zero programs would make every
# assertion below pass without executing anything.
# EXACT, derived from the SUT rather than a magic 3: a fourth bucketing site written with a
# reordered flag (`jq --argjson period ... -c`) would leave a `-ge 3` green while its
# null-startedAt crash went untested. Comment lines mentioning the token are excluded.
BUCKET_SITE_N=$(grep -vE '^[[:space:]]*#' "$WF" | grep -c 'fromdateiso8601' || true)
assert "#6178 every fromdateiso8601 site was extracted (expected $BUCKET_SITE_N)" "[[ '$BUCKET_PROG_N' -eq '$BUCKET_SITE_N' ]]"
assert "#6178 at least 3 bucketing sites exist (2 arms + missed-tick OBSERVED)" "[[ '$BUCKET_PROG_N' -ge 3 ]]"

# A run with no startedAt has NOT fired, so it cannot be a double-fire -- but it must be
# dropped DELIBERATELY, not by dying, and the drop must be counted (a silent discard is
# the false-clean shape this gate exists to prevent).
# These programs are an EXECUTABLE ORACLE, so assert their OUTPUT VALUE, not merely that they
# exited 0. Asserting only "didn't crash" leaves the semantics unpinned: replacing
# `select(.startedAt != null)` with `(.startedAt // "1970-01-01T00:00:00Z")` — which defaults
# every null into a phantom 1970 bucket, so two QUEUED runs group together and report a FALSE
# DOUBLE-FIRE — exits 0 and emits no null bucket, and therefore survived. So did
# `select(length > 1)` → `> 0` and `group_by([.fn,.bucket])` → `group_by([.bucket])`.
#
# Two nulls (not one): at cardinality 1 the null axis cannot exhibit the grouping the defaulting
# mutation creates.
#   fn-a 10:00 / 10:02 -> SAME 1200s bucket  => exactly one dupe group, count 2
#   fn-b 10:00         -> different fn, same bucket => must NOT group with fn-a
#   fn-c 10:00 / 10:40 -> different buckets  => must NOT group
# #6178 THIRD DEFECT — the Postgres-backed dedicated host returns startedAt WITH FRACTIONAL SECONDS
# ("2026-09-14T11:09:34.101119Z"), which `fromdateiso8601` rejects (jq exit 5), so op=verify could
# never produce a verdict on the new backend (measured, run 34961424195). Both fixtures therefore
# mix whole-second and fractional-second stamps: the whole-second-only fixtures this block had
# before were the SQLite shape, and could not see it.
NULL_FIXTURE='{"runs":[
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:02:00.101119Z"},
  {"functionID":"fn-b","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-c","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-c","startedAt":"2026-07-08T10:40:00.25Z"}]}'
# fn-c 10:40:00.25Z is the ONLY run in its (fn,bucket) pair and carries a non-6-digit fraction: a
# program that silently DROPS fractional runs (`try fromdateiso8601 catch empty`) or strips only 6
# digits loses that pair, so the missed-tick OBSERVED count below falls to 3 instead of passing.
# A fixture with NO duplicate at all — proves the dupe detector can say "clean", so an
# always-reports-a-dupe mutation cannot pass by satisfying only the positive case.
CLEAN_FIXTURE='{"runs":[
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:40:00.5Z"},
  {"functionID":"fn-b","startedAt":"2026-07-08T10:00:00Z"}]}'
for prog in "$BUCKET_PROGS_DIR"/prog-*.jq; do
  pname=$(basename "$prog")
  prc=0
  pout=$(jq -c --argjson period 1200 -f "$prog" <<<"$NULL_FIXTURE" 2>&1) || prc=$?
  assert "#6178 $pname survives a null startedAt (jq exit 5 was the crash)" "[[ '$prc' -eq 0 ]]"
  assert "#6178 $pname output contains no null bucket" "! grep -qE '\"bucket\":null|bucket: *null' <<<\"\$(cat <<'EOF'
$pout
EOF
)\""
  # A null-startedAt run must be ABSENT from the output entirely — not defaulted into a bucket.
  assert "#6178 $pname drops the queued (null-startedAt) runs rather than defaulting them" \
    "! grep -qF 'fn-q' <<<\"\$(cat <<'EOF'
$pout
EOF
)\""

  if grep -qF 'group_by' "$prog"; then
    # DUPE-DETECTOR programs (the two probe arms): assert the exact verdict, both directions.
    dupe_n=$(jq -c --argjson period 1200 -f "$prog" <<<"$NULL_FIXTURE" 2>/dev/null | jq 'length')
    assert "#6178 $pname reports EXACTLY one double-fire group on the seeded fixture" "[[ '$dupe_n' -eq 1 ]]"
    dupe_fn=$(jq -c --argjson period 1200 -f "$prog" <<<"$NULL_FIXTURE" 2>/dev/null | jq -r '.[0].functionID')
    dupe_ct=$(jq -c --argjson period 1200 -f "$prog" <<<"$NULL_FIXTURE" 2>/dev/null | jq -r '.[0].count')
    assert "#6178 $pname attributes the double-fire to fn-a (not fn-b sharing the bucket)" "[[ '$dupe_fn' == 'fn-a' ]]"
    assert "#6178 $pname reports count=2 for the duplicated tick" "[[ '$dupe_ct' -eq 2 ]]"
    crc=0
    clean_out=$(jq -c --argjson period 1200 -f "$prog" <<<"$CLEAN_FIXTURE" 2>/dev/null) || crc=$?
    clean_n=$(jq 'length' <<<"${clean_out:-null}" 2>/dev/null || true)
    assert "#6178 $pname parses the clean fixture (a crash must not read as 'clean')" "[[ '$crc' -eq 0 ]]"
    assert "#6178 $pname reports ZERO groups on a genuinely clean fixture (detector can say clean)" "[[ '$clean_n' =~ ^[0-9]+\$ && '$clean_n' -eq 0 ]]"
  else
    # The missed-tick OBSERVED program: a deduplicated (fn, bucket) set, nulls excluded.
    obs_n=$(jq -c --argjson period 1200 -f "$prog" <<<"$NULL_FIXTURE" 2>/dev/null | jq 'length')
    assert "#6178 $pname yields 4 distinct (fn,bucket) pairs, nulls excluded" "[[ '$obs_n' -eq 4 ]]"
  fi
done

# --- #6178 page-overlap dedupe (both probe arms) — EXECUTED, not grepped. ---
# The probe's cursor pagination returned the same run on two pages, and op=verify scored each repeat
# as a double-fire (measured 2026-09-15: groups == RUN_COUNT - total_count, all absent from
# trace_runs). Dedupe is by run id: a repeat shares its id, two distinct runs never do — INCLUDING two
# schedulers firing in the same MILLISECOND (startedAt is ms precision), which the id key must keep.
# Without ids (a host probe predating the projection) it falls back to (functionID, startedAt).
DEDUPE_PROGS=$(perl -ne "print \"\$1\n\" if /jq -c '(\.runs \|= [^']+unique_by[^']+)'/" "$WF")
DEDUPE_N=$(printf '%s\n' "$DEDUPE_PROGS" | grep -c 'unique_by' || true)
assert "#6178 page-overlap dedupe is applied in BOTH probe arms (op=doublefire-probe + op=verify 2.6)" "[[ '$DEDUPE_N' -eq 2 ]]"
ID_FIXTURE='{"runs":[
  {"id":"R1","functionID":"fn-p","startedAt":"2026-09-15T07:47:00.208Z"},
  {"id":"R1","functionID":"fn-p","startedAt":"2026-09-15T07:47:00.208Z"},
  {"id":"R2","functionID":"fn-s","startedAt":"2026-09-15T08:00:00.012Z"},
  {"id":"R3","functionID":"fn-s","startedAt":"2026-09-15T08:00:00.012Z"},
  {"id":"R4","functionID":"fn-d","startedAt":"2026-07-30T15:00:00.065Z"},
  {"id":"R5","functionID":"fn-d","startedAt":"2026-07-30T15:00:00.343Z"},
  {"id":"R6","functionID":"fn-q","startedAt":null},
  {"id":"R7","functionID":"fn-q","startedAt":null}]}'
NOID_FIXTURE='{"runs":[
  {"functionID":"fn-p","startedAt":"2026-09-15T07:47:00.208Z"},
  {"functionID":"fn-p","startedAt":"2026-09-15T07:47:00.208Z"},
  {"functionID":"fn-d","startedAt":"2026-07-30T15:00:00.065Z"},
  {"functionID":"fn-d","startedAt":"2026-07-30T15:00:00.343Z"},
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-q","startedAt":null}]}'
_fncount() { jq --arg f "$2" '[.runs[]? | select(.functionID==$f)] | length' <<<"$1" 2>/dev/null || echo X; }
di=0
while IFS= read -r dprog; do
  [[ -n "$dprog" ]] || continue
  di=$((di + 1))
  iout=$(jq -c "$dprog" <<<"$ID_FIXTURE" 2>/dev/null || echo '{"runs":"CRASH"}')
  nout=$(jq -c "$dprog" <<<"$NOID_FIXTURE" 2>/dev/null || echo '{"runs":"CRASH"}')
  assert "#6178 dedupe site $di [id] drops the page-repeated run (same id -> fn-p once)" "[[ '$(_fncount "$iout" fn-p)' == 1 ]]"
  assert "#6178 dedupe site $di [id] KEEPS a same-MILLISECOND double-fire (distinct ids -> fn-s stays 2)" "[[ '$(_fncount "$iout" fn-s)' == 2 ]]"
  assert "#6178 dedupe site $di [id] KEEPS a ms-apart double-fire (fn-d stays 2)" "[[ '$(_fncount "$iout" fn-d)' == 2 ]]"
  assert "#6178 dedupe site $di [id] keeps distinct null-startedAt runs (fn-q stays 2)" "[[ '$(_fncount "$iout" fn-q)' == 2 ]]"
  assert "#6178 dedupe site $di [no-id fallback] drops the repeat (fn-p once)" "[[ '$(_fncount "$nout" fn-p)' == 1 ]]"
  assert "#6178 dedupe site $di [no-id fallback] KEEPS a ms-apart double-fire (fn-d stays 2)" "[[ '$(_fncount "$nout" fn-d)' == 2 ]]"
  assert "#6178 dedupe site $di [no-id fallback] leaves null-startedAt runs (fn-q stays 2)" "[[ '$(_fncount "$nout" fn-q)' == 2 ]]"
done <<<"$DEDUPE_PROGS"
assert "#6178 the dedupe loop executed both sites" "[[ '$di' -eq 2 ]]"
VERIFY_ARM_BODY=$(grep -vE '^[[:space:]]*#' "$WF") || true
assert "#6178 op=verify FAILS an incomplete scan (deduped RUN_COUNT < total_count) instead of printing a verdict" \
  "grep -A2 -F '(( RUN_COUNT < TOTAL_COUNT ))' <<<\"\$VERIFY_ARM_BODY\" | grep -cF '2.6 INCOMPLETE SCAN' >/dev/null && grep -A3 -F '2.6 INCOMPLETE SCAN' <<<\"\$VERIFY_ARM_BODY\" | grep -cE '^[[:space:]]*exit 1' >/dev/null"
assert "#6178 op=verify QUALIFIES a verdict whose dedupe fell back off the run id" \
  "grep -qF '[[ \"\$DEDUPE_KEY\" != \"run-id\" ]]' <<<\"\$VERIFY_ARM_BODY\""

# --- NON-VACUITY HARD GATE (AC-V3), enforced in code rather than by operator diligence. ---
assert "#6178 op=verify READS the server's total_count (it was emitted and never consumed)" \
  "grep -qE 'TOTAL_COUNT=.*jq -r .\\.total_count' '$VERIFY_ARM_FILE'"
assert "#6178 op=verify HARD-FAILS a vacuous scan rather than reporting a verdict" \
  "grep -qF 'VACUOUS SCAN' '$VERIFY_ARM_FILE'"
assert "#6178 the vacuity gate covers 0, unknown, absent AND run_count==0" \
  "grep -qF '\"\$TOTAL_COUNT\" == \"0\"' '$VERIFY_ARM_FILE' && grep -qF '\"\$TOTAL_COUNT\" == \"unknown\"' '$VERIFY_ARM_FILE' && grep -qF '\"\$TOTAL_COUNT\" == \"absent\"' '$VERIFY_ARM_FILE' && grep -qF '\"\$RUN_COUNT\" -eq 0' '$VERIFY_ARM_FILE'"
assert "#6178 the vacuity gate EXITS (a warning would still let the verdict print)" \
  "grep -A3 'VACUOUS SCAN' '$VERIFY_ARM_FILE' | grep -cE 'exit 1' >/dev/null"
assert "#6178 op=verify QUALIFIES a clean verdict when the claim is weaker" \
  "grep -qF 'VERDICT_QUALIFIERS' '$VERIFY_ARM_FILE' && grep -qF 'exactly-once VERIFIED (QUALIFIED)' '$VERIFY_ARM_FILE'"
# EXECUTED against the SUT's OWN expression, extracted from the arm -- not a copy retyped
# here. A hardcoded `jq -r '.total_count // "absent"'` in the test is a tautology: it stays
# green when the workflow drops the fallback (measured -- that mutation survived until this
# extraction replaced it). `// "absent"` is load-bearing: a bare .total_count on a body
# lacking the field yields the string "null", which matches NONE of the gate's literals, so
# a partial GraphQL error would sail through the vacuity gate.
TC_EXPR=$(grep -oE "jq -r '\.total_count[^']*'" "$VERIFY_ARM_FILE" | head -1 | sed "s/^jq -r '//; s/'\$//")
assert "#6178 the total_count extraction expression was found in the verify arm" "[[ -n '$TC_EXPR' ]]"
for _tc_case in '{}|absent' '{"total_count":0}|0' '{"total_count":"unknown"}|unknown' '{"total_count":728}|728'; do
  _tc_body="${_tc_case%%|*}"; _tc_want="${_tc_case##*|}"
  _tc_got=$(jq -r "$TC_EXPR" <<<"$_tc_body" 2>/dev/null || echo "<jq-error>")
  df_eq "#6178 the arm's OWN total_count expression maps $_tc_body -> $_tc_want" "$_tc_want" "$_tc_got"
done

# The drop must be VISIBLE: both probe arms emit the dropped count as a ::notice::.
# Anchored on the syntactic construct, per-arm. The former file-global `grep -cE 'no
# startedAt|NO_START' -ge 2` was satisfied by the two explanatory COMMENT lines alone: deleting
# every NO_START computation and emission from BOTH arms left it green.
assert "#6178 each arm COMPUTES the dropped-run count (2 sites, syntactic)" \
  "[[ \"\$(grep -cE '^[[:space:]]*NO_START=\\\$\\(echo \"\\\$BODY\" \\| jq' '$WF')\" -eq 2 ]]"
assert "#6178 each arm EMITS the dropped-run count (2 sites)" \
  "[[ \"\$(grep -cF 'run(s) carry no startedAt' '$WF')\" -eq 2 ]]"
assert "#6178 op=verify arm surfaces the dropped count (arm-scoped)" "grep -qF 'run(s) carry no startedAt' '$VERIFY_ARM_FILE'"
assert "#6178 op=doublefire-probe arm surfaces the dropped count (arm-scoped)" "grep -qF 'run(s) carry no startedAt' '$DFPROBE_ARM_FILE'"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# #8054 — op=execute 2.0 DARK ARM. Until #8054 the non-200 branch was `exit 1`, which made 2.0
# unrunnable in the very sequence it guards (P1-5 keeps the dedicated host dark until op=arm, which
# runs AFTER execute). The arm now grades darkness positively through
# tests/scripts/lib/inngest-host-dark-gate.sh's second entry point. These rows pin the WIRING —
# the gate's own predicates are the dark-gate suite's job.
# ═══════════════════════════════════════════════════════════════════════════════════════════════
GATE_LIB="$REPO_ROOT/tests/scripts/lib/inngest-host-dark-gate.sh"
FLIP_GUARD="$REPO_ROOT/apps/web-platform/infra/inngest-server-flip-guard.sh"
EXEC_ARM_FILE="$(mktemp)"; SCRATCH+=("$EXEC_ARM_FILE")
awk '/^  execute\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$BODY_SH" > "$EXEC_ARM_FILE"
EXEC_ARM_N=$(grep -cv '^[[:space:]]*#' "$EXEC_ARM_FILE" || true)
assert "#8054 execute arm extraction is non-vacuous (>100 non-comment lines, got $EXEC_ARM_N)" "[[ '$EXEC_ARM_N' -gt 100 ]]"

# ── One guarded gate call, the set -e-safe shape (AC5) ───────────────────────────
ERG_CALLS=$(grep -v '^[[:space:]]*#' "$EXEC_ARM_FILE" | grep -cE '^[[:space:]]*ERG_VERDICT="?\$\(inngest_execute_registry_gate ' || true)
assert "#8054 2.0 routes through EXACTLY one inngest_execute_registry_gate call, got $ERG_CALLS" "[[ '$ERG_CALLS' -eq 1 ]]"
assert "#8054 the gate call is ||-guarded (a bare \$(…) under set -e aborts before any ::error:: prints)" \
  "grep -v '^[[:space:]]*#' '$EXEC_ARM_FILE' | grep -E '^[[:space:]]*ERG_VERDICT=' | grep -cE '\|\| ERG_RC=\\\$\?' >/dev/null"
assert "#8054 the gate lib is sourced under an || guard (a missing lib on an old ref names the fix, not a mute abort)" \
  "grep -qE '^[[:space:]]*source tests/scripts/lib/inngest-host-dark-gate.sh \|\| \{' '$EXEC_ARM_FILE'"
# #8079 D7 row 1 / AC13 — the gate's consumer set is exactly {execute, registry-probe}. A per-arm
# census derived from the arm enumeration (so a new arm is counted, not assumed), and the
# whole-file total pinned at 2 (so a call in a top-level function or the `*)` catch-all — which
# sits in no arm — cannot escape). Dispatch floor >= 12 arms, or an emptied enumeration passes.
PROBE_ARM_FILE="$(mktemp)"; SCRATCH+=("$PROBE_ARM_FILE")
awk '/^  registry-probe\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$BODY_SH" > "$PROBE_ARM_FILE"
PROBE_ARM_N=$(grep -cv '^[[:space:]]*#' "$PROBE_ARM_FILE" || true)
assert "#8079 registry-probe arm extraction is non-vacuous (>80 non-comment lines, got $PROBE_ARM_N)" "[[ '$PROBE_ARM_N' -gt 80 ]]"
# Occurrences, not lines (`grep -o | wc -l`): a second call appended to the SAME physical line is a
# member of the consumer set and a line count cannot see it. A function so the mutation rows below
# can re-run the census on a patched copy.
_gate_census() {  # $1 = script → stdout "arms=N bad=<…>"; rc 1 when the set is not {execute, registry-probe}
  local arm c n=0 bad=""
  while IFS= read -r arm; do
    n=$((n + 1))
    c=$(awk -v a="$arm" '$0 ~ "^  "a"\\)$"{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$1" | grep -v '^[[:space:]]*#' | grep -o 'inngest_execute_registry_gate' | wc -l) || true
    case "$arm" in
      execute|registry-probe) [[ "$c" -eq 1 ]] || bad="$bad $arm=$c(want 1)" ;;
      *)                      [[ "$c" -eq 0 ]] || bad="$bad $arm=$c(want 0)" ;;
    esac
  done < <(grep -oE '^  [a-z-]+\)$' "$1" | tr -d ' )' | sort -u)
  printf 'arms=%s bad=%s' "$n" "${bad:- none}"
  [[ "$n" -ge 12 && -z "$bad" ]]
}
_gate_total() { grep -v '^[[:space:]]*#' "$1" | grep -o 'inngest_execute_registry_gate' | wc -l; }
_CENSUS="$(_gate_census "$BODY_SH")" && _census_ok=1 || _census_ok=0
assert "#8079 gate consumer census: 1 in execute, 1 in registry-probe, 0 in every other arm, >= 12 arms enumerated ($_CENSUS)" "[[ '$_census_ok' -eq 1 ]]"
assert "#8079 gate consumer whole-file total is exactly 2 OCCURRENCES (a call outside every arm, or a second on the same line, cannot hide), got $(_gate_total "$BODY_SH")" \
  "[[ \$(_gate_total '$BODY_SH') -eq 2 ]]"
# The lib exports a second verdict-producing entry point (inngest_host_dark_gate, the recut gate)
# and the _ihdg_* helpers; a consumer reaching a verdict through those would sit outside this
# census's name. The script calls none of them.
assert "#8079 the script reaches no OTHER lib entry point (inngest_host_dark_gate / _ihdg_* / _erg_*) — the census's one name is the whole consumer surface" \
  "! grep -v '^[[:space:]]*#' '$BODY_SH' | grep -E 'inngest_host_dark_gate|_ihdg_[a-z_]+|_erg_(emit|hb_newest|flag_class|[a-z_]*verdict)' | grep -v 'inngest_execute_registry_gate' >/dev/null"

# ── Every token the lib can emit has a case arm; the *) arm exits 1 ─────────────
LIB_TOKENS=$(grep -v '^[[:space:]]*#' "$GATE_LIB" | grep -oE '_ihdg_verdict "[a-z_]+"' | cut -d'"' -f2 | sort -u || true)
LIB_TOKEN_N=$(printf '%s\n' "$LIB_TOKENS" | grep -c . || true)
assert "#8054 the lib emits a non-trivial token set (>= 11, got $LIB_TOKEN_N)" "[[ '$LIB_TOKEN_N' -ge 11 ]]"
# The recut gate's own tokens (redis_down, store_populated, …) are not reachable from the execute
# gate; the case must cover every token the EXECUTE gate can return. Derive that set from the
# execute gate's function body + the shared helpers' whitelist in it.
ERG_FN_FILE="$(mktemp)"; SCRATCH+=("$ERG_FN_FILE")
awk '/^inngest_execute_registry_gate\(\) \{$/,/^\}$/' "$GATE_LIB" > "$ERG_FN_FILE"
ERG_TOKENS=$(grep -v '^[[:space:]]*#' "$ERG_FN_FILE" | grep -oE '_ihdg_verdict "[a-z_]+"' | cut -d'"' -f2 | sort -u || true)
ERG_TOKEN_N=$(printf '%s\n' "$ERG_TOKENS" | grep -c . || true)
assert "#8054 the execute gate's reachable token set is the plan's 11" "[[ '$ERG_TOKEN_N' -eq 11 ]]"
_missing_arms=""
for _tok in $ERG_TOKENS; do
  grep -qE "^[[:space:]]+${_tok}\)$" "$EXEC_ARM_FILE" || _missing_arms="$_missing_arms $_tok"
done
assert "#8054 every execute-gate token has its own case arm in 2.0 (missing:${_missing_arms:- none})" "[[ -z '$_missing_arms' ]]"

# ── #8079 D10 — three drift guards for the accepted duplication of the gate plumbing ──────────
# Guard 1: token coverage, by the SAME lib-derived loop. Both arms quantify over the lib's set, so
# a 12th lib token reddens both. Non-vacuity rides on the ERG_TOKEN_N -eq 11 row above — three
# empty sets are equal. Probe emit `case` arms must stay single-line (as 2.0's are), which is what
# keeps the `$`-anchored token pattern from swallowing `flag)`, `boot_id)` etc.
_missing_probe_arms=""
for _tok in $ERG_TOKENS; do
  grep -qE "^[[:space:]]+${_tok}\)$" "$PROBE_ARM_FILE" || _missing_probe_arms="$_missing_probe_arms $_tok"
done
assert "#8079 every execute-gate token has its own case arm in registry-probe too (missing:${_missing_probe_arms:- none})" "[[ -z '$_missing_probe_arms' ]]"
assert "#8079 the registry-probe *) arm exits 1 and names the GATE as the defect, never the host" \
  "awk '/^        \*\)\$/{f=1} f' '$PROBE_ARM_FILE' | sed -n '1,8p' | grep -cE 'defect in tests/scripts/lib/inngest-host-dark-gate.sh or in this arm.*NOT a host state' >/dev/null && awk '/^        \*\)\$/{f=1} f' '$PROBE_ARM_FILE' | sed -n '1,8p' | grep -c 'exit 1 ;;' >/dev/null"
# PER ARM, not an aggregate: review of #8079 measured 15 `exit 1` lines against a `>= 10` floor, so
# four tokens could lose their exit (a REFUSED that then exits 0) with the row green. Every non-dark
# token's body — comment-stripped — must carry `exit 1` AND the no-SSH sentence; the `*)` arm too.
_arm_exit_gaps() {  # $1 = arm file, $2 = verdict var → tokens whose body lacks exit 1 or the no-SSH line
  local tok gaps="" body
  for tok in $ERG_TOKENS '\\*'; do
    [[ "$tok" == "dark" ]] && continue
    body=$(awk -v t="$tok" '$0 ~ "^        "t"\\)"{f=1;print;next} f&&/^        [a-z_*]+\)/{exit} f' "$1" | grep -v '^[[:space:]]*#') || true
    grep -q 'exit 1' <<<"$body" && grep -q 'Do NOT SSH the host' <<<"$body" || gaps="$gaps $tok"
  done
  printf '%s' "$gaps"
}
_PROBE_EXIT_GAPS="$(_arm_exit_gaps "$PROBE_ARM_FILE")"
assert "#8079 every refusal arm of the registry-probe case (10 tokens + *) carries its own exit 1 AND 'Do NOT SSH the host' (gaps:${_PROBE_EXIT_GAPS:- none})" "[[ -z '$_PROBE_EXIT_GAPS' ]]"

# Guard 2: plumbing parity by prefix normalisation. ONE row pins the trap POSITION, the
# `: > "$EMIT"` pre-touch, the `|| RC=$?` call shape, both read windows, the emit shape regex and
# the absence of a umask: the probe plumbing region, with its RPG_ prefix and step label
# normalised, must be BYTE-EQUAL to the exec plumbing region normalised the same way. The
# uniform prefix is what makes this mechanical. Region = the guarded `source` line through the
# emit read loop's `done`, comments dropped.
_plumb() {
  awk '/^      source tests\/scripts\/lib\/inngest-host-dark-gate.sh \|\| \{/{f=1} f{print} f&&/^      done < "\$(ERG|RPG)_EMIT"$/{exit}' "$1" \
    | grep -v '^[[:space:]]*#' \
    | sed -E 's/(ERG|RPG)_//g; s/_(erg|rpg)_/_/g; s/(erg|rpg)\.XXXXXXXX/x.XXXXXXXX/g; s/::(error|notice|warning)::(2\.0|registry-probe):/::\1::STEP:/g'
}
_PL_EXEC="$(_plumb "$EXEC_ARM_FILE")"; _PL_PROBE="$(_plumb "$PROBE_ARM_FILE")"
_PL_N=$(printf '%s\n' "$_PL_EXEC" | grep -c . || true)
assert "#8079 plumbing parity extraction is non-vacuous (>= 18 lines each, got $_PL_N / $(printf '%s\n' "$_PL_PROBE" | grep -c . || true))" "[[ '$_PL_N' -ge 18 && \$(printf '%s\n' \"\$_PL_PROBE\" | grep -c .) -ge 18 ]]"
assert "#8079 plumbing parity: the probe arm's gate plumbing, prefix-normalised, is BYTE-EQUAL to 2.0's (trap position, pre-touch, || RC=\$? shape, both windows, emit regex)" \
  "[[ \"\$_PL_EXEC\" == \"\$_PL_PROBE\" ]]"
assert "#8079 plumbing parity guard is load-bearing: the two UN-normalised regions differ (so equality above is the normaliser's work, not a tautology)" \
  "[[ \"\$(awk '/^      source tests/{f=1} f{print} f&&/^      done </{exit}' '$EXEC_ARM_FILE')\" != \"\$(awk '/^      source tests/{f=1} f{print} f&&/^      done </{exit}' '$PROBE_ARM_FILE')\" ]]"

# Guard 3: cross-arm remedy guard. Guards 1 and 2 pin the token set and the plumbing; nothing
# pins the ELEVEN remedy strings, where all the divergence and all the value live. One row per
# arm: every non-dark token's remedy names at least one no-SSH instrument OR one action from the
# closed no-SSH set (file an issue / wait for the next probe or heartbeat) — a remedy naming
# nothing, or naming SSH, is what this catches. Plus the `# twin:`
# comment at each `case` head, so a remedy edit in one arm has a pointer to the other.
_remedy_instruments='gh workflow run|gh run list|scripts/inngest-host-state\.sh|op=inventory|_bs_read_remedy|scheduled-inngest-health|runbooks/inngest-server\.md|git show vinngest-|[Ff]ile an issue|[Ww]ait for the next hourly probe|[Ww]ait one heartbeat|[Ww]ait one probe period'
_arm_remedy_gaps() {  # $1 = arm file, $2 = verdict var name
  local tok gaps="" body
  for tok in $ERG_TOKENS; do
    [[ "$tok" == "dark" ]] && continue
    body=$(awk -v t="$tok" '$0 ~ "^        "t"\\)"{f=1;print;next} f&&/^        [a-z_*]+\)/{exit} f' "$1")
    # Herestring, never `printf | grep -q`: under pipefail an early match SIGPIPEs the producer
    # (141) and `||` reads that as "no instrument" — the flake fired on the arm whose match
    # sits earliest in its body, exactly as the pipefail-grep-q learning predicts.
    grep -qE "$_remedy_instruments" <<<"$body" || gaps="$gaps $tok"
  done
  printf '%s' "$gaps"
}
_EXEC_GAPS="$(_arm_remedy_gaps "$EXEC_ARM_FILE")"; _PROBE_GAPS="$(_arm_remedy_gaps "$PROBE_ARM_FILE")"
assert "#8079 every non-dark 2.0 remedy names a no-SSH instrument (gaps:${_EXEC_GAPS:- none})" "[[ -z '$_EXEC_GAPS' ]]"
assert "#8079 every non-dark registry-probe remedy names a no-SSH instrument (gaps:${_PROBE_GAPS:- none})" "[[ -z '$_PROBE_GAPS' ]]"
assert "#8079 each case head carries a # twin: pointer at the other arm" \
  "grep -B3 '^      case \"\$ERG_VERDICT\" in$' '$EXEC_ARM_FILE' | grep -c '# twin: the registry-probe arm' >/dev/null && grep -B3 '^      case \"\$RPG_VERDICT\" in$' '$PROBE_ARM_FILE' | grep -c '# twin: the 2.0 arm' >/dev/null"
assert "#8054 the *) arm exits 1 and names the gate as the defect, never the host" \
  "awk '/^        \*\)\$/{f=1} f' '$EXEC_ARM_FILE' | sed -n '1,8p' | grep -cE 'defect in the gate, not a host state.*exit 1 ;;' >/dev/null"
# Every refusal arm exits 1: count `exit 1` inside the case at least once per non-dark token.
_case_exits=$(awk '/^      case "\$ERG_VERDICT" in$/{f=1} f&&/^      esac$/{exit} f' "$EXEC_ARM_FILE" | grep -c 'exit 1' || true)
assert "#8054 the 2.0 case carries an exit 1 per refusal token (>= 10, got $_case_exits)" "[[ '$_case_exits' -ge 10 ]]"

# ── Two reads, one --grep term each, distinct (AC6) ──────────────────────────────
ERG_READS=$(grep -v '^[[:space:]]*#' "$EXEC_ARM_FILE" | grep -E '_bs_query_rows ' || true)
ERG_READ_N=$(printf '%s\n' "$ERG_READS" | grep -c . || true)
assert "#8054 2.0 makes exactly two Better Stack reads, got $ERG_READ_N" "[[ '$ERG_READ_N' -eq 2 ]]"
assert "#8054 one read carries the probe marker, the other the flip tag, and neither carries both" \
  "printf '%s\n' \"\$ERG_READS\" | grep -c 'SOLEUR_INNGEST_SERVER_PROBE' | grep -cx 1 >/dev/null && printf '%s\n' \"\$ERG_READS\" | grep -c 'inngest-cutover-flip' | grep -cx 1 >/dev/null && ! printf '%s\n' \"\$ERG_READS\" | grep 'SOLEUR_INNGEST_SERVER_PROBE' | grep -c 'inngest-cutover-flip' >/dev/null"
assert "#8054 both reads capture stderr to a file and return the query's rc into a *_RC variable" \
  "[[ \$(printf '%s\n' \"\$ERG_READS\" | grep -cE '^[[:space:]]*(PROBE|HB)_RC=0;[[:space:]]+_bs_query_rows .* \"\\\$(PROBE|HB)_ERR\" > \"\\\$(PROBE|HB)_ROWS\" \|\| (PROBE|HB)_RC=\\\$\?$') -eq 2 ]]"
_trap_line="trap 'rm -rf \"\$ERG_DIR\"' EXIT"
# `-t <prefix>` since #8079: TMPDIR-based and PROVABLY absolute to fixture-scan (a destination
# argument rooted on ${RUNNER_TEMP:-/tmp} was not, and rooted 4 baselined sites per arm).
_mktemp_line='mktemp -d -t erg.XXXXXXXX'
assert "#8054 the row files live under a private mktemp -d -t (0700, TMPDIR-based, provably absolute) directory, removed on EXIT" \
  "grep -qF -- \"\$_mktemp_line\" '$EXEC_ARM_FILE' && grep -qF -- \"\$_trap_line\" '$EXEC_ARM_FILE' && ! grep -qE '^[[:space:]]*umask ' '$EXEC_ARM_FILE'"
# The dark arm is entered ONLY on the dedicated host's own connection-refused signature (HTTP 500
# + __FETCH_FAILED__ from inngest-registry-probe.sh); every other non-200 is a WEBHOOK-PATH fault
# and refuses without reading Better Stack at all.
assert "#8054 the dark arm is gated on HTTP 500 + the __FETCH_FAILED__ signature; other non-200s refuse as webhook_path" \
  "grep -qE '^[[:space:]]*if \[\[ \"\\\$CODE\" != \"500\" \|\| \"\\\$BODY\" != \*\"__FETCH_FAILED__\"\* \]\]; then' '$EXEC_ARM_FILE' && grep -qE 'REFUSED \(webhook_path\).*op=registry-probe' '$EXEC_ARM_FILE' && grep -A2 -E 'REFUSED \(webhook_path\)' '$EXEC_ARM_FILE' | grep -cE '^[[:space:]]*exit 1$' >/dev/null"

# ── Purity: no annotation line interpolates a row file, the body or the cause (AC9) ──
ANNOT_LEAKS=$(awk '/# ---- 2\.0 DARK ARM/{f=1} f&&/^    else$/{exit} f' "$EXEC_ARM_FILE" \
  | grep -E 'echo "::(notice|error|warning)::' | grep -cE '\$\{?(PROBE_ROWS|HB_ROWS|BODY|CAUSE|newest_msg|chosen_msg|rows_tsv|hb_msg)\b' || true)
assert "#8054 no dark-arm annotation interpolates PROBE_ROWS/HB_ROWS/BODY/CAUSE (got $ANNOT_LEAKS)" "[[ '$ANNOT_LEAKS' -eq 0 ]]"
assert "#8054 the webhook body is printed ONCE, as a plain non-annotation line, CR/LF-stripped" \
  "[[ \$(grep -cE '^[[:space:]]*echo \"2\.0 webhook body \(HTTP \\\$CODE, informational' '$EXEC_ARM_FILE') -eq 1 ]]"

# ── ERG_* values: read only from --emit-file behind the shape regex; none on the HTTP-200 path (AC16b) ──
GATE_CALL_LN=$(grep -nE '^[[:space:]]*ERG_VERDICT="?\$\(inngest_execute_registry_gate ' "$EXEC_ARM_FILE" | sed -n '1p' | cut -d: -f1 || true)
ELSE_LN=$(awk '/# ---- 2\.0 DARK ARM/{f=1} f&&/^    else$/{print NR; exit}' "$EXEC_ARM_FILE")
PREFLIGHT_LN=$(grep -nF '::notice::2.0 registry-probe: dark registry EMPTY' "$EXEC_ARM_FILE" | sed -n '1p' | cut -d: -f1 || true)
assert "#8054 anchors resolve (gate call, else, pre-flight clear)" "[[ -n '$GATE_CALL_LN' && -n '$ELSE_LN' && -n '$PREFLIGHT_LN' && '$GATE_CALL_LN' -lt '$ELSE_LN' && '$ELSE_LN' -lt '$PREFLIGHT_LN' ]]"
_erg_before=$(sed -n "1,${GATE_CALL_LN}p" "$EXEC_ARM_FILE" | grep -v '^[[:space:]]*#' | grep -E '\$\{?ERG_(FLAG|BOOT|ROW_AGE|HB_AGE|HB_FLAG|VERDICT|SAN)\b' | grep -c . || true)
assert "#8054 no ERG_ value is interpolated BEFORE the gate call (got $_erg_before)" "[[ '$_erg_before' -eq 0 ]]"
_erg_http200=$(sed -n "${ELSE_LN},${PREFLIGHT_LN}p" "$EXEC_ARM_FILE" | grep -v '^[[:space:]]*#' | grep -c 'ERG_' || true)
assert "#8054 the HTTP-200 (reachable-empty) path never touches an ERG_ variable (set -u would abort mute), got $_erg_http200" "[[ '$_erg_http200' -eq 0 ]]"
_erg_assign_regex=$(grep -cE '(^|[[:space:]])ERG_(FLAG|BOOT|ROW_AGE|HB_AGE|HB_FLAG)="\$\{BASH_REMATCH\[' "$EXEC_ARM_FILE" || true)
_erg_assign_other=$(grep -v '^[[:space:]]*#' "$EXEC_ARM_FILE" | grep -E 'ERG_(FLAG|BOOT|ROW_AGE|HB_AGE|HB_FLAG)=' | grep -vE 'ERG_(FLAG|BOOT|ROW_AGE|HB_AGE|HB_FLAG)=("\$\{BASH_REMATCH\[|""|"__UNREAD__")' | grep -c . || true)
assert "#8054 every ERG_ notice field is assigned from the emit-file read behind the shape regex (regex-assigns=$_erg_assign_regex, other=$_erg_assign_other)" "[[ '$_erg_assign_regex' -ge 5 && '$_erg_assign_other' -eq 0 ]]"
assert "#8054 the emit-file read is anchored: ^(flag|boot_id|row_age|hb_age|hb_flag)=([A-Za-z0-9_-]{1,64})\$" \
  "grep -qF '=~ ^(flag|boot_id|row_age|hb_age|hb_flag)=([A-Za-z0-9_-]{1,64})\$' '$EXEC_ARM_FILE'"

# ── The reachable-empty decision logic is unchanged (AC7) — pinned as CONTENT, not against a ref ──
# A comparison against `origin/main` is a comparison against whatever main holds when the suite
# runs: vacuous after this PR merges (main vs main) and dependent on remote state before it. The
# normalised block (comments stripped, indentation stripped, the one deliberately edited D4 echo
# excluded) is pinned here verbatim as it stood on main before #8054; a future deliberate change to
# the reachable-empty decision logic updates this pin in the same commit, which is the point.
AC7_HEAD="$(mktemp)"; AC7_PIN="$(mktemp)"; SCRATCH+=("$AC7_HEAD" "$AC7_PIN")
awk '/^  execute\)$/{e=1} e&&/REG_EMPTY=\$\(echo "\$BODY"/{f=1} f{print} f&&/pre-flight clear/{exit}' "$BODY_SH" \
  | grep -v 'Remediation (P1-6)' | grep -v '^[[:space:]]*#' | sed 's/^[[:space:]]*//' > "$AC7_HEAD"
cat > "$AC7_PIN" <<'AC7EOF'
REG_EMPTY=$(echo "$BODY" | jq -r '.registry_empty')
REG_COUNT=$(echo "$BODY" | jq -r '.function_count // 0')
if [[ "$REG_EMPTY" != "true" ]]; then
echo "::error::2.0 ABORT — dark registry is NON-empty (function_count=$REG_COUNT). The cutover flip must only run against an EMPTY dark registry or a second scheduler double-fires against prod Postgres."
exit 1
fi
echo "::notice::2.0 registry-probe: dark registry EMPTY (function_count=$REG_COUNT) — pre-flight clear"
AC7EOF
assert "#8054 AC7: the reachable-empty decision logic is byte-identical to its pre-#8054 form (modulo indentation, comments and the D4 echo)" \
  "[[ -s '$AC7_HEAD' ]] && diff -q '$AC7_PIN' '$AC7_HEAD' >/dev/null"
assert "#8054 D4: the impossible step (2) is gone and the replacement names an operator-performable read" \
  "! grep -v '^[[:space:]]*#' '$EXEC_ARM_FILE' | grep -c 'stop the dark inngest-server' >/dev/null && grep -qE 'Remediation \(P1-6\).*scheduled-inngest-health' '$EXEC_ARM_FILE'"
assert "#8054 the reachable-empty arm gains its out-of-sequence warning after pre-flight clear (#8072)" \
  "sed -n \"\$((PREFLIGHT_LN + 1))p\" '$EXEC_ARM_FILE' | grep -cE '^[[:space:]]*echo \"::warning::2\.0: a dedicated host that ANSWERS pre-arm is out of sequence.*#8072' >/dev/null"
assert "#8054 2.2 STILL RUNNING carries the first-run 'designed stop' sentence" \
  "grep -qF 'On the first execute of a cutover this is the designed stop and the run is red by design' '$EXEC_ARM_FILE'"

# ── E11/E13 allowlist is DERIVED from the P1-5 source, not retyped (AC16) ────────
# Order-independent: anchored on the `flag_ok=true` arm, not on `armed` being its first alternative
# (the same derivation inngest-server-flip-guard.test.sh uses).
P15_SET=$(grep -E 'flag_ok=true' "$FLIP_GUARD" | grep -vE '^[[:space:]]*#' | sed -n '1p' | sed -E 's/\).*$//; s/[[:space:]]//g' | tr '|' '\n' | sort | tr '\n' ',' || true)
e11_set_of() { awk '/^_erg_flag_class\(\) \{$/,/^}$/' "$1" | grep -oE "^[[:space:]]*[a-z|-]+\) printf 'armed'" | sed -E "s/\) printf 'armed'//; s/^[[:space:]]*//" | tr '|' '\n' | sort | tr '\n' ','; }
E11_SET=$(e11_set_of "$GATE_LIB")
assert "#8054 AC16: E11/E13 arm set [$E11_SET] is SET-EQUAL to the P1-5 allowlist [$P15_SET] in $(basename "$FLIP_GUARD") (read from $(basename "$GATE_LIB"))" \
  "[[ -n '$P15_SET' && '$P15_SET' == '$E11_SET' ]]"

# ── The admission signature is a CROSS-FILE contract with the web-host probe ──────
# `webhook_path` admits the dark arm on the literal the web-host probe emits when its fetch fails.
# Derive that literal from the PRODUCER and require the script to test for the same bytes; a rename
# on either side otherwise refuses every execute as webhook_path with both suites green.
REGISTRY_PROBE="$REPO_ROOT/apps/web-platform/infra/inngest-registry-probe.sh"
FF_LITERAL_PRODUCER="$(grep -oE '"message":"__[A-Z_]+__"' "$REGISTRY_PROBE" | sed -n '1p' | grep -oE '__[A-Z_]+__' || true)"
FF_LITERAL_SCRIPT="$(grep -oE '"\$BODY" != \*"__[A-Z_]+__"\*' "$EXEC_ARM_FILE" | sed -n '1p' | grep -oE '__[A-Z_]+__' || true)"
assert "#8054 the dark arm's admission literal [$FF_LITERAL_SCRIPT] equals the web-host probe's fetch-failure literal [$FF_LITERAL_PRODUCER] (derived from $(basename "$REGISTRY_PROBE"))" \
  "[[ -n '$FF_LITERAL_PRODUCER' && '$FF_LITERAL_PRODUCER' == '$FF_LITERAL_SCRIPT' ]]"
assert "#8054 the web-host probe still exits 1 on that literal (the hook's error passthrough turns it into the HTTP 500 the script requires)" \
  "grep -qE 'include-command-output-in-response-on-error.*true' '$REPO_ROOT/apps/web-platform/infra/hooks.json.tmpl' && awk '/^run_probe\(\) \{$/,/^\}$/' '$REGISTRY_PROBE' | grep -cE '^[[:space:]]*exit 1$' >/dev/null"

# ── RENDER the dark arm against the H5 fixture (AC16b) and the reachable-empty arm (H6) ──
# The 2.0 region is extracted from the script and executed with the network stubbed: `curl`
# answers the webhook, `_bs_query_rows` answers the two Better Stack reads from fixtures. The
# gate lib is REAL (sourced by the region itself, cwd = repo root). Fixtures are dated relative
# to the wall clock because the production call passes no --now-epoch.
REGION_FILE="$(mktemp)"; SCRATCH+=("$REGION_FILE")
awk '/# ---- 2\.0 empty-registry pre-flight/{f=1} f&&/# ---- 2\.1 capture/{exit} f' "$BODY_SH" > "$REGION_FILE"
REGION_N=$(grep -cv '^[[:space:]]*#' "$REGION_FILE" || true)
assert "#8054 2.0 region extraction is non-vacuous (>60 non-comment lines, got $REGION_N)" "[[ '$REGION_N' -gt 60 ]]"
H5_BOOT="a1b2c3d4-0000-4000-8000-00000000cafe"; H5_BID="${H5_BOOT//-/}"
H5_PROBE_DT="$(date -u -d '-7 min' '+%Y-%m-%d %H:%M:%S')"
H5_HB_DT="$(date -u -d '-1 min' '+%Y-%m-%d %H:%M:%S')"
H5_MSG="SOLEUR_INNGEST_SERVER_PROBE http_code=000 server_active=failed vector_active=active redis_active=active uptime_s=100 boot_id=$H5_BOOT image_ref=ghcr.io/other@sha256:fff instance_id=1 cli_version=v1 cutover_flag=rolled-back probe_schema=8 host_role=dedicated flush_latched=false redis_keys=16 redis_expires=0 redis_key_patterns=k:1 data_mount_src=/dev/sdb data_bytes=4096 data_mount_base=sdb data_mount_devid=scsi-0HC_Volume_1 registry_fns=__UNREADABLE__ zz_trailing=1"
H5_PROBE_ROW=$(jq -cn --arg dt "$H5_PROBE_DT" --arg m "$H5_MSG" --arg b "$H5_BID" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-server-probe", _BOOT_ID:$b, message:$m} | tojson)}')
H5_HB_ROW=$(jq -cn --arg dt "$H5_HB_DT" --arg b "$H5_BID" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-cutover-flip", _BOOT_ID:$b, message:{flag:"rolled-back", reason:"noop-rolled-back", guard:"7761", exit_code:0}} | tojson)}')
# #8079 D8 — the flag_armed 2x2 needs the probe row and the heartbeat each sampled at `done`
# and at an in-flight value. Each is the H5 fixture with ONE substitution, so it reaches the
# same E-step and refuses there for the flag and nothing else.
DONE_MSG="${H5_MSG/cutover_flag=rolled-back/cutover_flag=done}"
ARMED_MSG="${H5_MSG/cutover_flag=rolled-back/cutover_flag=armed}"
DONE_PROBE_ROW=$(jq -cn --arg dt "$H5_PROBE_DT" --arg m "$DONE_MSG" --arg b "$H5_BID" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-server-probe", _BOOT_ID:$b, message:$m} | tojson)}')
ARMED_PROBE_ROW=$(jq -cn --arg dt "$H5_PROBE_DT" --arg m "$ARMED_MSG" --arg b "$H5_BID" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-server-probe", _BOOT_ID:$b, message:$m} | tojson)}')
DONE_HB_ROW=$(jq -cn --arg dt "$H5_HB_DT" --arg b "$H5_BID" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-cutover-flip", _BOOT_ID:$b, message:{flag:"done", reason:"noop-done", guard:"7761", exit_code:0}} | tojson)}')
ARMED_HB_ROW=$(jq -cn --arg dt "$H5_HB_DT" --arg b "$H5_BID" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-cutover-flip", _BOOT_ID:$b, message:{flag:"armed", reason:"noop-armed", guard:"7761", exit_code:0}} | tojson)}')
# #8079 — every token the probe case handles gets a render (review found host_serving, wrong_host,
# stale_row, stale_schema, flag_unreadable, unreadable/fsm_unreadable at rc 0 and the heartbeat
# read-failure leg unrendered, so their exit 1 and their step operand were deletable green). Each
# fixture is H5 with ONE substitution, so it reaches the E-step named and refuses there alone.
_h5_probe_row() {  # $1 dt  $2 message  $3 host
  jq -cn --arg dt "$1" --arg m "$2" --arg b "$H5_BID" --arg h "$3" '{dt:$dt, raw: ({host:$h, host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-server-probe", _BOOT_ID:$b, message:$m} | tojson)}'
}
_h5_hb_row() {  # $1 flag
  jq -cn --arg dt "$H5_HB_DT" --arg b "$H5_BID" --arg f "$1" '{dt:$dt, raw: ({host:"soleur-inngest", host_name:"soleur-inngest-prd", SYSLOG_IDENTIFIER:"inngest-cutover-flip", _BOOT_ID:$b, message:{flag:$f, reason:("noop-"+$f), guard:"7761", exit_code:0}} | tojson)}'
}
SERVING_PROBE_ROW=$(_h5_probe_row "$H5_PROBE_DT" "${H5_MSG/http_code=000 server_active=failed/http_code=200 server_active=active}" soleur-inngest)
WRONGHOST_PROBE_ROW=$(_h5_probe_row "$H5_PROBE_DT" "$H5_MSG" web-1)
STALE_PROBE_ROW=$(_h5_probe_row "$(date -u -d '-3 hour' '+%Y-%m-%d %H:%M:%S')" "$H5_MSG" soleur-inngest)
SCHEMA7_PROBE_ROW=$(_h5_probe_row "$H5_PROBE_DT" "${H5_MSG/probe_schema=8/probe_schema=7}" soleur-inngest)
UNKNOWNFLAG_PROBE_ROW=$(_h5_probe_row "$H5_PROBE_DT" "${H5_MSG/cutover_flag=rolled-back/cutover_flag=unknown}" soleur-inngest)
ABORTED_PROBE_ROW=$(_h5_probe_row "$H5_PROBE_DT" "${H5_MSG/cutover_flag=rolled-back/cutover_flag=aborted}" soleur-inngest)
ROLLBACKFLAG_HB_ROW=$(_h5_hb_row rollback)
ABORTED_HB_ROW=$(_h5_hb_row aborted)
assert "#8079 per-token fixtures are each ONE substitution from H5 (serving/schema7/unknownflag/aborted differ in 2 tokens; wronghost only in host; stale only in dt)" \
  "[[ \$(diff <(tr ' ' '\n' <<<\"\$H5_MSG\") <(tr ' ' '\n' <<<\"\${H5_MSG/probe_schema=8/probe_schema=7}\") | grep -c '^[<>]') -eq 2 && \$(jq -r '.raw|fromjson|.host' <<<\"\$WRONGHOST_PROBE_ROW\") == web-1 && \$(jq -r '.raw|fromjson|.host' <<<\"\$H5_PROBE_ROW\") == soleur-inngest && \$(jq -r .dt <<<\"\$STALE_PROBE_ROW\") != \$(jq -r .dt <<<\"\$H5_PROBE_ROW\") ]]"
assert "#8079 2x2 fixtures differ from H5 in the flag ONLY (done/armed probe rows; done/armed heartbeats)" \
  "[[ \"\$DONE_MSG\" != \"\$H5_MSG\" && \"\$ARMED_MSG\" != \"\$H5_MSG\" && \$(diff <(tr ' ' '\n' <<<\"\$H5_MSG\") <(tr ' ' '\n' <<<\"\$DONE_MSG\") | grep -c '^[<>]') -eq 2 && \$(diff <(tr ' ' '\n' <<<\"\$H5_MSG\") <(tr ' ' '\n' <<<\"\$ARMED_MSG\") | grep -c '^[<>]') -eq 2 ]]"
# render_2_0 <region-file> <webhook-code> <webhook-body> <probe-mode> <hb-mode>  — echoes stdout+stderr, returns rc
#
# RUNS IN A FRESH `bash` PROCESS, NOT A SUBSHELL. Row 19's property is "a refusal is not MUTE under
# set -e", and bash disables errexit — and IGNORES a re-enabling `set -e` — for everything executed
# inside an `if` condition or the left side of `||`, which is exactly where mutate_file calls its
# check function. A `( set -e; … )` subshell there inherits the ignored state and the un-guarded
# mutant renders identically to the guarded original. A child process starts with its own flags.
# THE SEAM IS THE PROCESS BOUNDARY, NOT THE READER. The first cut of this driver stubbed
# `_bs_query_rows` itself, and the stub's `empty` arm wrote ZERO bytes where the real reader
# writes ONE blank line (`printf '%s\n' "$rows"`); four review agents then found that the real
# byte shape graded `unreadable` where the render said `silent` — the stub's shape had become the
# fixture's shape. So the driver now extracts the REAL `_bs_query_rows` and `_bs_read_remedy` from
# the script under test and stubs `doppler` (the process the reader execs), recording its argv so
# the `--since`/`--grep`/`--limit` operands are pinned, and emitting each fixture exactly as the
# real query would print it (rows on stdout; an HTTP-error body on stdout with rc 22).
BS_READER_FN="$(awk '/^_bs_query_rows\(\) \{$/,/^\}$/' "$BODY_SH")"
BS_REMEDY_FN="$(awk '/^_bs_read_remedy\(\) \{$/,/^\}$/' "$BODY_SH")"
# (#8178) `_bs_read_remedy` now CALLS `bs_read_classify` instead of carrying the rc=22
# partition inline. The driver runs the extracted function text in a fresh `bash` under
# `set -euo pipefail`, so without the classifier the rc=22 arm dies on an unbound command
# and the render assertions go RED. Extract it from the library and inline it too.
# Extracted by the same awk-by-name shape as the two above, so a rename breaks loudly
# here rather than silently degrading the arm.
BS_CLASSIFY_LIB="$REPO_ROOT/scripts/lib/betterstack-read-classify.sh"
BS_CLASSIFY_FN="$(awk '/^bs_read_classify\(\) \{$/,/^\}$/' "$BS_CLASSIFY_LIB")"
assert "#8054 render driver: the REAL reader and remedy functions extract non-vacuously" "[[ \$(printf '%s\n' \"\$BS_READER_FN\" | wc -l) -gt 3 && \$(printf '%s\n' \"\$BS_REMEDY_FN\" | wc -l) -gt 10 ]]"
# Non-vacuity for the classifier too: an awk range that matches nothing yields an empty
# string, which would inline cleanly and leave the arm dying exactly as it would have
# without this change — a silent regression wearing a green suite.
assert "#8178 render driver: bs_read_classify extracts non-vacuously" "[[ \$(printf '%s\n' \"\$BS_CLASSIFY_FN\" | wc -l) -gt 5 ]]"
RENDER_TMPDS="$(mktemp)"
render_2_0() {
  local region="$1" code="$2" body="$3" pmode="$4" hmode="$5" tmpd driver rc=0
  tmpd="$(mktemp -d)"; printf '%s\n' "$tmpd" >> "$RENDER_TMPDS"
  driver="$tmpd/driver.sh"
  {
    printf 'cd %q || exit 97\n' "$REPO_ROOT"
    printf 'set -euo pipefail\n'
    printf 'export RUNNER_TEMP=%q TMPDIR=%q\n' "$tmpd" "$tmpd"
    printf 'BASE="https://stub.invalid"; WEBHOOK_SECRET="stub"; CF_ACCESS_CLIENT_ID="stub"; CF_ACCESS_CLIENT_SECRET="stub"\n'
    printf 'INNGEST_HOST="soleur-inngest"; INNGEST_HOST_NAME="soleur-inngest-prd"; FLIP_LIVENESS_SINCE="15m"\n'
    printf 'STUB_CODE=%q; STUB_BODY=%q; PMODE=%q; HMODE=%q; TMPD=%q\n' "$code" "$body" "$pmode" "$hmode" "$tmpd"
    printf 'H5_PROBE_ROW=%q; H5_HB_ROW=%q\n' "$H5_PROBE_ROW" "$H5_HB_ROW"
    printf 'DONE_PROBE_ROW=%q; ARMED_PROBE_ROW=%q; DONE_HB_ROW=%q; ARMED_HB_ROW=%q\n' "$DONE_PROBE_ROW" "$ARMED_PROBE_ROW" "$DONE_HB_ROW" "$ARMED_HB_ROW"
    printf 'SERVING_PROBE_ROW=%q; WRONGHOST_PROBE_ROW=%q; STALE_PROBE_ROW=%q; SCHEMA7_PROBE_ROW=%q; UNKNOWNFLAG_PROBE_ROW=%q; ABORTED_PROBE_ROW=%q\n' \
      "$SERVING_PROBE_ROW" "$WRONGHOST_PROBE_ROW" "$STALE_PROBE_ROW" "$SCHEMA7_PROBE_ROW" "$UNKNOWNFLAG_PROBE_ROW" "$ABORTED_PROBE_ROW"
    printf 'ROLLBACKFLAG_HB_ROW=%q; ABORTED_HB_ROW=%q\n' "$ROLLBACKFLAG_HB_ROW" "$ABORTED_HB_ROW"
    printf '%s\n' "$BS_CLASSIFY_FN"
    printf '%s\n' "$BS_READER_FN"
    printf '%s\n' "$BS_REMEDY_FN"
    cat <<'DRIVER'
curl() { local o=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && o="$2"; shift; done; printf '%s' "$STUB_BODY" > "$o"; printf '%s' "$STUB_CODE"; }
# doppler <run args…> -- bash scripts/betterstack-query.sh --since S --grep T --limit N : the process
# the real reader execs. Records the reader's argv, then answers per the --grep term and the mode.
doppler() {
  local term="" a
  for a in "$@"; do [[ "${_prev:-}" == "--grep" ]] && term="$a"; _prev="$a"; done
  printf '%s\n' "$*" >> "$TMPD/doppler.argv"
  case "$term" in
    SOLEUR_INNGEST_SERVER_PROBE)
      case "$PMODE" in
        h5)        printf '%s\n' "$H5_PROBE_ROW"; return 0 ;;
        done)      printf '%s\n' "$DONE_PROBE_ROW"; return 0 ;;
        armed)     printf '%s\n' "$ARMED_PROBE_ROW"; return 0 ;;
        empty)     return 0 ;;
        serving)     printf '%s\n' "$SERVING_PROBE_ROW"; return 0 ;;
        wronghost)   printf '%s\n' "$WRONGHOST_PROBE_ROW"; return 0 ;;
        stale)       printf '%s\n' "$STALE_PROBE_ROW"; return 0 ;;
        schema7)     printf '%s\n' "$SCHEMA7_PROBE_ROW"; return 0 ;;
        unknownflag) printf '%s\n' "$UNKNOWNFLAG_PROBE_ROW"; return 0 ;;
        aborted)     printf '%s\n' "$ABORTED_PROBE_ROW"; return 0 ;;
        badjson)     printf 'not json\n'; return 0 ;;
        fail)      printf '{"exception":"Code: 241. DB::Exception: Memory limit exceeded; source under maintenance"}'; return 22 ;;
        authfail)  printf '{"exception":"Code: 516. DB::Exception: u123secretuser-connect: Authentication failed: password is incorrect, or there is no user with such name."}'; return 22 ;;
        forbidden) touch "$TMPD/PROBE_READ_HAPPENED"; return 0 ;;
      esac ;;
    inngest-cutover-flip)
      case "$HMODE" in
        h5)        printf '%s\n' "$H5_HB_ROW"; return 0 ;;
        done)      printf '%s\n' "$DONE_HB_ROW"; return 0 ;;
        armed)     printf '%s\n' "$ARMED_HB_ROW"; return 0 ;;
        empty)     return 0 ;;
        rollbackflag) printf '%s\n' "$ROLLBACKFLAG_HB_ROW"; return 0 ;;
        aborted)      printf '%s\n' "$ABORTED_HB_ROW"; return 0 ;;
        badjson)      printf 'not json\n'; return 0 ;;
        fail)         printf '{"exception":"Code: 241. DB::Exception: Memory limit exceeded; source under maintenance"}'; return 22 ;;
        forbidden) touch "$TMPD/HB_READ_HAPPENED"; return 0 ;;
      esac ;;
  esac
  return 99
}
DRIVER
    printf 'source %q\n' "$region"
    printf 'echo "__REGION_FELL_THROUGH__"\n'
  } > "$driver"
  bash "$driver" 2>&1 || rc=$?
  echo "__RC=$rc"
  echo "__TMPD=$tmpd"   # the caller runs this in $(…), so a global would not survive; parse it
}
# render_tmpd_of <render-output> — the render's scratch dir (swept by scratch_cleanup via
# RENDER_TMPDS; a `SCRATCH+=` inside render_2_0 would land in the `$(…)` subshell and be lost —
# measured: 14 dirs leaked per run before this).
render_tmpd_of() { printf '%s\n' "$1" | sed -n 's/^__TMPD=//p' | tail -1; }
# The web-host probe's REAL refusal body (run 34529824513, 2026-09-10) — the only non-200 that
# admits the dark arm.
FF_BODY='inngest-registry-probe: FATAL /v0/gql functions query failed or non-array (errors=["__FETCH_FAILED__"] data_keys=[]); is the dedicated inngest-server reachable at http://10.0.1.40:8288/v0/gql?'
# shellcheck disable=SC2034  # the *_OUT captures are read inside assert's eval'd condition strings
H5_OUT="$(render_2_0 "$REGION_FILE" 500 "$FF_BODY" h5 h5)"
assert "#8054 H5 render: the dark arm PASSES and falls through to 2.1 (rc 0)" "printf '%s\n' \"\$H5_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$H5_OUT\" | grep -cx '__REGION_FELL_THROUGH__' >/dev/null"
assert "#8054 H5 render: the pre-arm notice names P1-5 and the webhook code" "printf '%s\n' \"\$H5_OUT\" | grep -cE '^::notice::2\.0 expected pre-arm \(P1-5\): webhook probe HTTP 500' >/dev/null"
assert "#8054 H5 render: the dark notice carries boot_id=<36-char uuid> then flag=(aborted|rolled-back)" \
  "printf '%s\n' \"\$H5_OUT\" | grep -E '^::notice::2\.0 dark-host arm PASSED' | grep -cE 'boot_id=[0-9a-f-]{36}.*flag=(aborted|rolled-back)' >/dev/null"
assert "#8054 H5 render: the dark notice says in plain words that the refusal to start is the correct pre-flip posture" \
  "printf '%s\n' \"\$H5_OUT\" | grep -cF 'intentionally refusing to start until op=arm; a non-200 loopback with the server not active is the correct pre-flip posture, not a fault' >/dev/null"
assert "#8054 H5 render: the notice reports BOTH ages and the heartbeat flag from the emit file (no raw row)" \
  "printf '%s\n' \"\$H5_OUT\" | grep -E '^::notice::2\.0 dark-host arm PASSED' | grep -cE 'probe row [0-9]+s old with flag=rolled-back, FSM heartbeat [0-9]+s old with flag=rolled-back' >/dev/null && ! printf '%s\n' \"\$H5_OUT\" | grep -c 'zz_trailing' >/dev/null"
H5_TMPD="$(render_tmpd_of "$H5_OUT")"
assert "#8054 H5 render: the REAL reader was exec'd twice with the pinned operands (24h/SOLEUR_INNGEST_SERVER_PROBE/500, 30m/inngest-cutover-flip/200)" \
  "grep -qE -- '--since 24h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500' '$H5_TMPD/doppler.argv' && grep -qE -- '--since 30m --grep inngest-cutover-flip --limit 200' '$H5_TMPD/doppler.argv' && [[ \$(wc -l < '$H5_TMPD/doppler.argv') -eq 2 ]]"
assert "#8054 H5 render: the heartbeat window (30m) is WIDER than the gate's 900 s bound and the probe window (24h) wider than 5400 s" \
  "[[ 1800 -gt 900 && 86400 -gt 5400 ]] && grep -qE -- '--since 30m --grep inngest-cutover-flip' '$H5_TMPD/doppler.argv' && grep -qE -- '--since 24h --grep SOLEUR' '$H5_TMPD/doppler.argv'"
assert "#8054 H5 render: the webhook body appears exactly once, as a plain line" \
  "[[ \$(printf '%s\n' \"\$H5_OUT\" | grep -c '__FETCH_FAILED__') -eq 1 ]] && printf '%s\n' \"\$H5_OUT\" | grep -c '^2\.0 webhook body (HTTP 500, informational' >/dev/null"
# shellcheck disable=SC2034  # read inside assert's eval'd condition
SILENT_OUT="$(render_2_0 "$REGION_FILE" 500 "$FF_BODY" empty h5)"
assert "#8054 silent render: zero probe rows REFUSE with the silent remedy and rc 1 (silence is not darkness)" \
  "printf '%s\n' \"\$SILENT_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$SILENT_OUT\" | grep -cE '^::error::2\.0 REFUSED \(silent\)' >/dev/null && ! printf '%s\n' \"\$SILENT_OUT\" | grep -c '__REGION_FELL_THROUGH__' >/dev/null"
# shellcheck disable=SC2034  # read inside assert's eval'd condition
FAILREAD_OUT="$(render_2_0 "$REGION_FILE" 500 "$FF_BODY" fail h5)"
assert "#8054 read-failure render: probe rc 22 (maintenance body) routes to the REAL read remedy — 'under maintenance', body NOT printed, never a host verdict" \
  "printf '%s\n' \"\$FAILREAD_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$FAILREAD_OUT\" | grep -cE '^::error::2\.0 probe read: the ClickHouse read path is under maintenance' >/dev/null && ! printf '%s\n' \"\$FAILREAD_OUT\" | grep -c 'Memory limit exceeded' >/dev/null && printf '%s\n' \"\$FAILREAD_OUT\" | grep -cF 'NOTHING about the dedicated host was measured' >/dev/null"
# THE CREDENTIAL-REJECTED BODY NAMES THE USERNAME. A ClickHouse 403 body is `Code: 516.
# DB::Exception: <BETTERSTACK_QUERY_USERNAME>: Authentication failed…` — half of the Basic-auth pair,
# injected by doppler inside the reader so GitHub never masks it, on a PUBLIC repo's run log.
# The remedy must classify it and never print it (security + observability review, 2026-09-11).
# shellcheck disable=SC2034  # read inside assert's eval'd condition
AUTHFAIL_OUT="$(render_2_0 "$REGION_FILE" 500 "$FF_BODY" authfail h5)"
assert "#8054 auth-failure render: a credentials-rejected read body is classified and NEVER printed (the username must not reach the run log)" \
  "printf '%s\n' \"\$AUTHFAIL_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$AUTHFAIL_OUT\" | grep -cE '^::error::2\.0 probe read: the ClickHouse read path REJECTED the credentials' >/dev/null && ! printf '%s\n' \"\$AUTHFAIL_OUT\" | grep -c 'u123secretuser' >/dev/null"
# shellcheck disable=SC2034  # read inside assert's eval'd condition
FSMSILENT_OUT="$(render_2_0 "$REGION_FILE" 500 "$FF_BODY" h5 empty)"
assert "#8054 fsm_silent render: a dark probe row with no same-boot heartbeat REFUSES (freshness cannot be established)" \
  "printf '%s\n' \"\$FSMSILENT_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$FSMSILENT_OUT\" | grep -cE '^::error::2\.0 REFUSED \(fsm_silent\)' >/dev/null"
# H6 — the reachable-empty arm: webhook 200 + registry_empty=true, NO Better Stack read at all.
# Positive control for the read markers: a non-200 webhook with the same stubs MUST leave both
# markers, or the H6 absence assertion below is vacuous.
CTRL_OUT="$(render_2_0 "$REGION_FILE" 500 "$FF_BODY" forbidden forbidden)"; CTRL_TMPD="$(render_tmpd_of "$CTRL_OUT")"
assert "#8054 marker control: the dark arm performs both reads (markers present) — so H6's absence is a measurement" \
  "[[ -e '$CTRL_TMPD/PROBE_READ_HAPPENED' && -e '$CTRL_TMPD/HB_READ_HAPPENED' ]] && printf '%s\n' \"\$CTRL_OUT\" | grep -cx '__RC=1' >/dev/null"
H6_OUT="$(render_2_0 "$REGION_FILE" 200 '{"registry_empty":true,"function_count":0}' forbidden forbidden)"; H6_TMPD="$(render_tmpd_of "$H6_OUT")"
assert "#8054 H6 render: the reachable-empty arm still passes (rc 0, pre-flight clear, then the #8072 warning)" \
  "printf '%s\n' \"\$H6_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$H6_OUT\" | grep -c 'pre-flight clear' >/dev/null && printf '%s\n' \"\$H6_OUT\" | grep -cE '^::warning::2\.0: a dedicated host that ANSWERS pre-arm' >/dev/null"
assert "#8054 H6 render: the reachable-empty arm performed NO Better Stack read (it must not route through the gate)" \
  "[[ ! -e '$H6_TMPD/PROBE_READ_HAPPENED' && ! -e '$H6_TMPD/HB_READ_HAPPENED' ]]"
# shellcheck disable=SC2034  # read inside assert's eval'd condition
H6N_OUT="$(render_2_0 "$REGION_FILE" 200 '{"registry_empty":false,"function_count":3}' forbidden forbidden)"
assert "#8054 H6 render: the reachable NON-empty arm still aborts with the P1-6 remediation, rc 1" \
  "printf '%s\n' \"\$H6N_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$H6N_OUT\" | grep -cE '^::error::Remediation \(P1-6\).*scheduled-inngest-health' >/dev/null"
# webhook_path — a CF Access 403 and a 500 WITHOUT the refusal signature both refuse BEFORE any
# Better Stack read; a stale dark row + fresh heartbeat must not be consulted when the live path
# said nothing about the host.
# shellcheck disable=SC2034  # read inside assert's eval'd condition
WP403_OUT="$(render_2_0 "$REGION_FILE" 403 '{"error":"cf access"}' forbidden forbidden)"; WP403_TMPD="$(render_tmpd_of "$WP403_OUT")"
assert "#8054 webhook_path render: HTTP 403 refuses naming the webhook path (op=registry-probe), rc 1, with NO Better Stack read" \
  "printf '%s\n' \"\$WP403_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$WP403_OUT\" | grep -cE '^::error::2\.0 REFUSED \(webhook_path\).*op=registry-probe' >/dev/null && [[ ! -e '$WP403_TMPD/PROBE_READ_HAPPENED' && ! -e '$WP403_TMPD/HB_READ_HAPPENED' ]]"
# shellcheck disable=SC2034  # read inside assert's eval'd condition
WP500_OUT="$(render_2_0 "$REGION_FILE" 500 'inngest-registry-probe: FATAL /v0/gql functions query failed or non-array (errors=["some other graphql error"] data_keys=["functions"])' forbidden forbidden)"; WP500_TMPD="$(render_tmpd_of "$WP500_OUT")"
assert "#8054 webhook_path render: HTTP 500 WITHOUT __FETCH_FAILED__ (a reachable server's GQL error) refuses as webhook_path, no read" \
  "printf '%s\n' \"\$WP500_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$WP500_OUT\" | grep -cE '^::error::2\.0 REFUSED \(webhook_path\)' >/dev/null && [[ ! -e '$WP500_TMPD/PROBE_READ_HAPPENED' ]]"
assert "#8054 webhook_path render: the refusal never falls through to 2.1" \
  "! printf '%s\n' \"\$WP403_OUT\" | grep -c '__REGION_FELL_THROUGH__' >/dev/null && ! printf '%s\n' \"\$WP500_OUT\" | grep -c '__REGION_FELL_THROUGH__' >/dev/null"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# #8079 — op=registry-probe routes its non-200 branch through the SAME gate. The region is
# extracted by its markers (opened BEFORE `SIG=` so the driver, under set -u, binds CODE/BODY
# itself) and sourced by the same render_2_0 driver — stubbed curl, REAL reader, REAL lib.
# ═══════════════════════════════════════════════════════════════════════════════════════════════
PROBE_REGION_FILE="$(mktemp)"; SCRATCH+=("$PROBE_REGION_FILE")
awk '/# ---- registry-probe host-state gate \(#8079\)/{f=1} f&&/# ---- end registry-probe host-state gate \(#8079\)/{exit} f' "$BODY_SH" > "$PROBE_REGION_FILE"
PROBE_REGION_N=$(grep -cv '^[[:space:]]*#' "$PROBE_REGION_FILE" || true)
assert "#8079 probe region extraction is non-vacuous (>90 non-comment lines, got $PROBE_REGION_N)" "[[ '$PROBE_REGION_N' -gt 90 ]]"
assert "#8079 probe region starts at SIG= (binds CODE/BODY itself; a later start dies on unbound CODE under set -u) and ends at the arm's fi" \
  "grep -vE '^[[:space:]]*(#|$)' '$PROBE_REGION_FILE' | sed -n '1p' | grep -cE '^    SIG=' >/dev/null && grep -vE '^[[:space:]]*(#|$)' '$PROBE_REGION_FILE' | sed -n '\$p' | grep -cE '^    fi$' >/dev/null"
# Selection control: the markers must select the REGISTRY-PROBE arm, not 2.0's — a marker
# collision would source 2.0 here and every render below would certify the wrong arm.
# Herestring, not `grep -v | grep -q`: the producer is ~16 KB, `grep -q` exits on its first match
# and the producer's next write() takes EPIPE under pipefail — measured flaking 1 in 8 under load.
_PROBE_REGION_NC="$(grep -v '^[[:space:]]*#' "$PROBE_REGION_FILE" || true)"
assert "#8079 probe region is the registry-probe arm, not 2.0 (carries RPG_VERDICT, no ERG_VERDICT)" \
  "grep -q 'RPG_VERDICT' <<<\"\$_PROBE_REGION_NC\" && ! grep -q 'ERG_VERDICT' <<<\"\$_PROBE_REGION_NC\""
# The markers are the extractor's whole authority: a second copy of either (a decoy in a comment,
# an illustrative block) silently re-targets the region, and code placed between the end marker
# and the arm's `;;` executes live while no render and no static row ever sees it.
assert "#8079 both region markers occur EXACTLY once in the script" \
  "[[ \$(grep -c '# ---- registry-probe host-state gate (#8079)' '$BODY_SH') -eq 1 && \$(grep -c '# ---- end registry-probe host-state gate (#8079)' '$BODY_SH') -eq 1 ]]"
assert "#8079 the end marker is the arm's last non-blank line before its ;; (no code lives outside the region's reach)" \
  "[[ \$(grep -A2 '# ---- end registry-probe host-state gate (#8079)' '$BODY_SH' | grep -vE '^[[:space:]]*$' | sed -n '2p') == '    ;;' ]]"
assert "#8079 H3: the probe arm carries no CRON_PERIOD (the extraction did not swallow a sibling arm)" "! grep -q 'CRON_PERIOD' '$PROBE_ARM_FILE'"

# ── static rows over the region (comment-stripped, so a rationale comment cannot satisfy them) ──
PROBE_REGION_CODE="$(mktemp)"; SCRATCH+=("$PROBE_REGION_CODE")
grep -v '^[[:space:]]*#' "$PROBE_REGION_FILE" > "$PROBE_REGION_CODE"
# D5 / AC8 — flat ban on mutating ops and on SSH, anywhere in the region.
assert "#8079 AC8: the probe region names NO mutating op (op=execute|resume|rollback|arm) — this op runs outside a window" \
  "! grep -qE 'op=(execute|resume|rollback|arm)([^a-z-]|\$)' '$PROBE_REGION_CODE'"
assert "#8079 AC8: the probe region never says 'ssh ' as an instruction (lowercase: a command; 'Do NOT SSH' is the opposite)" "! grep -qE '(^|[^a-zA-Z])ssh ' '$PROBE_REGION_CODE'"
# D2 / AC2 — the dark sub-block (non-200 branch up to the `else` terminator) never emits the
# live-measurement triple. Scoped by the `^    else$` terminator, as ANNOT_LEAKS scopes 2.0's.
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
DARK_SUBBLOCK="$(awk '/^    if \[\[ "\$CODE" != "200" \]\]; then$/{f=1} f&&/^    else$/{exit} f' "$PROBE_REGION_CODE")"
assert "#8079 AC2 dark sub-block extraction is non-vacuous and stops at the else terminator" \
  "[[ \$(grep -c . <<<\"\$DARK_SUBBLOCK\") -gt 60 ]] && ! grep -q 'REG_EMPTY=' <<<\"\$DARK_SUBBLOCK\""
assert "#8079 AC2: the dark sub-block emits none of registry_empty= / function_count= / ids=[ (reserved for the live HTTP-200 measurement)" \
  "! grep -qE 'registry_empty=|function_count=|ids=\[' <<<\"\$DARK_SUBBLOCK\""
assert "#8079 AC2 control: the 200 path (outside the sub-block) DOES emit the triple, so the absence above is a measurement" \
  "grep -qE 'registry_empty=\\\$REG_EMPTY function_count=\\\$REG_COUNT ids=\[' '$PROBE_REGION_CODE'"
# D2 / AC3 — the caveat warning: two greppable clause openers, the field named with NO trailing
# `=` (which is what keeps it clear of AC2), and the follow-up op named.
assert "#8079 AC3: the dark warning carries both clause openers and names op=doublefire-probe" \
  "grep -E '^[[:space:]]*echo \"::warning::registry-probe: What this establishes:' '$PROBE_REGION_CODE' | grep -c 'What it does not establish:' >/dev/null && grep -E '^[[:space:]]*echo \"::warning::registry-probe: What this establishes:' '$PROBE_REGION_CODE' | grep -c 'op=doublefire-probe' >/dev/null"
assert "#8079 AC3: the warning names registry_empty with NO trailing = (a mutation appending =false must redden AC2)" \
  "grep -E '^[[:space:]]*echo \"::warning::registry-probe: What this establishes:' '$PROBE_REGION_CODE' | grep -cE 'registry_empty was not measured' >/dev/null && ! grep -E '^[[:space:]]*echo \"::warning::registry-probe: What this establishes:' '$PROBE_REGION_CODE' | grep -c 'registry_empty=' >/dev/null"
# D6 — webhook_path names op=inventory AND carries the discrimination rule in the string.
assert "#8079 D6: the webhook_path refusal names op=inventory with its discrimination rule (200 -> hook; non-200 -> path)" \
  "grep -E 'REFUSED \(webhook_path\)' '$PROBE_REGION_CODE' | grep -c 'op=inventory' >/dev/null && grep -E 'REFUSED \(webhook_path\)' '$PROBE_REGION_CODE' | grep -cE 'returns 200 the path is healthy.*if it also fails, the path is at fault' >/dev/null"
# The per-arm exit/no-SSH pairing lives in _arm_exit_gaps above (D10 block); this view of the
# case feeds the AC4 static rows.
_probe_case="$(awk '/^      case "\$RPG_VERDICT" in$/{f=1} f&&/^      esac$/{exit} f' "$PROBE_REGION_CODE")"
# D8 / AC4 static half — the done message must NOT reproduce 2.0's remedy, and must qualify the
# hourly sample's staleness; the emit read must not interpolate RPG_HB_AGE on the E11 path.
assert "#8079 AC4: no done-branch message says 'the cutover already completed', names op=verify, or names restart-inngest-server" \
  "! grep -qE 'the cutover already completed|op=verify|restart-inngest-server' <<<\"\$_probe_case\""
assert "#8079 AC4: the hourly-row done branch carries the 90-minute staleness qualifier and does not interpolate RPG_HB_AGE" \
  "grep -A3 'REFUSED (flag_armed/done): the dedicated host is NOT ANSWERING and its cutover flag' <<<\"\$_probe_case\" | grep -c 'lag reality by up to 90 minutes' >/dev/null && ! grep -A6 'REFUSED (flag_armed/done): the dedicated host is NOT ANSWERING and its cutover flag' <<<\"\$_probe_case\" | grep -c 'RPG_HB_AGE' >/dev/null"
# AC10 — no annotation interpolates a raw rows file, BODY, or CAUSE; the only body prints are
# the CR/LF-stripped CAUSE on plain lines.
# Scoped to the DARK sub-block (the code this PR adds). The 200 path's malformed-JSON branch
# carries a PRE-EXISTING raw `echo "$BODY"` that AC9 pins byte-for-byte to main; it is recorded
# in the PR rather than fixed here, because fixing it breaks the content pin the plan requires.
assert "#8079 AC10: no ::error/notice/warning:: in the dark sub-block interpolates RPG_PROBE_ROWS, RPG_HB_ROWS, \$RPG_DIR, \$BODY/\${BODY} or \$CAUSE/\${CAUSE} (echo or printf)" \
  "! grep -E '(echo|printf) .*\"::(error|notice|warning)::' <<<\"\$DARK_SUBBLOCK\" | grep -cE 'RPG_PROBE_ROWS|RPG_HB_ROWS|\\\$\{?RPG_DIR|\\\$\{?BODY|\\\$\{?CAUSE|registry-probe-body' >/dev/null"
assert "#8079 AC10: in the dark sub-block every print of the webhook body uses the CR/LF-stripped CAUSE on a plain line, never raw BODY (echo or printf, either brace form)" \
  "[[ \$(grep -cE '^[[:space:]]*echo \"registry-probe webhook body \(HTTP \\\$CODE.*\\\$\{CAUSE:-' <<<\"\$DARK_SUBBLOCK\") -eq 2 ]] && ! grep -E '^[[:space:]]*(echo|printf) ' <<<\"\$DARK_SUBBLOCK\" | grep -v 'CAUSE' | grep -cE '\\\$\{?BODY|registry-probe-body' >/dev/null"
# AC9 — the HTTP-200 path is content-pinned modulo leading whitespace and comments, VERBATIM,
# the way AC7 pins 2.0 (see its comment: a comparison against origin/main is main==main once this
# merges, and went RED the moment the arm was restructured — review of #8079 measured 725/726
# with HEAD standing in for main). The one intended change vs the pre-#8079 text is the REGISTERED
# warning's cutover-state qualifier: a populated registry is the healthy state after step 2.4.
_strip() { sed -E 's/^[[:space:]]+//' | grep -v '^#' | grep -v '^$'; }
_HEAD_200="$(awk '/^    else$/{f=1;next} f&&/^    fi$/{exit} f' "$PROBE_REGION_FILE" | _strip || true)"
_PIN_200="$(cat <<'PIN200'
if ! echo "$BODY" | jq -e 'type=="object" and has("registry_empty")' >/dev/null 2>&1; then
echo "::error::registry-probe did not return a {registry_empty,function_count,function_ids} object"; echo "$BODY"; exit 1
fi
REG_EMPTY=$(echo "$BODY" | jq -r '.registry_empty')
REG_COUNT=$(echo "$BODY" | jq -r '.function_count // 0')
REG_IDS=$(echo "$BODY" | jq -r '[.function_ids[]?] | join(",")')
echo "::notice::registry-probe: registry_empty=$REG_EMPTY function_count=$REG_COUNT ids=[$REG_IDS]"
if [[ "$REG_EMPTY" == "false" ]]; then
echo "::warning::registry-probe: the dedicated host (10.0.1.40) has $REG_COUNT REGISTERED function(s). Before the cutover flag reads done this is UNEXPECTED (an SDK registered against a host that should be dark); after cutover step 2.4 it is the HEALTHY state — production functions register here. Pre-cutover, run op=doublefire-probe to establish whether those registrations have also EXECUTED runs (registration alone is not proof of a double-fire)."
else
echo "::notice::registry-probe: dedicated registry is EMPTY — no SDK has registered functions against 10.0.1.40."
fi
PIN200
)"
assert "#8079 AC9: the HTTP-200 path is content-identical to the verbatim pin, modulo indentation and comments ($(printf '%s\n' "$_HEAD_200" | grep -c .) lines)" \
  "[[ \"\$_PIN_200\" == \"\$_HEAD_200\" ]] && [[ \$(printf '%s\n' \"\$_HEAD_200\" | grep -c .) -ge 10 ]]"

# ── renders ───────────────────────────────────────────────────────────────────────────────────
# AC1 — dark: rc 0, the HOST-STATE notice, the caveat warning, and the region reaches its END
# (the else-branch is skipped, the fi is reached) rather than falling into the 200 path.
RPG_DARK_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" h5 h5)"; RPG_DARK_TMPD="$(render_tmpd_of "$RPG_DARK_OUT")"
assert "#8079 AC1 dark render: rc 0 and the region reaches its end (no exit, no fall-through into the 200 path)" \
  "printf '%s\n' \"\$RPG_DARK_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$RPG_DARK_OUT\" | grep -cx '__REGION_FELL_THROUGH__' >/dev/null"
assert "#8079 AC1 dark render: prints the HOST-STATE VERDICT notice with boot_id, both ages and both flags from the emit file" \
  "printf '%s\n' \"\$RPG_DARK_OUT\" | grep -E '^::notice::registry-probe HOST-STATE VERDICT: dark' | grep -cE 'boot_id=[0-9a-f-]{36}: probe row [0-9]+s old with flag=rolled-back, FSM heartbeat [0-9]+s old with flag=rolled-back' >/dev/null"
assert "#8079 AC1/AC3 dark render: the caveat warning is emitted with both clauses and the follow-up op" \
  "printf '%s\n' \"\$RPG_DARK_OUT\" | grep -E '^::warning::registry-probe: What this establishes:' | grep -c 'What it does not establish:.*op=doublefire-probe' >/dev/null"
assert "#8079 AC2 dark render: the OUTPUT carries none of registry_empty= / function_count= / ids=[ (a dark verdict is not a live measurement)" \
  "! printf '%s\n' \"\$RPG_DARK_OUT\" | grep -cE 'registry_empty=|function_count=|ids=\[' >/dev/null"
assert "#8079 dark render: the REAL reader was exec'd twice with the pinned operands (same windows as 2.0)" \
  "grep -qE -- '--since 24h --grep SOLEUR_INNGEST_SERVER_PROBE --limit 500' '$RPG_DARK_TMPD/doppler.argv' && grep -qE -- '--since 30m --grep inngest-cutover-flip --limit 200' '$RPG_DARK_TMPD/doppler.argv' && [[ \$(wc -l < '$RPG_DARK_TMPD/doppler.argv') -eq 2 ]]"
assert "#8079 dark render: the webhook body appears exactly once, as a plain informational line" \
  "[[ \$(printf '%s\n' \"\$RPG_DARK_OUT\" | grep -c '__FETCH_FAILED__') -eq 1 ]] && printf '%s\n' \"\$RPG_DARK_OUT\" | grep -c '^registry-probe webhook body (HTTP 500, informational' >/dev/null"
# AC7 — webhook_path: a 403 and a 500 without the signature refuse BEFORE any read, rc 1, naming
# op=inventory; the marker control from 2.0 (both reads happen on the graded path) makes the
# absence a measurement.
RPG_WP403_OUT="$(render_2_0 "$PROBE_REGION_FILE" 403 '{"error":"cf access"}' forbidden forbidden)"; RPG_WP403_TMPD="$(render_tmpd_of "$RPG_WP403_OUT")"
RPG_WP500_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 'inngest-registry-probe: FATAL /v0/gql functions query failed or non-array (errors=["some other graphql error"] data_keys=["functions"])' forbidden forbidden)"; RPG_WP500_TMPD="$(render_tmpd_of "$RPG_WP500_OUT")"
RPG_CTRL_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" forbidden forbidden)"; RPG_CTRL_TMPD="$(render_tmpd_of "$RPG_CTRL_OUT")"
assert "#8079 AC7 marker control: on the graded path BOTH reads happen (so the absences below are measurements)" \
  "[[ -e '$RPG_CTRL_TMPD/PROBE_READ_HAPPENED' && -e '$RPG_CTRL_TMPD/HB_READ_HAPPENED' ]]"
assert "#8079 AC7 render: HTTP 403 refuses as webhook_path naming op=inventory, rc 1, NO Better Stack read, never reaches the end" \
  "printf '%s\n' \"\$RPG_WP403_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_WP403_OUT\" | grep -cE '^::error::registry-probe REFUSED \(webhook_path\).*op=inventory' >/dev/null && [[ ! -e '$RPG_WP403_TMPD/PROBE_READ_HAPPENED' && ! -e '$RPG_WP403_TMPD/HB_READ_HAPPENED' ]] && ! printf '%s\n' \"\$RPG_WP403_OUT\" | grep -c '__REGION_FELL_THROUGH__' >/dev/null"
assert "#8079 AC7 render: HTTP 500 WITHOUT __FETCH_FAILED__ refuses as webhook_path, rc 1, no read" \
  "printf '%s\n' \"\$RPG_WP500_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_WP500_OUT\" | grep -cE '^::error::registry-probe REFUSED \(webhook_path\)' >/dev/null && [[ ! -e '$RPG_WP500_TMPD/PROBE_READ_HAPPENED' ]]"
# AC4 — flag_armed 2x2: four DISTINCT messages, each naming the sample it quotes.
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_FA11D_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" 'done' h5)"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_FA11A_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" armed h5)"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_FA13D_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" h5 'done')"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_FA13A_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" h5 armed)"
assert "#8079 AC4 E11/done render: rc 1, headline names flag_armed/done and 'scheduling may be DOWN' and points at the plain next steps, quotes the HOURLY row with the 90-minute qualifier" \
  "printf '%s\n' \"\$RPG_FA11D_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_FA11D_OUT\" | grep -cE '^::error::registry-probe REFUSED \(flag_armed/done\).*scheduling may be DOWN — the numbered registry-probe: next steps are in this step.s log' >/dev/null && printf '%s\n' \"\$RPG_FA11D_OUT\" | grep -c 'HOURLY probe row.*lag reality by up to 90 minutes' >/dev/null"
assert "#8079 AC4 E11/done render: the ordered steps are PLAIN log lines, the watchdog read comes FIRST, the state script names its prerequisite, the runbook is third" \
  "printf '%s\n' \"\$RPG_FA11D_OUT\" | grep -c '^registry-probe: 1. read the latest watchdog verdict first' >/dev/null && printf '%s\n' \"\$RPG_FA11D_OUT\" | grep -c '^registry-probe: 2. read the host.*inngest-host-state.sh (needs BETTERSTACK_QUERY_' >/dev/null && printf '%s\n' \"\$RPG_FA11D_OUT\" | grep -c '^registry-probe: 3. .*runbooks/inngest-server.md' >/dev/null"
assert "#8079 AC4 E11/armed render: rc 1, names flag_armed with the HOURLY row and 'in flight', dispatches nothing" \
  "printf '%s\n' \"\$RPG_FA11A_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_FA11A_OUT\" | grep -cE '^::error::registry-probe REFUSED \(flag_armed\): the dedicated host.s newest HOURLY probe row.*in flight.*Dispatch nothing' >/dev/null"
assert "#8079 AC4 E13/done render: rc 1, headline quotes the same-boot HEARTBEAT as a live sample and does NOT call it hourly" \
  "printf '%s\n' \"\$RPG_FA13D_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_FA13D_OUT\" | grep -cE '^::error::registry-probe REFUSED \(flag_armed/done\).*same-boot heartbeat.*a live sample, not the hourly row' >/dev/null && ! printf '%s\n' \"\$RPG_FA13D_OUT\" | grep -c 'HOURLY probe row' >/dev/null"
assert "#8079 AC4 E13/armed render: rc 1, quotes the same-boot heartbeat, 'in flight right now'" \
  "printf '%s\n' \"\$RPG_FA13A_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_FA13A_OUT\" | grep -cE '^::error::registry-probe REFUSED \(flag_armed\): the flip FSM.s newest same-boot heartbeat.*in flight right now' >/dev/null"
assert "#8079 AC4: the four 2x2 headlines are pairwise DISTINCT" \
  "[[ \$(for o in \"\$RPG_FA11D_OUT\" \"\$RPG_FA11A_OUT\" \"\$RPG_FA13D_OUT\" \"\$RPG_FA13A_OUT\"; do printf '%s\n' \"\$o\" | grep -E '^::error::registry-probe REFUSED \(flag_armed' | sed -n '1p'; done | sort -u | wc -l) -eq 4 ]]"
assert "#8079 AC4/D5: no 2x2 message names a mutating op or 2.0's remedy" \
  "! printf '%s\n%s\n%s\n%s\n' \"\$RPG_FA11D_OUT\" \"\$RPG_FA11A_OUT\" \"\$RPG_FA13D_OUT\" \"\$RPG_FA13A_OUT\" | grep -cE 'op=(execute|resume|rollback|arm)([^a-z-]|\$)|the cutover already completed|op=verify|restart-inngest-server' >/dev/null"
# AC6 — a refusing fixture still prints its ::error:: (the || RPG_RC=\$? guard is load-bearing).
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_SILENT_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" empty h5)"
assert "#8079 AC6 silent render: rc 1 with the silent remedy — and it names the 2026-08-14 ingest-402 case BEFORE the host-replace step" \
  "printf '%s\n' \"\$RPG_SILENT_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_SILENT_OUT\" | grep -E '^::error::registry-probe REFUSED \(silent\)' | grep -cE 'confirm INGEST health/quota.*402.*Two consecutive probe-unavailable' >/dev/null"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_FSMSILENT_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" h5 empty)"
assert "#8079 fsm_silent render: rc 1 with the fsm_silent remedy" \
  "printf '%s\n' \"\$RPG_FSMSILENT_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_FSMSILENT_OUT\" | grep -cE '^::error::registry-probe REFUSED \(fsm_silent\)' >/dev/null"
# D4 — the read-failure arms delegate to _bs_read_remedy with the TRAILING step operand, so the
# nine messages report 'registry-probe', never '2.0'. This is the render that proves D4's operand
# reaches the printer; the census row proved the printer has no hardcoded step left.
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_FAILREAD_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" fail h5)"
assert "#8079 D4 read-failure render: rc 22 routes to the shared remedy and it reports 'registry-probe', never '2.0' (the step operand landed)" \
  "printf '%s\n' \"\$RPG_FAILREAD_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$RPG_FAILREAD_OUT\" | grep -cE '^::error::registry-probe probe read: the ClickHouse read path is under maintenance' >/dev/null && printf '%s\n' \"\$RPG_FAILREAD_OUT\" | grep -cE '^::error::registry-probe probe read failed — NOTHING about the dedicated host was measured' >/dev/null && ! printf '%s\n' \"\$RPG_FAILREAD_OUT\" | grep -c '::error::2\.0 ' >/dev/null"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_AUTHFAIL_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" authfail h5)"
assert "#8079 D4 auth-failure render: a credentials-rejected body is classified and NEVER printed (the username must not reach the run log)" \
  "printf '%s\n' \"\$RPG_AUTHFAIL_OUT\" | grep -cE '^::error::registry-probe probe read: the ClickHouse read path REJECTED the credentials' >/dev/null && ! printf '%s\n' \"\$RPG_AUTHFAIL_OUT\" | grep -c 'u123secretuser' >/dev/null"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_HBFAIL_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" h5 fail)"
assert "#8079 D4 heartbeat read-failure render: rc 22 on the HEARTBEAT leg routes to the shared remedy labelled 'heartbeat' and reports 'registry-probe', never '2.0' (the step operand landed on BOTH legs)" \
  "grep -qx '__RC=1' <<<\"\$RPG_HBFAIL_OUT\" && grep -qE '^::error::registry-probe heartbeat read: the ClickHouse read path is under maintenance' <<<\"\$RPG_HBFAIL_OUT\" && ! grep -q '::error::2\.0 ' <<<\"\$RPG_HBFAIL_OUT\""
# One render per remaining token: rc 1, its own REFUSED (<token>) headline carrying the property
# the remedy claims, no 2.0-labelled line, no fall-through. `out` is a local of the helper and the
# eval'd condition reads it by bash's dynamic scoping.
_rpg_refusal() {  # $1 label  $2 pmode  $3 hmode  $4 token  $5 headline ERE
  local out _rr_re="$5"; out="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" "$2" "$3")"
  assert "#8079 $1 render ($2/$3): rc 1, REFUSED ($4) headline carries its property, no ::error::2.0, no fall-through" \
    "grep -qx '__RC=1' <<<\"\$out\" && grep -E '^::error::registry-probe REFUSED \\($4\\)' <<<\"\$out\" | grep -cE \"\$_rr_re\" >/dev/null && ! grep -q '::error::2\\.0 ' <<<\"\$out\" && ! grep -q '__REGION_FELL_THROUGH__' <<<\"\$out\""
}
_rpg_refusal 'host_serving' serving h5 host_serving 'row \([0-9]+s old — hourly.*90 minutes\).*WAS serving.*hook just failed to reach 10\.0\.1\.40:8288.*inngest-host-state\.sh.*op=inventory reads the WEB host'
_rpg_refusal 'wrong_host' wronghost h5 wrong_host 'Two causes with opposite remedies.*dead host, not a mislabel.*inngest-host-state\.sh.*treat this as silent'
_rpg_refusal 'stale_row' stale h5 stale_row '90-minute bound.*FSM transition.*Wait for the next hourly probe'
_rpg_refusal 'stale_schema' schema7 h5 stale_schema 'not probe_schema=8.*unbumped pin re-delivers the same bytes'
_rpg_refusal 'flag_unreadable E11' unknownflag h5 flag_unreadable 'HOURLY probe row \([0-9]+s old\).*Do NOT write the flag by hand'
_rpg_refusal 'flag_unreadable E13' h5 rollbackflag flag_unreadable 'same-boot heartbeat \([0-9]+s old\).*reports it as __UNREADABLE__'
_rpg_refusal 'unreadable rc=0' badjson h5 unreadable 'answered \(rc=0\).*Nothing about the host was measured'
_rpg_refusal 'fsm_unreadable rc=0' h5 badjson fsm_unreadable 'answered \(rc=0\).*not a host verdict'
# H2 — must-PASS non-canonical: `aborted` is the OTHER pre-arm flag; a suite whose only dark
# fixture is rolled-back cannot tell "pre-arm" from "rolled-back".
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_ABORTED_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY" aborted aborted)"
assert "#8079 H2 must-PASS non-canonical: an aborted/aborted host renders dark at rc 0 with flag=aborted on both samples" \
  "grep -qx '__RC=0' <<<\"\$RPG_ABORTED_OUT\" && grep -E '^::notice::registry-probe HOST-STATE VERDICT: dark' <<<\"\$RPG_ABORTED_OUT\" | grep -c 'flag=aborted, FSM heartbeat [0-9]*s old with flag=aborted' >/dev/null"
# D2 truth — the warning states the INTERVAL it measured and the rollback caveat, never a
# since-boot universal (a rollback is a stop, not a reboot: the server served on this same boot).
assert "#8079 dark render: the warning claims only the measured interval and carries the same-boot rollback caveat, never 'since boot'/'has not been bound on this boot'" \
  "grep -E '^::warning::registry-probe: What this establishes:' <<<\"\$RPG_DARK_OUT\" | grep -cE 'NOT serving as of its [0-9]+s-old probe row.*no FSM transition has landed since.*in THAT interval.*after a rollback the server was bound and served on this same boot' >/dev/null && ! grep -qE 'since boot|has not been bound on this boot|no SDK can have reached it' <<<\"\$RPG_DARK_OUT\""
# AC9 renders — the 200 path is untouched in behaviour and performs NO Better Stack read.
RPG_200_OUT="$(render_2_0 "$PROBE_REGION_FILE" 200 '{"registry_empty":true,"function_count":0}' forbidden forbidden)"; RPG_200_TMPD="$(render_tmpd_of "$RPG_200_OUT")"
assert "#8079 AC9 render: HTTP 200 + empty registry -> rc 0, the live triple with registry_empty=true, the EMPTY notice, NO Better Stack read" \
  "printf '%s\n' \"\$RPG_200_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$RPG_200_OUT\" | grep -c '^::notice::registry-probe: registry_empty=true function_count=0 ids=\[\]' >/dev/null && printf '%s\n' \"\$RPG_200_OUT\" | grep -c 'dedicated registry is EMPTY' >/dev/null && [[ ! -e '$RPG_200_TMPD/PROBE_READ_HAPPENED' && ! -e '$RPG_200_TMPD/HB_READ_HAPPENED' ]]"
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_200N_OUT="$(render_2_0 "$PROBE_REGION_FILE" 200 '{"registry_empty":false,"function_count":3,"function_ids":["a","b","c"]}' forbidden forbidden)"
assert "#8079 AC9 render: HTTP 200 + non-empty registry -> rc 0 (diagnostic, not gating), live triple with the ids, the REGISTERED warning" \
  "printf '%s\n' \"\$RPG_200N_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$RPG_200N_OUT\" | grep -c '^::notice::registry-probe: registry_empty=false function_count=3 ids=\[a,b,c\]' >/dev/null && printf '%s\n' \"\$RPG_200N_OUT\" | grep -cE '^::warning::registry-probe: the dedicated host \(10.0.1.40\) has 3 REGISTERED' >/dev/null"
# AC10 render — annotation log-injection: a body carrying a literal newline followed by a
# forged ::notice:: must NOT produce that line at column 0 in the output.
# shellcheck disable=SC2034  # read inside the eval'd assert conditions below
RPG_INJ_OUT="$(render_2_0 "$PROBE_REGION_FILE" 500 "$FF_BODY"$'\n'"::notice::PASS forged" h5 h5)"
assert "#8079 AC10 render: a webhook body with an embedded newline + forged ::notice:: is CR/LF-stripped — the forged line never lands at column 0" \
  "! printf '%s\n' \"\$RPG_INJ_OUT\" | grep -cx '::notice::PASS forged' >/dev/null && printf '%s\n' \"\$RPG_INJ_OUT\" | grep -c '__FETCH_FAILED__.* ::notice::PASS forged' >/dev/null"

# ── mutate_file: the matrix rows that live in the SCRIPT (17, 18, 19) and the lib (20) ────
# Patches a PRISTINE copy of a file with one single-line `sed` (same cmp + exactly-one-line guards
# as the dark-gate suite's mutate()), then re-runs a named assertion FUNCTION against the copy and
# asserts it FAILS. Before this, matrix rows 17-19 were PR-body claims: this suite was static
# `assert` over awk-extracted text and nothing patched a copy.
mutate_file() {
  local label="$1" src="$2" expr="$3" check_fn="$4" mutated changed
  mutated="$(mktemp)"; SCRATCH+=("$mutated")
  # A malformed expression is a FAILED ROW, not a dead suite: under set -e a sed parse error here
  # aborted the whole run with no Results line and no floor verdict (measured on a `RANGE/pat/d`
  # missing its braces — every row after it, and the exact-floor gate, silently never ran).
  if ! sed "$expr" "$src" > "$mutated" 2>/dev/null; then
    assert "#8054 mutate[$label]: the sed expression itself failed to parse — the row ran nothing" "false"; return
  fi
  if cmp -s "$mutated" "$src"; then
    assert "#8054 mutate[$label]: the mutation matched NOTHING (byte-identical copy) — the line drifted" "false"; return
  fi
  changed="$(diff "$src" "$mutated" | grep -c '^<' || true)"
  if [[ "$changed" != "1" ]]; then
    assert "#8054 mutate[$label]: the mutation changed $changed lines, expected exactly 1" "false"; return
  fi
  if "$check_fn" "$src"; then :; else
    assert "#8054 mutate[$label]: the UNMUTATED file does not satisfy the property — the row proves nothing" "false"; return
  fi
  if "$check_fn" "$mutated"; then
    assert "#8054 mutate[$label]: the mutation did NOT redden the property — the assertion is decorative" "false"
  else
    assert "#8054 mutate[$label]: the mutation reddens the property (load-bearing)" "true"
  fi
}
# Known-negative for mutate_file itself: a comment-only mutation must be reported as NOT reddening.
_kn_p=$PASS; _kn_f=$FAIL
check_always_true() { grep -qE '^set -euo pipefail$' "$1"; }
mutate_file "known-negative" "$BODY_SH" 's|^# _bs_read_remedy <label> <rc> <errfile> <rowsfile> \[step\] — .*|# (comment mutated by the known-negative)|' check_always_true >/dev/null
if [[ "$FAIL" -eq $((_kn_f + 1)) && "$PASS" -eq "$_kn_p" ]]; then
  FAIL=$((FAIL - 1)); assert "#8054 mutate_file known-negative: a comment-only mutation is reported as NOT reddening" "true"
else
  PASS=$_kn_p; FAIL=$_kn_f; assert "#8054 mutate_file known-negative: the harness reports 'reddens' for a dead line — it cannot tell a live line from a dead one" "false"
fi
# Row 17 — the reader swallows the query's rc. Property: with doppler stubbed to rc 7, the
# extracted reader returns 7.
check_reader_returns_rc() {
  local f="$1" fn rc=0
  fn="$(awk '/^_bs_query_rows\(\) \{$/,/^\}$/' "$f")"
  [[ -n "$fn" ]] || return 1
  ( set +e; eval "$fn"; doppler() { return 7; }; _bs_query_rows 15m t 5 >/dev/null 2>&1; exit $? ) || rc=$?
  [[ "$rc" -eq 7 ]]
}
mutate_file "row17 reader swallows rc" "$BODY_SH" 's|^  rows=\$(doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since "\$since" --grep "\$term" --limit "\$limit" 2>"\$errfile") \|\| rc=\$?$|  rows=$(doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since "$since" --grep "$term" --limit "$limit" 2>"$errfile") \|\| true|' check_reader_returns_rc
# Row 18 — the *) arm falls through. Property: the *) arm exits 1.
check_star_arm_exits() {
  awk '/^  execute\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$1" | awk '/^        \*\)$/{f=1} f' | sed -n '1,8p' | grep -cE 'exit 1 ;;' >/dev/null
}
mutate_file "row18 *) arm falls through" "$BODY_SH" 's|^          echo "::error::2.0 REFUSED: the dark-host gate returned an unrecognised verdict .*; exit 1 ;;$|          : ;;|' check_star_arm_exits
# Row 19 — the production call un-guarded. Property (DYNAMIC): a refusing fixture still prints its
# ::error:: — under set -e a bare $(…) aborts before the case, fail-closed but MUTE.
check_refusal_is_not_mute() {
  local f="$1" region out
  region="$(mktemp)"; SCRATCH+=("$region")
  awk '/# ---- 2\.0 empty-registry pre-flight/{f=1} f&&/# ---- 2\.1 capture/{exit} f' "$f" > "$region"
  out="$(render_2_0 "$region" 500 "$FF_BODY" empty h5)"
  printf '%s\n' "$out" | grep -cE '^::error::2\.0 REFUSED \(silent\)' >/dev/null && printf '%s\n' "$out" | grep -cx '__RC=1' >/dev/null
}
mutate_file "row19 gate call un-guarded" "$BODY_SH" 's|^      ERG_VERDICT="\$(inngest_execute_registry_gate \(.*\))" \|\| ERG_RC=\$?$|      ERG_VERDICT="$(inngest_execute_registry_gate \1)"|' check_refusal_is_not_mute
# webhook_path gate — neuter the signature test. Property (DYNAMIC): a 403 must refuse without a read.
check_403_refuses_without_read() {
  local f="$1" region out tmpd
  region="$(mktemp)"; SCRATCH+=("$region")
  awk '/# ---- 2\.0 empty-registry pre-flight/{f=1} f&&/# ---- 2\.1 capture/{exit} f' "$f" > "$region"
  out="$(render_2_0 "$region" 403 '{"error":"cf access"}' forbidden forbidden)"; tmpd="$(render_tmpd_of "$out")"
  printf '%s\n' "$out" | grep -cE '^::error::2\.0 REFUSED \(webhook_path\)' >/dev/null && [[ ! -e "$tmpd/PROBE_READ_HAPPENED" ]]
}
# Range-scoped to the 2.0 region since #8079: the probe arm carries this line byte-identically
# (the plumbing-parity guard requires it), so a file-global sed would change 2 lines.
mutate_file "webhook_path gate neutered" "$BODY_SH" '/# ---- 2\.0 empty-registry pre-flight/,/# ---- 2\.1 capture/s|^      if \[\[ "\$CODE" != "500" \|\| "\$BODY" != \*"__FETCH_FAILED__"\* \]\]; then$|      if false; then|' check_403_refuses_without_read

# ── #8079 — mutation rows over the PROBE region. Each sed is RANGE-SCOPED to the probe markers,
# because the signature test, the guarded source, the mktemp and the emit loop now exist
# byte-identically in both arms (the plumbing-parity guard REQUIRES that); a file-global
# single-line sed would change 2 lines and mutate_file refuses it. That refusal fired on 2.0's
# own `webhook_path gate neutered` row the moment the probe arm landed — the row above is now
# scoped the same way.
_RPG_RANGE='/# ---- registry-probe host-state gate (#8079)/,/# ---- end registry-probe host-state gate (#8079)/'
_rpg_region_of() {  # $1 = (possibly mutated) script → prints a temp file holding its probe region
  local r; r="$(mktemp)"; SCRATCH+=("$r")
  awk '/# ---- registry-probe host-state gate \(#8079\)/{f=1} f&&/# ---- end registry-probe host-state gate \(#8079\)/{exit} f' "$1" > "$r"
  printf '%s' "$r"
}
# Row A — the || RPG_RC=$? guard removed. Property (DYNAMIC): a refusing fixture still prints its
# ::error::; un-guarded, set -e aborts before the case — fail-closed but MUTE.
check_rpg_refusal_is_not_mute() {
  local out; out="$(render_2_0 "$(_rpg_region_of "$1")" 500 "$FF_BODY" empty h5)"
  printf '%s\n' "$out" | grep -cE '^::error::registry-probe REFUSED \(silent\)' >/dev/null && printf '%s\n' "$out" | grep -cx '__RC=1' >/dev/null
}
mutate_file "rpg gate call un-guarded" "$BODY_SH" "${_RPG_RANGE}"'s|^      RPG_VERDICT="\$(inngest_execute_registry_gate \(.*\))" \|\| RPG_RC=\$?$|      RPG_VERDICT="$(inngest_execute_registry_gate \1)"|' check_rpg_refusal_is_not_mute
# Row B — the signature test neutered. Property (DYNAMIC): a 403 must refuse without a read.
check_rpg_403_refuses_without_read() {
  local out tmpd; out="$(render_2_0 "$(_rpg_region_of "$1")" 403 '{"error":"cf access"}' forbidden forbidden)"; tmpd="$(render_tmpd_of "$out")"
  printf '%s\n' "$out" | grep -cE '^::error::registry-probe REFUSED \(webhook_path\)' >/dev/null && [[ ! -e "$tmpd/PROBE_READ_HAPPENED" ]]
}
mutate_file "rpg webhook_path gate neutered" "$BODY_SH" "${_RPG_RANGE}"'s|^      if \[\[ "\$CODE" != "500" \|\| "\$BODY" != \*"__FETCH_FAILED__"\* \]\]; then$|      if false; then|' check_rpg_403_refuses_without_read
# Row C — D1 inverted: `dark` made to exit 1. Property (DYNAMIC): the dark render is rc 0 and
# reaches the region's end.
check_rpg_dark_exits_zero() {
  local out; out="$(render_2_0 "$(_rpg_region_of "$1")" 500 "$FF_BODY" h5 h5)"
  printf '%s\n' "$out" | grep -cx '__RC=0' >/dev/null && printf '%s\n' "$out" | grep -cx '__REGION_FELL_THROUGH__' >/dev/null
}
mutate_file "rpg dark verdict exits 1" "$BODY_SH" "${_RPG_RANGE}"'s|^\(          echo "::warning::registry-probe: What this establishes:.*\) ;;$|\1; exit 1 ;;|' check_rpg_dark_exits_zero
# Row D — D2 violated: the warning names the field WITH a trailing `=false`. Property (STATIC +
# DYNAMIC): the dark sub-block and the dark OUTPUT carry none of the reserved triple.
check_rpg_dark_emits_no_triple() {
  local r out; r="$(_rpg_region_of "$1")"
  ! grep -qE 'registry_empty=|function_count=|ids=\[' <<<"$(awk '/^    if \[\[ "\$CODE" != "200" \]\]; then$/{f=1} f&&/^    else$/{exit} f' "$r" | grep -v '^[[:space:]]*#')" \
    && out="$(render_2_0 "$r" 500 "$FF_BODY" h5 h5)" && ! grep -qE 'registry_empty=|function_count=|ids=\[' <<<"$out"
}
mutate_file "rpg warning appends =false to the reserved field" "$BODY_SH" "${_RPG_RANGE}"'s|registry_empty was not measured, because a dark host answers no read\.|registry_empty=false was not measured, because a dark host answers no read.|' check_rpg_dark_emits_no_triple
# Row E — D7 row 4's mutation: a request body on the probe's curl. Property (STATIC): the #6617
# no-request-body row (judged on the curl's joined logical line) must redden — proving `-d/-T
# adjacent to curl` is still load-bearing after `mktemp -d` was allowed.
check_rpg_no_request_body() {
  local code; code="$(mktemp)"; SCRATCH+=("$code")
  awk '/^[[:space:]]+registry-probe\)$/,/^[[:space:]]+rearm\)$/' "$1" > "$code.arms"; SCRATCH+=("$code.arms")
  _probe_arms_code_of "$code.arms" > "$code"
  ! grep -qE '[[:space:]](-d|-T)([[:space:]]|=)' <<<"$(grep -E '(^|[^a-z-])curl[[:space:]]' "$code")" 
}
mutate_file "rpg curl gains a request body" "$BODY_SH" "${_RPG_RANGE}"'s|^      "\$BASE/inngest-registry-probe" \|\| echo "000")$|      -d '"'"'{}'"'"' "$BASE/inngest-registry-probe" \|\| echo "000")|' check_rpg_no_request_body
# Row F — D5 violated: a remedy names op=execute. Property (STATIC): AC8's flat ban reds.
check_rpg_no_mutating_op() {
  ! grep -qE 'op=(execute|resume|rollback|arm)([^a-z-]|$)' <<<"$(grep -v '^[[:space:]]*#' "$(_rpg_region_of "$1")")" 
}
mutate_file "rpg remedy names op=execute" "$BODY_SH" "${_RPG_RANGE}"'s|Dispatch nothing from here; this op is a read and its answer would describe a host mid-transition\.|Then re-dispatch op=execute.|' check_rpg_no_mutating_op
# Row G — D8 violated: the done branch reverts to 2.0's remedy. Property (STATIC): AC4's ban on
# "the cutover already completed" reds.
check_rpg_done_not_2_0_remedy() {
  ! grep -qE 'the cutover already completed|op=verify|restart-inngest-server' <<<"$(awk '/^      case "\$RPG_VERDICT" in$/{f=1} f&&/^      esac$/{exit} f' "$(_rpg_region_of "$1")" | grep -v '^[[:space:]]*#')" 
}
mutate_file "rpg done branch reverts to 2.0 remedy" "$BODY_SH" "${_RPG_RANGE}"'s|^\(              echo "::error::registry-probe REFUSED (flag_armed/done): the dedicated host is NOT ANSWERING and its cutover flag reads .done.\.\) Since cutover step 2\.4 this host owns production cron scheduling, so scheduling may be DOWN — the numbered registry-probe: next steps are in this step.s log\."$|\1 done => the cutover already completed: dispatch op=verify."|' check_rpg_done_not_2_0_remedy
# Row H — M1.2: the probe arm's call renamed. Property: the census (registry-probe=1) reds.
check_rpg_census() { _gate_census "$1" >/dev/null; }
mutate_file "rpg gate call renamed (census M1.2)" "$BODY_SH" "${_RPG_RANGE}"'s|^      RPG_VERDICT="\$(inngest_execute_registry_gate |      RPG_VERDICT="$(inngest_executeX_registry_gate |' check_rpg_census
# Row I — M1.1: a THIRD consumer added to rollback), the arm that follows BOTH members (a census
# that stopped after two would still be green on the first arm). The sed replaces the arm's
# first comment line (an append has zero `<` lines and mutate_file refuses it).
mutate_file "third gate consumer in rollback) (census M1.1)" "$BODY_SH" 's|^    # op=rollback — the AUTHORED reverse of the cutover (P1-13)\. As of #6369 it has TWO$|    _third="$(inngest_execute_registry_gate --rows-file /dev/null)" \|\| true|' check_rpg_census
# Row J — a SECOND call on the same physical line as the censused one (a line count sees 2, an
# occurrence count sees 3). Property: the whole-file occurrence total is 2.
check_rpg_gate_total() { [[ "$(_gate_total "$1")" -eq 2 ]]; }
mutate_file "second gate call on the censused line" "$BODY_SH" "${_RPG_RANGE}"'s|^\(      RPG_VERDICT="\$(inngest_execute_registry_gate .*\) \|\| RPG_RC=\$?$|\1 \|\| RPG_RC=$?; _x="$(inngest_execute_registry_gate)"|' check_rpg_gate_total
# Row K — M2.6: the 2x2 collapsed to the hourly sample (nested sed range so the SAME `if` in
# flag_unreadable is left alone: mutate_file refuses a 2-line diff). Property: four distinct headlines.
check_rpg_2x2_distinct() {
  local r n; r="$(_rpg_region_of "$1")"
  # Ages are normalised before the distinct-count: the headlines interpolate the row age, and two
  # renders straddling a second boundary print 421s/422s — a mutant collapsing the 2x2 then
  # survived 1 run in 3 on the age alone (measured).
  n=$(for m in "done h5" "armed h5" "h5 done" "h5 armed"; do render_2_0 "$r" 500 "$FF_BODY" $m | grep -E '^::error::registry-probe REFUSED \(flag_armed' | sed -n '1p'; done | sed -E 's/[0-9]+s old/Ns old/g' | sort -u | wc -l) || true
  [[ "${n:-0}" -eq 4 ]]
}
mutate_file "rpg 2x2 collapsed to the hourly sample (M2.6)" "$BODY_SH" "${_RPG_RANGE}"'{/^        flag_armed)$/,/^        host_serving)$/s|^          if \[\[ "\$RPG_HB_FLAG" == "__UNREAD__" \]\]; then$|          if true; then|}' check_rpg_2x2_distinct
# Row L — M2.7: the trap deleted. Property: plumbing parity (the trap's position is in the region).
check_rpg_plumb_parity() { [[ "$(_plumb "$EXEC_ARM_FILE")" == "$(_plumb "$(_rpg_region_of "$1")")" ]]; }
mutate_file "rpg trap deleted (M2.7)" "$BODY_SH" "${_RPG_RANGE}"'{/^      trap '"'"'rm -rf "\$RPG_DIR"'"'"' EXIT$/d}' check_rpg_plumb_parity
# Row M — M2.8: the *) arm falls through; Row N — S1: host_serving loses its exit 1. Property for
# both: the per-arm exit/no-SSH row (tokens + *).
check_rpg_arm_exits() { [[ -z "$(_arm_exit_gaps "$(_rpg_region_of "$1")")" ]]; }
mutate_file "rpg *) arm falls through (M2.8)" "$BODY_SH" "${_RPG_RANGE}"'s|^          echo "::error::registry-probe REFUSED: the dark-host gate returned a token this arm does not handle .*; exit 1 ;;$|          : ;;|' check_rpg_arm_exits
mutate_file "rpg host_serving loses its exit 1 (S1)" "$BODY_SH" "${_RPG_RANGE}"'s|^\(          echo "::error::registry-probe REFUSED (host_serving):.*\)"; exit 1 ;;$|\1" ;;|' check_rpg_arm_exits
# Row O — M2.9: a real gh invocation appended to an echo's physical line; Row P — a $(gh …) NESTED
# inside the annotation string (the emptier's blind spot). Property for both: the tool census == 2.
check_rpg_tool_count() {
  local code; code="$(mktemp)"; SCRATCH+=("$code")
  awk '/^[[:space:]]+registry-probe\)$/,/^[[:space:]]+rearm\)$/' "$1" > "$code.arms"; SCRATCH+=("$code.arms")
  _probe_arms_code_of "$code.arms" > "$code"
  [[ "$(grep -cE '(^|[^a-z-])(curl|wget|nc|ncat|socat|python3?|perl|gh|aws|doppler|hcloud)[[:space:]]' "$code")" == 2 ]]
}
mutate_file "rpg gh invocation appended to an echo line (M2.9)" "$BODY_SH" "${_RPG_RANGE}"'s|^\(          echo "::error::registry-probe REFUSED (silent):.*\)"; exit 1 ;;$|\1"; gh workflow run cutover-inngest.yml -f op=inventory; exit 1 ;;|' check_rpg_tool_count
mutate_file "rpg \$(gh …) nested inside an annotation string" "$BODY_SH" "${_RPG_RANGE}"'s|^\(          echo "::error::registry-probe REFUSED (silent):.*\)Do NOT SSH the host\."; exit 1 ;;$|\1Do NOT SSH the host. $(gh run list --limit 1)"; exit 1 ;;|' check_rpg_tool_count
# Row Q — S3: the HEARTBEAT leg's step operand reverted to 2.0. Property: the heartbeat
# read-failure render reports 'registry-probe', never '2.0'.
check_rpg_hb_step_operand() {
  local out; out="$(render_2_0 "$(_rpg_region_of "$1")" 500 "$FF_BODY" h5 fail)"
  grep -qE '^::error::registry-probe heartbeat read:' <<<"$out" && ! grep -q '::error::2\.0 ' <<<"$out"
}
mutate_file "rpg heartbeat _bs_read_remedy step operand reverted to 2.0 (S3)" "$BODY_SH" "${_RPG_RANGE}"'s|^            _bs_read_remedy heartbeat "\$RPG_HB_RC" "\$RPG_HB_ERR" "\$RPG_HB_ROWS" "registry-probe"$|            _bs_read_remedy heartbeat "$RPG_HB_RC" "$RPG_HB_ERR" "$RPG_HB_ROWS" "2.0"|' check_rpg_hb_step_operand
# Row R — S6: the E11 flag_unreadable message quotes the HEARTBEAT age for the HOURLY row (the
# wrong-sample class D8 fixed for flag_armed). Property: the E11 render prints a numeric row age.
check_rpg_e11_unreadable_sample() {
  local out; out="$(render_2_0 "$(_rpg_region_of "$1")" 500 "$FF_BODY" unknownflag h5)"
  grep -E '^::error::registry-probe REFUSED \(flag_unreadable\)' <<<"$out" | grep -cE 'HOURLY probe row \([0-9]+s old\)' >/dev/null
}
mutate_file "rpg E11 flag_unreadable quotes the heartbeat age (S6)" "$BODY_SH" "${_RPG_RANGE}"'s|^\(            echo "::error::registry-probe REFUSED (flag_unreadable): the dedicated host.s newest HOURLY probe row (\)\${RPG_ROW_AGE}s old)|\1${RPG_HB_AGE}s old)|' check_rpg_e11_unreadable_sample
# Row 20 — the lib's allowlist retyped with one member missing. Property: set-equality with P1-5.
check_e11_set_equal() { [[ "$(e11_set_of "$1")" == "$P15_SET" ]]; }
mutate_file "row20 E11 allowlist minus flushed" "$GATE_LIB" "s|^    armed\|flipping\|flushed\|done) printf 'armed' ;;|    armed\|flipping\|done) printf 'armed' ;;|" check_e11_set_equal

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# #6921 — the execute → quiesce-web → execute loop is drivable (D1 CI half, D1c, D4, D5)
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ncl <file> — the file with comment lines removed (every static pin below reads CODE, not prose
# about code; a comment restating the old shape must not satisfy a pin on the new one).
ncl() { grep -v '^[[:space:]]*#' "$1" || true; }

# ── 2.1 (FR9): the capture's source is read with a live default and surfaced on the ONE notice ──
# The host adds `source:"persisted"` + `captured_at` only when it resumes from the file the quiesce
# handler wrote; a live answer carries no `source` field, so the absent field IS the live marker.
# shellcheck disable=SC2016  # literal source lines pinned verbatim, not expansions
S21_SRC_LINE='SOURCE=$(echo "$BODY" | jq -r '"'"'.source // "live"'"'"')'
# shellcheck disable=SC2016
S21_CAT_LINE='CAPTURED_AT=$(echo "$BODY" | jq -r '"'"'.captured_at // ""'"'"')'
S21_SRC_N=$(ncl "$EXEC_ARM_FILE" | sed 's/^[[:space:]]*//' | grep -cxF -- "$S21_SRC_LINE" || true)
S21_CAT_N=$(ncl "$EXEC_ARM_FILE" | sed 's/^[[:space:]]*//' | grep -cxF -- "$S21_CAT_LINE" || true)
assert "#6921 FR9 2.1 reads SOURCE via .source // \"live\" and CAPTURED_AT via .captured_at // \"\" exactly once each (source=$S21_SRC_N captured_at=$S21_CAT_N)" \
  "[[ '$S21_SRC_N' -eq 1 && '$S21_CAT_N' -eq 1 ]]"
S21_NOTICE_N=$(ncl "$EXEC_ARM_FILE" | grep -cE '^[[:space:]]*echo "::notice::2\.1 capture: ' || true)
# shellcheck disable=SC2016  # literal source text, not an expansion
S21_SHAPE_N=$(ncl "$EXEC_ARM_FILE" | grep -F 'echo "::notice::2.1 capture: Σcaptured=$SIGMA_CAPTURED source=$SOURCE${CAPTURED_AT_NOTE} ' | grep -c . || true)
S21_WARN_N=$(ncl "$EXEC_ARM_FILE" | grep -cF '::warning::2.1:' || true)
# shellcheck disable=SC2016
S21_NOTE_SET=$(ncl "$EXEC_ARM_FILE" | grep -cF 'CAPTURED_AT_NOTE=" captured_at=$CAPTURED_AT quiesced_since=$QUIESCED_SINCE rebooted_since_quiesce=$REBOOTED_SINCE_QUIESCE"' || true)
assert "#6921 FR9 2.1 has ONE notice, shaped 'Σcaptured=\$SIGMA_CAPTURED source=\$SOURCE\${CAPTURED_AT_NOTE}', captured_at/quiesced_since/rebooted_since_quiesce set only on the persisted branch, no ::warning::2.1: (notices=$S21_NOTICE_N shape=$S21_SHAPE_N note=$S21_NOTE_SET warn=$S21_WARN_N)" \
  "[[ '$S21_NOTICE_N' -eq 1 && '$S21_SHAPE_N' -eq 1 && '$S21_WARN_N' -eq 0 && '$S21_NOTE_SET' -eq 1 ]] && ncl '$EXEC_ARM_FILE' | grep -B1 -F 'CAPTURED_AT_NOTE=\" captured_at=' | grep -cF 'if [[ \"\$SOURCE\" == \"persisted\" ]]; then' >/dev/null"
# The two new persisted fields are read with an empty default. quiesced_since is a number, so
# `// ""` is safe; rebooted_since_quiesce is a BOOLEAN, and jq's `//` treats `false` as empty — the
# registry_empty trap (#6178) — so `// ""` would print a rebooted=false resume as blank. The read line
# is EXECUTED against false / true / absent, not grepped.
# shellcheck disable=SC2016
S21_QS_LINE='QUIESCED_SINCE=$(echo "$BODY" | jq -r '"'"'.quiesced_since // ""'"'"')'
S21_QS_N=$(ncl "$EXEC_ARM_FILE" | sed 's/^[[:space:]]*//' | grep -cxF -- "$S21_QS_LINE" || true)
# shellcheck disable=SC2016  # a literal regex over source text
S21_RB_LINE="$(ncl "$EXEC_ARM_FILE" | sed 's/^[[:space:]]*//' | grep -E '^REBOOTED_SINCE_QUIESCE=\$\(echo "\$BODY" \| jq -r ' || true)"
s21_rb() { # $1 JSON body → the value the 2.1 read line assigns
  # shellcheck disable=SC2034  # BODY is read by the eval'd 2.1 read line
  local BODY="$1" REBOOTED_SINCE_QUIESCE="__UNSET__"
  [[ "$(printf '%s\n' "$S21_RB_LINE" | grep -c .)" -eq 1 ]] || { echo "__NOT_ONE_LINE__"; return 0; }
  eval "$S21_RB_LINE"
  printf '%s' "$REBOOTED_SINCE_QUIESCE"
}
assert "#6921 FR9 2.1 reads quiesced_since via '// \"\"' once, and rebooted_since_quiesce false-safely (false->'$(s21_rb '{"rebooted_since_quiesce":false}')' true->'$(s21_rb '{"rebooted_since_quiesce":true}')' absent->'$(s21_rb '{}')')" \
  "[[ '$S21_QS_N' -eq 1 && '$(s21_rb '{"rebooted_since_quiesce":false}')' == false && '$(s21_rb '{"rebooted_since_quiesce":true}')' == true && -z '$(s21_rb '{}')' ]]"
# op=capture (the standalone reader) surfaces the same source + captured_at instead of ignoring .source.
CAP_ARM_FILE="$(mktemp)"; SCRATCH+=("$CAP_ARM_FILE")
awk '/^  capture\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$BODY_SH" > "$CAP_ARM_FILE"
# shellcheck disable=SC2016
assert "#6921 FR9 op=capture reads .source // \"live\" + .captured_at and prints both on its notice" \
  "ncl '$CAP_ARM_FILE' | sed 's/^[[:space:]]*//' | grep -cxF -- >/dev/null \"\$S21_SRC_LINE\" && ncl '$CAP_ARM_FILE' | sed 's/^[[:space:]]*//' | grep -cxF -- >/dev/null \"\$S21_CAT_LINE\" && ncl '$CAP_ARM_FILE' | grep -F 'echo \"::notice::capture: ' | grep -F 'source=\$SOURCE' | grep -cF 'captured_at=' >/dev/null"
# PANEL MUTATION R1: `SOURCE="live"` inserted before the `# ---- 2.2` marker stayed green, because
# render_2_2 injects SOURCE from outside the region. Pin it statically: from 2.1's read to the SEAM,
# the ONLY write to SOURCE is 2.1's own read line (assignment, append, read, declare, := default).
s21_source_writes() { # $1 script → count of SOURCE writers from the 2.1 marker to the SEAM marker
  awk '/# ---- 2\.1 capture/{f=1} f&&/# ---- SEAM: operator maintenance-window steps/{exit} f' "$1" \
    | grep -v '^[[:space:]]*#' \
    | grep -cE '(^|[^A-Za-z0-9_])(SOURCE\+?=|\$\{SOURCE:?=)|(^|[;&|[:space:]])(read|declare|local|typeset|export|printf -v)[[:space:]][^#]*(^|[^A-Za-z0-9_$])SOURCE([^A-Za-z0-9_]|$)' || true
}
S21_SOURCE_WRITES="$(s21_source_writes "$BODY_SH")"
assert "#6921 R1 nothing re-assigns SOURCE between the 2.1 read and the 2.2 gate's end (writers=$S21_SOURCE_WRITES, expected 1: the read itself)" "[[ '$S21_SOURCE_WRITES' -eq 1 ]]"
check_source_single_writer() { [[ "$(s21_source_writes "$1")" -eq 1 ]]; }
# shellcheck disable=SC2016
mutate_file "R1 SOURCE re-assigned before the 2.2 marker" "$BODY_SH" 's|^\(    echo "::notice::2\.1 capture: Σcaptured=.*\)$|\1; SOURCE="live"|' check_source_single_writer

# ── D1c (FR15): the rearm) arm's P2-b parser, EXECUTED against the Σ=0 body ─────────────────────
# The on-host rearm script now prints the canonical `re-armed=0 failed=0 total=0` line on an empty
# capture (stderr; the hook returns combined output). The parser region is run as-is in a fresh bash
# under set -euo pipefail, reading a fixture instead of /tmp/rearm-body. The negative control (the
# pre-D1c body, no canonical line) must still refuse — without it a parser that accepts anything
# would pass the Σ=0 row.
RA_REGION="$(mktemp)"; SCRATCH+=("$RA_REGION")
awk '/^  rearm\)$/{a=1} a&&/RBODY=\$\(cat \/tmp\/rearm-body/{f=1} f{print} f&&/::notice::re-arm completed/{exit}' "$BODY_SH" > "$RA_REGION"
RA_N=$(grep -cE '^[[:space:]]*RCOUNTS=\$\(printf .*sed -n' "$RA_REGION" || true)
assert "#6921 FR15 P2-b parser region extracts non-vacuously (RCOUNTS parse lines=$RA_N, ends at the completion notice)" \
  "[[ '$RA_N' -eq 1 ]] && grep -qF 'could not parse' '$RA_REGION' && tail -1 '$RA_REGION' | grep -cF '::notice::re-arm completed' >/dev/null"
run_p2b() { # $1 body → stdout+stderr, then __RC=
  local d rc=0; d="$(mktemp -d)"; printf '%s\n' "$d" >> "$RENDER_TMPDS"
  printf '%s' "$1" > "$d/rearm-body"
  sed "s|/tmp/rearm-body|$d/rearm-body|g" "$RA_REGION" > "$d/region.sh"
  bash -c 'set -euo pipefail; source "$1"' _ "$d/region.sh" 2>&1 || rc=$?
  echo "__RC=$rc"
}
# shellcheck disable=SC2034  # read inside assert's eval'd condition strings
P2B_ZERO_OUT="$(run_p2b $'inngest-rearm-reminders: nothing to re-arm\ninngest-rearm-reminders: re-armed=0 failed=0 held_back=0 total=0\n')"
# shellcheck disable=SC2034
P2B_OLD_OUT="$(run_p2b $'inngest-rearm-reminders: nothing to re-arm\n')"
assert "#6921 FR15 the Σ=0 canonical body (held_back=0) reconciles 0+0+0 == 0 (rc 0), never 'could not parse'" \
  "printf '%s\n' \"\$P2B_ZERO_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$P2B_ZERO_OUT\" | grep -cF '::notice::re-arm completed: rearmed=0 held_back=0 == Σcaptured(total)=0' >/dev/null && ! printf '%s\n' \"\$P2B_ZERO_OUT\" | grep -cF 'could not parse' >/dev/null"
# held_back (records due before the quiesce, already fired on the web scheduler, never POSTed) is a
# SUCCESS term: N+F+H must equal K, and F must be 0. An absent held_back field (a host script that
# predates it) reads as 0 — it is never an unparsed body.
# shellcheck disable=SC2034
P2B_HELD_OUT="$(run_p2b $'inngest-rearm-reminders: held back 1 reminder(s) due before the quiesce: rem-a\ninngest-rearm-reminders: re-armed=2 failed=0 held_back=1 total=3\n')"
assert "#6921 FR15 held_back row: re-armed=2 failed=0 held_back=1 total=3 reconciles (rc 0) and names the held-back id" \
  "printf '%s\n' \"\$P2B_HELD_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$P2B_HELD_OUT\" | grep -cF '::notice::re-arm completed: rearmed=2 held_back=1 == Σcaptured(total)=3' >/dev/null && printf '%s\n' \"\$P2B_HELD_OUT\" | grep -E '^::notice::re-arm held back' | grep -cF 'rem-a' >/dev/null"
# shellcheck disable=SC2034
P2B_NOHELD_OUT="$(run_p2b $'inngest-rearm-reminders: re-armed=0 failed=0 total=0\n')"
assert "#6921 FR15 an absent held_back field reads as 0 (re-armed=0 failed=0 total=0 -> rc 0)" \
  "printf '%s\n' \"\$P2B_NOHELD_OUT\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$P2B_NOHELD_OUT\" | grep -cF 'rearmed=0 held_back=0 == Σcaptured(total)=0' >/dev/null"
# shellcheck disable=SC2034
P2B_SUM_OUT="$(run_p2b $'inngest-rearm-reminders: re-armed=2 failed=0 held_back=0 total=3\n')"
assert "#6921 FR15 N+F+H != K (2+0+0 != 3) refuses as a reconciliation failure (rc 1), not a partial" \
  "printf '%s\n' \"\$P2B_SUM_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$P2B_SUM_OUT\" | grep -cF 're-arm reconciliation FAILED (P2-b): re-armed=2 + failed=0 + held_back=0 != total=3' >/dev/null && ! printf '%s\n' \"\$P2B_SUM_OUT\" | grep -cF 're-arm completed' >/dev/null"
# shellcheck disable=SC2034
P2B_PART_OUT="$(run_p2b $'inngest-rearm-reminders: re-arm failed for reminder_id=rem-b (HTTP 500)\ninngest-rearm-reminders: re-armed=1 failed=1 held_back=1 total=3\n')"
assert "#6921 FR15 failed>0 with a consistent sum is a PARTIAL (rc 1) naming the missing id" \
  "printf '%s\n' \"\$P2B_PART_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$P2B_PART_OUT\" | grep -E '^::error::re-arm PARTIAL' | grep -cF '[rem-b]' >/dev/null && ! printf '%s\n' \"\$P2B_PART_OUT\" | grep -cF 're-arm completed' >/dev/null"
assert "#6921 rearm arm comment: a 503 is cutover-quiesce OR backend-refused (X-Soleur-Unavailable)" \
  "awk '/^  rearm\\)\$/{f=1;next} f&&/^  [a-z-]+\\)\$/{exit} f' '$BODY_SH' | grep -E '^[[:space:]]*#' | grep -F 'X-Soleur-Unavailable' | grep -cF 'backend-refused' >/dev/null"
assert "#6921 FR15 control: the pre-D1c Σ=0 body (no canonical line) still refuses as unparsed (rc 1)" \
  "printf '%s\n' \"\$P2B_OLD_OUT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$P2B_OLD_OUT\" | grep -cF 'could not parse' >/dev/null"

# ── D4 (Guard 3, FR8): 2.2 certifies the QUIESCED unit shape — RENDERED ──────────────────────────
# The 2.2 region is extracted and executed in a fresh bash with `curl` stubbed. Unlike render_2_0's
# fixed answer, 2.2 probes in a loop and calls curl inside $(…), so the stub answers a per-call
# STUB_SEQ (`code:BODYNAME,…`) through a FILE-backed counter — a shell counter would die with each
# command-substitution subshell. A `000` entry reproduces real curl's transport-failure bytes: it
# prints `000` via -w AND exits non-zero, so the script's `|| echo "000"` appends a second 000.
extract_2_2() { awk '/# ---- 2\.2 QUIESCE HARD GATE/{f=1} f&&/# ---- SEAM: operator maintenance-window steps/{exit} f' "$1"; }
R22_REGION="$(mktemp)"; SCRATCH+=("$R22_REGION")
extract_2_2 "$BODY_SH" > "$R22_REGION"
R22_N=$(grep -cv '^[[:space:]]*#' "$R22_REGION" || true)
R22_TMP_REFS=$(grep -c '/tmp/exec-inv' "$R22_REGION" || true)
assert "#6921 2.2 region extraction is non-vacuous (>= 85 non-comment lines, got $R22_N; /tmp/exec-inv refs=$R22_TMP_REFS)" "[[ '$R22_N' -ge 85 && '$R22_TMP_REFS' -ge 5 ]]"
# Synthesized fixtures (cq-test-fixtures-synthesized-only), in the on-host emitter's shapes.
R22_QUIESCED='inngest-inventory: QUIESCED host_id=stub-web-a unit=inactive enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart'
# The hook returns COMBINED output, so the sentinel can sit on a later line behind stderr noise.
R22_QUIESCED_MULTI=$'ERROR: /v0/gql functions query failed (connection refused)\r\ninngest-inventory: QUIESCED host_id=stub-web-b unit=failed enabled=disabled — deliberate stop+disable (op=quiesce-web); no restart'
R22_FATAL=$'ERROR: /v0/gql functions query failed\r\ninngest-inventory: FATAL /v0/gql functions query failed or non-array (errors=["__FETCH_FAILED__"] data_keys=[]) host_id=stub-web-a PAST_CHAR_120_MARKER'
R22_NOT_QUIESCED='inngest-inventory: FATAL unit shape is not QUIESCED (errors=["inngest-inventory: QUIESCED"]) host_id=stub-web-a'
# §4 DISABLED_UNATTRIBUTED: the unit is disabled with no valid quiesce marker — not a deliberate quiesce.
R22_UNATTRIBUTED='inngest-inventory: DISABLED_UNATTRIBUTED host_id=stub-web-a unit=inactive enabled=disabled — scheduler disabled with no valid quiesce marker; not a deliberate quiesce; dispatch op=rollback'
# What adnanh/webhook answers on an HMAC trigger-rule mismatch (403) and an unknown hook id (404), and
# an edge 502 page: none of them carries an `inngest-inventory:` line.
R22_FORBIDDEN='Hook rules were not satisfied.'
R22_NOTFOUND='Hook not found.'
R22_GATEWAY='<html><head><title>502 Bad Gateway</title></head><body>cloudflare</body></html>'
render_2_2() { # $1 region  $2 SOURCE  $3 STUB_SEQ → stdout+stderr, __RC=, __CALLS=
  local region="$1" src="$2" seq="$3" tmpd driver rc=0
  tmpd="$(mktemp -d)"; printf '%s\n' "$tmpd" >> "$RENDER_TMPDS"
  driver="$tmpd/driver.sh"
  # Isolate the region's fixed /tmp/exec-inv scratch path per render (concurrent suites share /tmp).
  sed "s|/tmp/exec-inv|$tmpd/exec-inv|g" "$region" > "$tmpd/region.sh"
  {
    printf 'cd %q || exit 97\n' "$REPO_ROOT"
    printf 'set -euo pipefail\n'
    printf 'BASE="https://stub.invalid"; WEBHOOK_SECRET="stub"; CF_ACCESS_CLIENT_ID="stub"; CF_ACCESS_CLIENT_SECRET="stub"\n'
    printf 'SOURCE=%q; STUB_SEQ=%q; TMPD=%q\n' "$src" "$seq" "$tmpd"
    printf 'QUIESCED_BODY=%q; QUIESCED_MULTI_BODY=%q; FATAL_BODY=%q; NOTQ_BODY=%q; EMPTY_BODY=""\n' \
      "$R22_QUIESCED" "$R22_QUIESCED_MULTI" "$R22_FATAL" "$R22_NOT_QUIESCED"
    printf 'UNATTR_BODY=%q; FORBIDDEN_BODY=%q; NOTFOUND_BODY=%q; GATEWAY_BODY=%q\n' \
      "$R22_UNATTRIBUTED" "$R22_FORBIDDEN" "$R22_NOTFOUND" "$R22_GATEWAY"
    cat <<'DRIVER'
curl() {
  local o="" n entry code name
  while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && o="$2"; shift; done
  n=$(( $(cat "$TMPD/curl.count" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$TMPD/curl.count"
  IFS=',' read -r -a _seq <<< "$STUB_SEQ"
  entry="${_seq[$((n - 1))]:-}"
  if [[ -z "$entry" ]]; then touch "$TMPD/SEQ_EXHAUSTED"; return 99; fi
  code="${entry%%:*}"; name="${entry#*:}"
  if [[ "$code" == "000" ]]; then printf '000'; return 28; fi
  printf '%s' "${!name}" > "$o"
  printf '%s' "$code"
}
DRIVER
    printf 'source %q\n' "$tmpd/region.sh"
    printf 'echo "__REGION_FELL_THROUGH__"\n'
  } > "$driver"
  bash "$driver" 2>&1 || rc=$?
  echo "__RC=$rc"
  echo "__CALLS=$(cat "$tmpd/curl.count" 2>/dev/null || echo 0)"
  [[ -e "$tmpd/SEQ_EXHAUSTED" ]] && echo "__SEQ_EXHAUSTED__"
  return 0
}
# r22_is <output> <verdict> — the verdict the render reached, from the run log alone.
#   passed:  rc 0, the PASSED notice, fell through to the SEAM, no gate failure.
#   still:   rc 1, STILL RUNNING, gate failure, never PASSED.
#   unknown: rc 1, an UNKNOWN quiesce-check line, gate failure, never PASSED.
r22_is() {
  local out="$1" v="$2"
  printf '%s\n' "$out" | grep -c '__SEQ_EXHAUSTED__' >/dev/null && return 1
  case "$v" in
    passed)  printf '%s\n' "$out" | grep -cx '__RC=0' >/dev/null && printf '%s\n' "$out" | grep -cE '^::notice::2\.2 QUIESCE HARD GATE PASSED' >/dev/null \
               && printf '%s\n' "$out" | grep -cx '__REGION_FELL_THROUGH__' >/dev/null && ! printf '%s\n' "$out" | grep -cE '^::error::2\.2 QUIESCE HARD GATE FAILED' >/dev/null ;;
    still)   printf '%s\n' "$out" | grep -cx '__RC=1' >/dev/null && printf '%s\n' "$out" | grep -cE '^quiesce check .*STILL RUNNING' >/dev/null \
               && printf '%s\n' "$out" | grep -cE '^::error::2\.2 QUIESCE HARD GATE FAILED' >/dev/null && ! printf '%s\n' "$out" | grep -cE 'HARD GATE PASSED|__REGION_FELL_THROUGH__' >/dev/null ;;
    unknown) printf '%s\n' "$out" | grep -cx '__RC=1' >/dev/null && printf '%s\n' "$out" | grep -cE '^quiesce check .*UNKNOWN' >/dev/null \
               && printf '%s\n' "$out" | grep -cE '^::error::2\.2 QUIESCE HARD GATE FAILED' >/dev/null && ! printf '%s\n' "$out" | grep -cE 'HARD GATE PASSED|__REGION_FELL_THROUGH__|STILL RUNNING' >/dev/null ;;
    *) return 1 ;;
  esac
}
# shellcheck disable=SC2034  # the R22_* captures are read inside assert's eval'd condition strings
R22_Q3="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,500:QUIESCED_BODY,500:QUIESCED_BODY')"
assert "#6921 Guard3 row1: 3x QUIESCED -> PASSED" "r22_is \"\$R22_Q3\" passed"
# r22_first_verb_is_warned <output> — the FIRST line naming op=quiesce-web is a ::warning::2.2: line
# (an operator reads top-down; the verb that stops production scheduling is never met before the warning).
r22_first_verb_is_warned() { printf '%s\n' "$1" | grep -F 'op=quiesce-web' | sed -n '1p' | grep -cE '^::warning::2\.2: ' >/dev/null; }
# shellcheck disable=SC2034
R22_FL="$(render_2_2 "$R22_REGION" live '500:FATAL_BODY,500:FATAL_BODY,500:FATAL_BODY')"
assert "#6921 Guard3 row2: 3x FATAL + SOURCE=live -> UNKNOWN, remedy names the op=quiesce-web dispatch AFTER the maintenance-window warning" \
  "r22_is \"\$R22_FL\" unknown && printf '%s\n' \"\$R22_FL\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -F 'the unit is not in the quiesced shape (2.1 answered live)' | grep -cF \"gh workflow run cutover-inngest.yml --field op=quiesce-web\" >/dev/null && r22_first_verb_is_warned \"\$R22_FL\" && printf '%s\n' \"\$R22_FL\" | grep -E '^::warning::2\.2: ' | grep -cF 'STOPS production scheduling' >/dev/null"
# shellcheck disable=SC2034
R22_FP="$(render_2_2 "$R22_REGION" persisted '500:FATAL_BODY,500:FATAL_BODY,500:FATAL_BODY')"
assert "#6921 Guard3 row5b: 3x FATAL + SOURCE=persisted -> UNKNOWN naming the stale on-host inventory script + the config-push read, and NOWHERE op=quiesce-web" \
  "r22_is \"\$R22_FP\" unknown && printf '%s\n' \"\$R22_FP\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -cF 'the on-host inngest-inventory.sh likely predates the QUIESCED verdict; confirm the apply-deploy-pipeline-fix.yml run for the merge wrote /usr/local/bin/inngest-inventory.sh (read /hooks/infra-config-status sha256) and re-dispatch op=execute — do NOT re-run quiesce-web' >/dev/null && ! printf '%s\n' \"\$R22_FP\" | grep -cF 'op=quiesce-web' >/dev/null"
# shellcheck disable=SC2034
R22_Q2Q="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,200:EMPTY_BODY,500:QUIESCED_BODY')"
assert "#6921 Guard3 row2m: QUIESCED,200,QUIESCED -> STILL RUNNING (a sentinel never outranks a 200; loop stops at the 200: calls=2)" \
  "r22_is \"\$R22_Q2Q\" still && printf '%s\n' \"\$R22_Q2Q\" | grep -cx '__CALLS=2' >/dev/null && r22_first_verb_is_warned \"\$R22_Q2Q\""
# shellcheck disable=SC2034
R22_QQ2="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,500:QUIESCED_BODY,200:EMPTY_BODY')"
assert "#6921 Guard3 row5: QUIESCED,QUIESCED,200 -> STILL RUNNING (the loop keeps reading after a sentinel: calls=3)" \
  "r22_is \"\$R22_QQ2\" still && printf '%s\n' \"\$R22_QQ2\" | grep -cx '__CALLS=3' >/dev/null"
# shellcheck disable=SC2034
R22_000="$(render_2_2 "$R22_REGION" live '000:EMPTY_BODY,000:EMPTY_BODY,000:EMPTY_BODY')"
assert "#6921 Guard3: 3x 000 -> UNREADABLE / UNKNOWN, fail-closed" \
  "r22_is \"\$R22_000\" unknown && printf '%s\n' \"\$R22_000\" | grep -cE '^quiesce check .*UNREADABLE' >/dev/null && printf '%s\n' \"\$R22_000\" | grep -cx '__CALLS=3' >/dev/null"
# shellcheck disable=SC2034
R22_NQ="$(render_2_2 "$R22_REGION" live '500:NOTQ_BODY,500:NOTQ_BODY,500:NOTQ_BODY')"
assert "#6921 Guard3 row3: a FATAL body that merely MENTIONS QUIESCED mid-line -> UNKNOWN (anchored sentinel)" "r22_is \"\$R22_NQ\" unknown"
# shellcheck disable=SC2034
R22_MIX="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,503:QUIESCED_MULTI_BODY,500:QUIESCED_BODY')"
assert "#6921 Guard3 row7 (must-PASS non-canonical): 500/503 mix, different host_id, sentinel behind stderr noise -> PASSED" "r22_is \"\$R22_MIX\" passed"
# §9 — EVERY answered non-200 body must carry the sentinel; one sentinel is not a quorum.
# shellcheck disable=SC2034
R22_QFF="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,500:FATAL_BODY,500:FATAL_BODY')"
assert "#6921 §9 row: QUIESCED,FATAL,FATAL -> UNKNOWN (one sentinel does not certify two FATAL answers)" "r22_is \"\$R22_QFF\" unknown"
# shellcheck disable=SC2034
R22_Q0F="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,000:EMPTY_BODY,500:FATAL_BODY')"
assert "#6921 §9 row: QUIESCED,000,FATAL -> UNKNOWN (a 000 is skipped, the FATAL still counts)" "r22_is \"\$R22_Q0F\" unknown"
# shellcheck disable=SC2034
R22_00Q="$(render_2_2 "$R22_REGION" live '000:EMPTY_BODY,000:EMPTY_BODY,500:QUIESCED_BODY')"
assert "#6921 §9 row: 000,000,QUIESCED -> PASSED (000 is no answer; the one answered body carries the sentinel)" "r22_is \"\$R22_00Q\" passed"
# shellcheck disable=SC2034
R22_UA="$(render_2_2 "$R22_REGION" persisted '500:UNATTR_BODY,500:UNATTR_BODY,500:UNATTR_BODY')"
assert "#6921 §9 row: DISABLED_UNATTRIBUTED x3 -> UNKNOWN naming the op=rollback dispatch, and NOWHERE op=quiesce-web" \
  "r22_is \"\$R22_UA\" unknown && printf '%s\n' \"\$R22_UA\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -F 'DISABLED_UNATTRIBUTED' | grep -cF 'gh workflow run cutover-inngest.yml --field op=rollback' >/dev/null && ! printf '%s\n' \"\$R22_UA\" | grep -cF 'op=quiesce-web' >/dev/null"
# shellcheck disable=SC2034
R22_QUA="$(render_2_2 "$R22_REGION" live '500:QUIESCED_BODY,500:UNATTR_BODY,500:QUIESCED_BODY')"
assert "#6921 §9 row: QUIESCED,DISABLED_UNATTRIBUTED,QUIESCED -> UNKNOWN naming op=rollback (unattributed outranks the sentinel)" \
  "r22_is \"\$R22_QUA\" unknown && printf '%s\n' \"\$R22_QUA\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -cF 'op=rollback' >/dev/null"
# The remedy branches on the HTTP class BEFORE the 2.1 source: an answer the inventory script never
# produced says nothing about the unit, so it must not send the operator to quiesce-web OR to the
# config push.
# shellcheck disable=SC2034
R22_403="$(render_2_2 "$R22_REGION" live '403:FORBIDDEN_BODY,403:FORBIDDEN_BODY,403:FORBIDDEN_BODY')"
assert "#6921 §9 row: 403 x3 -> UNKNOWN naming CF-Access/HMAC, not op=quiesce-web, not the config push" \
  "r22_is \"\$R22_403\" unknown && printf '%s\n' \"\$R22_403\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -cF 'CF-Access' >/dev/null && ! printf '%s\n' \"\$R22_403\" | grep -cF 'op=quiesce-web' >/dev/null && ! printf '%s\n' \"\$R22_403\" | grep -cF 'predates the QUIESCED verdict' >/dev/null"
# shellcheck disable=SC2034
R22_404="$(render_2_2 "$R22_REGION" persisted '404:NOTFOUND_BODY,404:NOTFOUND_BODY,404:NOTFOUND_BODY')"
assert "#6921 §9 row: 404 x3 -> UNKNOWN naming the undeployed inngest-inventory hook, not the stale-script remedy" \
  "r22_is \"\$R22_404\" unknown && printf '%s\n' \"\$R22_404\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -cF 'hook is not deployed' >/dev/null && ! printf '%s\n' \"\$R22_404\" | grep -cF 'predates the QUIESCED verdict' >/dev/null"
# shellcheck disable=SC2034
R22_502="$(render_2_2 "$R22_REGION" live '502:GATEWAY_BODY,502:GATEWAY_BODY,502:GATEWAY_BODY')"
assert "#6921 §9 row: 502 x3 with no inngest-inventory: line -> UNKNOWN naming the gateway, not op=quiesce-web" \
  "r22_is \"\$R22_502\" unknown && printf '%s\n' \"\$R22_502\" | grep -E '^::error::2\.2 QUIESCE HARD GATE FAILED' | grep -cF 'gateway' >/dev/null && ! printf '%s\n' \"\$R22_502\" | grep -cF 'op=quiesce-web' >/dev/null"
# The UNKNOWN line carries what the host said: the first 120 chars of the last NON-EMPTY body, on ONE
# line. FATAL_BODY is CRLF-split and longer than 120 chars; its marker sits past char 120.
R22_EXCERPT_HEAD='ERROR: /v0/gql functions query failed'
assert "#6921 Guard3: the UNKNOWN line carries a CR/LF-stripped, 120-char excerpt of the last body" \
  "printf '%s\n' \"\$R22_FL\" | grep -E '^quiesce check .*UNKNOWN' | grep -cF '$R22_EXCERPT_HEAD' >/dev/null && ! printf '%s\n' \"\$R22_FL\" | grep -cF 'PAST_CHAR_120_MARKER' >/dev/null && ! printf '%s\n' \"\$R22_FL\" | grep -cE '^inngest-inventory: FATAL' >/dev/null && ! printf '%s\n' \"\$R22_FL\" | grep -c \$'\\r' >/dev/null"
# shellcheck disable=SC2034
R22_FF0="$(render_2_2 "$R22_REGION" live '500:FATAL_BODY,500:FATAL_BODY,000:EMPTY_BODY')"
assert "#6921 §9 excerpt: FATAL,FATAL,000 -> the excerpt is the last NON-EMPTY body (a trailing 000 does not hide the FATAL)" \
  "r22_is \"\$R22_FF0\" unknown && printf '%s\n' \"\$R22_FF0\" | grep -E '^quiesce check .*UNKNOWN' | grep -cF '$R22_EXCERPT_HEAD' >/dev/null"
assert "#6921 Guard3: the 2.2 gate still feeds the SEAM withhold through STILL_RUNNING / UNKNOWN_COUNT" \
  "ncl '$R22_REGION' | grep -cF 'if [[ \"\$STILL_RUNNING\" -gt 0 || \"\$UNKNOWN_COUNT\" -gt 0 ]]; then' >/dev/null && ncl '$R22_REGION' | grep -cE '^[[:space:]]*quiesced_n=0$' >/dev/null && ! ncl '$R22_REGION' | grep -cF 'reached_non200' >/dev/null && ! ncl '$R22_REGION' | grep -cF '\${SOURCE:-' >/dev/null"
# In-suite mutation rows (Guard 3 #1, #3, and the §9 every-body requirement) through mutate_file.
check_2_2_fatal_is_unknown() {
  local f="$1" region out
  region="$(mktemp)"; SCRATCH+=("$region")
  extract_2_2 "$f" > "$region"
  out="$(render_2_2 "$region" live '500:FATAL_BODY,500:FATAL_BODY,500:FATAL_BODY')"
  r22_is "$out" unknown
}
# shellcheck disable=SC2016  # a literal sed program matched against the script's source text
mutate_file "Guard3 #1 sentinel requirement dropped" "$BODY_SH" 's|^    elif \[\[ "\$answered_n" -ge 1 && "\$quiesced_n" -eq "\$answered_n" \]\]; then$|    elif [[ "$answered_n" -ge 1 ]]; then|' check_2_2_fatal_is_unknown
check_2_2_notq_is_unknown() {
  local f="$1" region out
  region="$(mktemp)"; SCRATCH+=("$region")
  extract_2_2 "$f" > "$region"
  out="$(render_2_2 "$region" live '500:NOTQ_BODY,500:NOTQ_BODY,500:NOTQ_BODY')"
  r22_is "$out" unknown
}
mutate_file "Guard3 #3 unanchored sentinel grep" "$BODY_SH" "s|^        elif grep -qE '\\^inngest-inventory: QUIESCED' /tmp/exec-inv 2>/dev/null; then\$|        elif grep -qE 'inngest-inventory: QUIESCED' /tmp/exec-inv 2>/dev/null; then|" check_2_2_notq_is_unknown
check_2_2_qff_is_unknown() {
  local f="$1" region out
  region="$(mktemp)"; SCRATCH+=("$region")
  extract_2_2 "$f" > "$region"
  out="$(render_2_2 "$region" live '500:QUIESCED_BODY,500:FATAL_BODY,500:FATAL_BODY')"
  r22_is "$out" unknown
}
# shellcheck disable=SC2016
mutate_file "§9 every-body requirement weakened to any-body" "$BODY_SH" 's|^    elif \[\[ "\$answered_n" -ge 1 && "\$quiesced_n" -eq "\$answered_n" \]\]; then$|    elif [[ "$answered_n" -ge 1 \&\& "$quiesced_n" -ge 1 ]]; then|' check_2_2_qff_is_unknown

# op=quiesce-web's secondary inventory confirm reports whether the sentinel was present.
QW_ARM_FILE="$(mktemp)"; SCRATCH+=("$QW_ARM_FILE")
awk '/^  quiesce-web\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$BODY_SH" > "$QW_ARM_FILE"
assert "#6921 quiesce-web secondary confirm greps the anchored sentinel and prints present/absent, with its own 000/unreadable branch" \
  "ncl '$QW_ARM_FILE' | grep -cF \"grep -qE '^inngest-inventory: QUIESCED' /tmp/quiesce-inv\" >/dev/null && ncl '$QW_ARM_FILE' | grep -cF 'QUIESCED sentinel=present' >/dev/null && ncl '$QW_ARM_FILE' | grep -cF 'QUIESCED sentinel=absent' >/dev/null && ncl '$QW_ARM_FILE' | grep -F 'echo \"::warning::quiesce-web: SECONDARY inventory confirm UNREADABLE' | grep -cF 'HTTP 000' >/dev/null"

# ── §9 quiesce-web PREFLIGHT: the config push landed BEFORE anything is stopped — RENDERED ────────
# The quiesce handler, the inventory QUIESCED verdict, the persisted-capture resume and the enumerate
# scrub all ship in ONE config push. A quiesce dispatched before that push lands stops production
# scheduling with a handler that cannot capture or certify it. So the arm reads /hooks/infra-config-status
# and compares the host's sha256 of each script against the checkout, and refuses before the fan-out POST.
QW_PF_NAMES="$(ncl "$QW_ARM_FILE" | sed -n 's/^[[:space:]]*for _pf_name in \(.*\); do$/\1/p')"
QW_PF_N="$(printf '%s\n' "$QW_PF_NAMES" | grep -c . || true)"
QW_PF_UNDELIVERED=""
for _pf in $QW_PF_NAMES; do
  grep -qF "|/usr/local/bin/$_pf|" "$REPO_ROOT/apps/web-platform/infra/infra-config-apply.sh" || QW_PF_UNDELIVERED+=" $_pf"
done
assert "#6921 §9 preflight list is the four cutover scripts, each a FILE_MAP-delivered /usr/local/bin dest (list='$QW_PF_NAMES' undelivered='${QW_PF_UNDELIVERED# }')" \
  "[[ '$QW_PF_N' -eq 1 && '$QW_PF_NAMES' == 'ci-deploy.sh inngest-inventory.sh inngest-rearm-reminders.sh inngest-enumerate-reminders.sh' && -z '$QW_PF_UNDELIVERED' ]]"
# shellcheck disable=SC2016  # literal source text, not expansions
QW_PF_STATUS_LN="$(ncl "$QW_ARM_FILE" | grep -nF '"$BASE/infra-config-status"' | sed -n '1p' | cut -d: -f1 || true)"
# shellcheck disable=SC2016
QW_PF_DEPLOY_LN="$(ncl "$QW_ARM_FILE" | grep -nF '"$BASE/deploy" ||' | sed -n '1p' | cut -d: -f1 || true)"
QW_PF_WARN_LN="$(ncl "$QW_ARM_FILE" | grep -nF 'echo "::warning::quiesce-web: this STOPS' | sed -n '1p' | cut -d: -f1 || true)"
assert "#6921 §9 the preflight read precedes the maintenance-window warning and the fan-out POST (status=$QW_PF_STATUS_LN warn=$QW_PF_WARN_LN deploy=$QW_PF_DEPLOY_LN)" \
  "[[ '$QW_PF_STATUS_LN' =~ ^[0-9]+\$ && '$QW_PF_WARN_LN' =~ ^[0-9]+\$ && '$QW_PF_DEPLOY_LN' =~ ^[0-9]+\$ ]] && (( QW_PF_STATUS_LN < QW_PF_WARN_LN && QW_PF_WARN_LN < QW_PF_DEPLOY_LN ))"
QW_PF_REGION="$(mktemp)"; SCRATCH+=("$QW_PF_REGION")
awk '/# ---- quiesce-web PREFLIGHT/{f=1} f&&/echo "::warning::quiesce-web: this STOPS/{exit} f' "$QW_ARM_FILE" > "$QW_PF_REGION"
QW_PF_REGION_N=$(grep -cv '^[[:space:]]*#' "$QW_PF_REGION" || true)
assert "#6921 §9 preflight region extraction is non-vacuous (>= 15 non-comment lines, got $QW_PF_REGION_N)" "[[ '$QW_PF_REGION_N' -ge 15 ]]"
# sha of each real checkout file, for building host frames that match or diverge.
declare -A QW_PF_SHA=()
for _pf in ci-deploy.sh inngest-inventory.sh inngest-rearm-reminders.sh inngest-enumerate-reminders.sh; do
  QW_PF_SHA[$_pf]="$(sha256sum "$REPO_ROOT/apps/web-platform/infra/$_pf" | awk '{print $1}')"
done
qw_pf_frame() { # $1 name to corrupt ('' none)  $2 corrupt mode: diverge|drop → a synthesized status frame
  local bad="$1" mode="$2" files="" n sha
  for n in ci-deploy.sh inngest-inventory.sh inngest-rearm-reminders.sh inngest-enumerate-reminders.sh; do
    sha="${QW_PF_SHA[$n]}"
    if [[ "$n" == "$bad" ]]; then
      [[ "$mode" == drop ]] && continue
      sha="$(printf '%s' "stub-$n" | sha256sum | awk '{print $1}')"
    fi
    files+="${files:+,}{\"file\":\"/usr/local/bin/$n\",\"sha256\":\"$sha\",\"status\":\"ok\",\"changed\":false}"
  done
  printf '{"schema_version":2,"start_ts":1,"end_ts":2,"exit_code":0,"files_written":4,"files_failed":0,"files_total":4,"files":[%s],"restarts":[]}' "$files"
}
render_qw_pf() { # $1 HTTP code  $2 body  $3 checkout file to REMOVE from the sandbox ('' none) → output, __RC=
  local code="$1" body="$2" rm_name="$3" tmpd root rc=0 n
  tmpd="$(mktemp -d)"; printf '%s\n' "$tmpd" >> "$RENDER_TMPDS"
  root="$tmpd/checkout"; mkdir -p "$root/apps/web-platform/infra"
  for n in ci-deploy.sh inngest-inventory.sh inngest-rearm-reminders.sh inngest-enumerate-reminders.sh; do
    [[ "$n" == "$rm_name" ]] || cp "$REPO_ROOT/apps/web-platform/infra/$n" "$root/apps/web-platform/infra/$n"
  done
  sed "s|/tmp/quiesce-preflight|$tmpd/quiesce-preflight|g" "$QW_PF_REGION" > "$tmpd/region.sh"
  {
    printf 'cd %q || exit 97\n' "$root"
    printf 'set -euo pipefail\n'
    printf 'BASE="https://stub.invalid"; WEBHOOK_SECRET="stub"; CF_ACCESS_CLIENT_ID="stub"; CF_ACCESS_CLIENT_SECRET="stub"\n'
    printf 'STUB_CODE=%q; STUB_BODY=%q; TMPD=%q\n' "$code" "$body" "$tmpd"
    cat <<'DRIVER'
curl() {
  local o="" a
  for a in "$@"; do [[ "$a" == */deploy ]] && touch "$TMPD/DEPLOY_POSTED"; done
  while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && o="$2"; shift; done
  if [[ "$STUB_CODE" == "000" ]]; then printf '000'; return 28; fi
  printf '%s' "$STUB_BODY" > "$o"
  printf '%s' "$STUB_CODE"
}
DRIVER
    printf 'source %q\n' "$tmpd/region.sh"
    printf 'echo "__PREFLIGHT_PASSED__"\n'
  } > "$tmpd/driver.sh"
  bash "$tmpd/driver.sh" 2>&1 || rc=$?
  echo "__RC=$rc"
  [[ -e "$tmpd/DEPLOY_POSTED" ]] && echo "__DEPLOY_POSTED__"
  return 0
}
qw_pf_refused() { # <output> <needle> — rc 1, one ::error:: naming the needle, never passed, never POSTed
  printf '%s\n' "$1" | grep -cx '__RC=1' >/dev/null && printf '%s\n' "$1" | grep -E '^::error::quiesce-web PREFLIGHT: config push not landed' | grep -cF -- >/dev/null "$2" \
    && ! printf '%s\n' "$1" | grep -cE '__PREFLIGHT_PASSED__|__DEPLOY_POSTED__' >/dev/null
}
# shellcheck disable=SC2034  # read inside assert's eval'd condition strings
QW_PF_OK="$(render_qw_pf 200 "$(qw_pf_frame '' '')" '')"
assert "#6921 §9 preflight: all four host sha256 == checkout -> passes (rc 0, no ::error::)" \
  "printf '%s\n' \"\$QW_PF_OK\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$QW_PF_OK\" | grep -cx '__PREFLIGHT_PASSED__' >/dev/null && ! printf '%s\n' \"\$QW_PF_OK\" | grep -c '^::error::' >/dev/null"
# shellcheck disable=SC2034
QW_PF_DIV="$(render_qw_pf 200 "$(qw_pf_frame inngest-inventory.sh diverge)" '')"
assert "#6921 §9 preflight: a diverging inngest-inventory.sh -> refuses naming host=<sha> checkout=<sha>, plus the apply-deploy-pipeline-fix.yml remedy" \
  "qw_pf_refused \"\$QW_PF_DIV\" '/usr/local/bin/inngest-inventory.sh host=$(printf '%s' stub-inngest-inventory.sh | sha256sum | awk '{print $1}') checkout=${QW_PF_SHA[inngest-inventory.sh]}' && printf '%s\n' \"\$QW_PF_DIV\" | grep -cF 'apply-deploy-pipeline-fix.yml' >/dev/null"
# shellcheck disable=SC2034
QW_PF_DROP="$(render_qw_pf 200 "$(qw_pf_frame inngest-enumerate-reminders.sh drop)" '')"
assert "#6921 §9 preflight: inngest-enumerate-reminders.sh absent from files[] -> refuses with host=missing" \
  "qw_pf_refused \"\$QW_PF_DROP\" '/usr/local/bin/inngest-enumerate-reminders.sh host=missing checkout=${QW_PF_SHA[inngest-enumerate-reminders.sh]}'"
# shellcheck disable=SC2034
QW_PF_403="$(render_qw_pf 403 'Hook rules were not satisfied.' '')"
assert "#6921 §9 preflight: an unreadable status (HTTP 403) refuses — fail-closed, never a skipped check" \
  "qw_pf_refused \"\$QW_PF_403\" 'HTTP 403'"
# shellcheck disable=SC2034
QW_PF_000="$(render_qw_pf 000 '' '')"
assert "#6921 §9 preflight: a transport failure (000) refuses" "qw_pf_refused \"\$QW_PF_000\" 'HTTP 000'"
# shellcheck disable=SC2034
QW_PF_NJ="$(render_qw_pf 200 '{"exit_code":-2,"reason":"no_prior_apply"}' '')"
assert "#6921 §9 preflight: a 200 frame with no files[] (no_prior_apply) refuses" "qw_pf_refused \"\$QW_PF_NJ\" 'no files[]'"
# shellcheck disable=SC2034
QW_PF_NOCO="$(render_qw_pf 200 "$(qw_pf_frame '' '')" ci-deploy.sh)"
assert "#6921 §9 preflight: an unreadable checkout file refuses with checkout=unreadable (never compares against an empty sha)" \
  "qw_pf_refused \"\$QW_PF_NOCO\" '/usr/local/bin/ci-deploy.sh host=${QW_PF_SHA[ci-deploy.sh]} checkout=unreadable'"
check_qw_pf_divergence_refuses() {
  local f="$1" arm region out
  arm="$(mktemp)"; region="$(mktemp)"; SCRATCH+=("$arm" "$region")
  awk '/^  quiesce-web\)$/{f=1;next} f&&/^  [a-z-]+\)$/{exit} f' "$f" > "$arm"
  awk '/# ---- quiesce-web PREFLIGHT/{f=1} f&&/echo "::warning::quiesce-web: this STOPS/{exit} f' "$arm" > "$region"
  out="$(QW_PF_REGION="$region" render_qw_pf 200 "$(qw_pf_frame inngest-inventory.sh diverge)" '')"
  printf '%s\n' "$out" | grep -cx '__RC=1' >/dev/null && ! printf '%s\n' "$out" | grep -cx '__PREFLIGHT_PASSED__' >/dev/null
}
# shellcheck disable=SC2016
mutate_file "§9 preflight refusal neutered" "$BODY_SH" 's|^    if \[\[ "\$PF_FAIL" -ne 0 \]\]; then$|    if false; then|' check_qw_pf_divergence_refuses

# ── §9 quiesce-web POLLER: lock_contention is not terminal; each quiesce failure has its own remedy ─
# RENDERED: the poll loop (TRIGGER_TS .. the SECONDARY confirm) runs with curl answering a per-call
# `reason:exit_code` sequence and sleep stubbed out. A lock_contention loser (a watchdog restart racing
# the quiesce's flock) overwrites the single deploy-status slot; the winner's verdict lands after it.
QW_POLL_REGION="$(mktemp)"; SCRATCH+=("$QW_POLL_REGION")
awk '/^    TRIGGER_TS=\$\(date \+%s\)$/{f=1} f&&/# SECONDARY confirm/{exit} f' "$QW_ARM_FILE" > "$QW_POLL_REGION"
QW_POLL_N=$(grep -cv '^[[:space:]]*#' "$QW_POLL_REGION" || true)
assert "#6921 §9 poll region extraction is non-vacuous (>= 30 non-comment lines, got $QW_POLL_N)" "[[ '$QW_POLL_N' -ge 30 ]]"
render_qw_poll() { # $1 QSEQ `reason:exit,…` → output, __RC=, __CALLS=
  local seq="$1" tmpd rc=0
  tmpd="$(mktemp -d)"; printf '%s\n' "$tmpd" >> "$RENDER_TMPDS"
  sed "s|/tmp/quiesce-status|$tmpd/quiesce-status|g" "$QW_POLL_REGION" > "$tmpd/region.sh"
  {
    printf 'set -euo pipefail\n'
    printf 'BASE="https://stub.invalid"; WEBHOOK_SECRET="stub"; CF_ACCESS_CLIENT_ID="stub"; CF_ACCESS_CLIENT_SECRET="stub"\n'
    printf 'QSEQ=%q; TMPD=%q\n' "$seq" "$tmpd"
    cat <<'DRIVER'
sleep() { :; }
curl() {
  local o="" n entry
  while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && o="$2"; shift; done
  n=$(( $(cat "$TMPD/curl.count" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$TMPD/curl.count"
  IFS=',' read -r -a _seq <<< "$QSEQ"
  entry="${_seq[$((n - 1))]:-}"
  [[ -n "$entry" ]] || return 7
  printf '{"start_ts":9999999999,"end_ts":9999999999,"exit_code":%s,"component":"inngest","image":"","tag":"","reason":"%s"}' "${entry#*:}" "${entry%%:*}" > "$o"
  printf '200'
}
DRIVER
    printf 'source %q\n' "$tmpd/region.sh"
    printf 'echo "__POLL_FELL_THROUGH__"\n'
  } > "$tmpd/driver.sh"
  bash "$tmpd/driver.sh" 2>&1 || rc=$?
  echo "__RC=$rc"
  echo "__CALLS=$(cat "$tmpd/curl.count" 2>/dev/null || echo 0)"
  return 0
}
qw_poll_failed() { # <output> <calls> <needle>… — rc 1, stopped at call <calls>, the ::error:: carries every needle
  local out="$1" calls="$2" line; shift 2
  printf '%s\n' "$out" | grep -cx '__RC=1' >/dev/null && printf '%s\n' "$out" | grep -cx "__CALLS=$calls" >/dev/null && ! printf '%s\n' "$out" | grep -cx '__POLL_FELL_THROUGH__' >/dev/null || return 1
  line="$(printf '%s\n' "$out" | grep -E '^::error::' | sed -n '1p' || true)"
  while [[ $# -gt 0 ]]; do printf '%s' "$line" | grep -cF -- >/dev/null "$1" || return 1; shift; done
}
# shellcheck disable=SC2034
QW_POLL_LC="$(render_qw_poll 'running:-1,lock_contention:1,quiesced:0')"
assert "#6921 §9 poller: running, lock_contention, quiesced -> keeps polling past lock_contention and confirms (rc 0, calls=3)" \
  "printf '%s\n' \"\$QW_POLL_LC\" | grep -cx '__RC=0' >/dev/null && printf '%s\n' \"\$QW_POLL_LC\" | grep -cx '__CALLS=3' >/dev/null && printf '%s\n' \"\$QW_POLL_LC\" | grep -cx '__POLL_FELL_THROUGH__' >/dev/null && printf '%s\n' \"\$QW_POLL_LC\" | grep -cE '^::notice::quiesce-web: host-side QUIESCED confirmed' >/dev/null"
# shellcheck disable=SC2034
QW_POLL_LCT="$(render_qw_poll 'lock_contention:1')"
assert "#6921 §9 poller: lock_contention to the end -> the timeout error names lock_contention as the last reason (rc 1)" \
  "printf '%s\n' \"\$QW_POLL_LCT\" | grep -cx '__RC=1' >/dev/null && printf '%s\n' \"\$QW_POLL_LCT\" | grep -E '^::error::quiesce-web did not reach' | grep -cF 'lock_contention' >/dev/null"
# shellcheck disable=SC2034
QW_POLL_CF="$(render_qw_poll 'quiesce_capture_failed:1')"
assert "#6921 §9 poller: quiesce_capture_failed -> fails fast naming the Better Stack read, restart-inngest-server.yml and the re-dispatch" \
  "qw_poll_failed \"\$QW_POLL_CF\" 1 'reason=quiesce_capture_failed' 'doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 1h --grep INNGEST_QUIESCE_CAPTURE_FAILED' 'restart-inngest-server.yml' 'op=quiesce-web' 'NOTHING was stopped'"
# shellcheck disable=SC2034
QW_POLL_CU="$(render_qw_poll 'quiesce_capture_unavailable:1')"
assert "#6921 §9 poller: quiesce_capture_unavailable -> fails fast naming restart-inngest-server.yml, op=rollback (disabled_unattributed) and the re-quiesce" \
  "qw_poll_failed \"\$QW_POLL_CU\" 1 'reason=quiesce_capture_unavailable' 'INNGEST_QUIESCE_CAPTURE_UNAVAILABLE' 'restart-inngest-server.yml' 'op=rollback' 'disabled_unattributed' 'op=quiesce-web'"
# shellcheck disable=SC2034
QW_POLL_MW="$(render_qw_poll 'quiesce_marker_write_failed:1')"
assert "#6921 §9 poller: quiesce_marker_write_failed -> fails fast naming /var/lib/inngest and the re-dispatch" \
  "qw_poll_failed \"\$QW_POLL_MW\" 1 'reason=quiesce_marker_write_failed' '/var/lib/inngest' 'INNGEST_QUIESCE_MARKER_WRITE_FAILED' 'op=quiesce-web'"
# shellcheck disable=SC2034
QW_POLL_SU="$(render_qw_poll 'quiesced_shape_unrecognized:1')"
assert "#6921 §9 poller: quiesced_shape_unrecognized -> fails fast, says scheduling IS stopped, names op=rollback then op=quiesce-web" \
  "qw_poll_failed \"\$QW_POLL_SU\" 1 'reason=quiesced_shape_unrecognized' 'production scheduling IS stopped' 'op=rollback' 'op=quiesce-web'"
# shellcheck disable=SC2034
QW_POLL_UN="$(render_qw_poll 'bogus_reason:1')"
assert "#6921 §9 poller: an unenumerated terminal reason still fails fast (calls=1)" \
  "qw_poll_failed \"\$QW_POLL_UN\" 1 'unrecognized terminal reason bogus_reason'"

# ── D5 (FR10): the operator text states the measured state — WHOLE FILE, comments included ──────
# web-2 (10.0.1.11) is a scheduler-less cattle standby born with web_colocate_inngest=false; the loop
# is drivable; the watchdog leaves a quiesced unit alone. The old premises must be gone everywhere,
# including comments — a comment contradicting the notice beneath it is the next maintainer's trap.
for _stale in 'KNOWN GAP (#6921)' 'web-2 freeze/recreate' 'self-arms oneshots'; do
  _n=$(grep -cF -- "$_stale" "$BODY_SH" || true)
  assert "#6921 FR10 whole-file: '$_stale' is gone (got $_n)" "[[ '$_n' -eq 0 ]]"
done
_n=$(grep -cE 'auto-restart the web scheduler|currently fails at 2\.1' "$BODY_SH" || true)
assert "#6921 FR10 whole-file: 'auto-restart the web scheduler|currently fails at 2.1' is gone (got $_n)" "[[ '$_n' -eq 0 ]]"
# echo_has <file> <echo-prefix> <phrase> — a NON-COMMENT echo line starting with the prefix carries the phrase.
echo_has() { ncl "$1" | grep -F -- "echo \"$2" | grep -cF -- >/dev/null "$3"; }
assert "#6921 D5 2.2 STILL RUNNING warning: a second op=execute resumes 2.1 from the persisted capture, and the watchdog leaves a quiesced unit alone" \
  "echo_has '$EXEC_ARM_FILE' '::warning::2.2:' 'a second op=execute resumes 2.1 from the persisted capture taken at the quiesce boundary' && echo_has '$EXEC_ARM_FILE' '::warning::2.2:' 'leaves a quiesced unit alone'"
assert "#6921 D5 quiesce-web warning: capture-before-stop resume + the watchdog leaves a quiesced unit alone" \
  "echo_has '$QW_ARM_FILE' '::warning::quiesce-web:' 'a second op=execute resumes 2.1 from the persisted capture taken at the quiesce boundary' && echo_has '$QW_ARM_FILE' '::warning::quiesce-web:' 'leaves a quiesced unit alone'"
assert "#6921 D5 SEAM 2.2a: the ONE authoritative web-2 statement — scheduler-less cattle standby, the fan-outs tolerated (not no-ops: rollback's enable fails on web-2's own unread slot), no freeze or recreate step" \
  "echo_has '$EXEC_ARM_FILE' '  2.2a WEB-2' 'web-2 (10.0.1.11) is a scheduler-less cattle standby born with web_colocate_inngest=false' && echo_has '$EXEC_ARM_FILE' '  2.2a WEB-2' 'tolerated, not no-ops' && echo_has '$EXEC_ARM_FILE' '  2.2a WEB-2' \"reports inngest_enable_failed on web-2's OWN deploy-status slot, which CI does not read\" && echo_has '$EXEC_ARM_FILE' '  2.2a WEB-2' 'no web-2 freeze or recreate step'"
# ONE statement: the full premise appears exactly once in the whole file (comments included); every other
# site points at SEAM 2.2a instead of restating (and drifting from) it.
_n=$(grep -cF 'scheduler-less cattle standby born with web_colocate_inngest=false' "$BODY_SH" || true)
assert "#6921 D5 whole-file: the web-2 premise is stated exactly once (SEAM 2.2a) (got $_n)" "[[ '$_n' -eq 1 ]]"
_n=$(grep -cE 'tolerated no-op|no-op on an absent unit' "$BODY_SH" || true)
assert "#6921 D5 whole-file: no web-2 fan-out is called a no-op (got $_n)" "[[ '$_n' -eq 0 ]]"
assert "#6921 D5 2.2 PASSED notice names the QUIESCED shape and points web-2 scope at SEAM 2.2a" \
  "echo_has '$EXEC_ARM_FILE' '::notice::2.2 QUIESCE HARD GATE PASSED' 'QUIESCED unit shape' && echo_has '$EXEC_ARM_FILE' '::notice::2.2 QUIESCE HARD GATE PASSED' 'SEAM 2.2a'"
assert "#6921 D5 quiesce-web completion notice: web-2 scope points at SEAM 2.2a, 2.1 resumes" \
  "echo_has '$QW_ARM_FILE' '::notice::quiesce-web complete' 'SEAM 2.2a' && echo_has '$QW_ARM_FILE' '::notice::quiesce-web complete' '2.1 resumes from the persisted capture'"
_n=$(ncl "$BODY_SH" | grep -F 'SCOPE CAVEAT (P2-a / DI-C3)' | grep -F 'NOT a web-host double-fire detector' | grep -cF 'SEAM 2.2a' || true)
assert "#6921 D5 both doublefire scope caveats (doublefire-probe + verify 2.6) name the web host and point web-2 at SEAM 2.2a (got $_n)" "[[ '$_n' -eq 2 ]]"
assert "#6921 D5 the quiesce-web #6178 poll-window comment includes the 120 s capture bound and the peer fan-out term, drift-guarded" \
  "grep -B7 -E '^[[:space:]]*QMAX_POLLS=[0-9]+$' '$QW_ARM_FILE' | grep -E '^[[:space:]]*#' | grep -cF '120 s quiesce capture bound' >/dev/null && grep -B7 -E '^[[:space:]]*QMAX_POLLS=[0-9]+$' '$QW_ARM_FILE' | grep -E '^[[:space:]]*#' | grep -cF 'peer fan-out' >/dev/null && grep -B7 -E '^[[:space:]]*QMAX_POLLS=[0-9]+$' '$QW_ARM_FILE' | grep -E '^[[:space:]]*#' | grep -cF 'drift-guarded by ci-deploy.test.sh' >/dev/null"
# The deploy. tunnel ingress is web-1-only (tunnel.tf pins the origin to web_hosts["web-1"]): there is no
# load balancer in front of these hooks, so no text may say there is.
_n=$(grep -cE 'LB-routed|LB-reachable|LB-scoped|LOAD BALANCER|the LB may' "$BODY_SH" || true)
assert "#6921 D5 whole-file: no 'LB-routed / LB-reachable / LOAD BALANCER' wording (the deploy. ingress is web-1-only) (got $_n)" "[[ '$_n' -eq 0 ]]"
assert "#6921 D5 the tunnel fact the wording rests on still holds: tunnel.tf pins deploy. to web-1" \
  "grep -A2 -F 'hostname = \"deploy.\${var.app_domain_base}\"' '$REPO_ROOT/apps/web-platform/infra/tunnel.tf' | grep -cF 'var.web_hosts[\"web-1\"].private_ip' >/dev/null"

# =====================================================================================
# #6939 — op=verify missed-tick candidates: OFF by default, never command-shaped.
#
# The old block printed `soleur:trigger-cron` with two flags the skill does not accept, one line
# per empty (function, bucket) pair — including buckets a slower cron was never due in, so acting
# on the list double-fired the cron. It now lives in missed_tick_report(), gated on the
# missed_tick_candidates dispatch input (default false). These rows EXECUTE the extracted function.
# =====================================================================================
echo "--- #6939 missed-tick candidates (opt-in, never a re-fire list) ---"

# Guard 1 — no nonexistent trigger-cron flag at ANY emission site. Greps the REAL files, not $WF
# ($WF drops the script preamble above `set -euo pipefail`). `-e` per pattern: a bare
# `grep -E '--function-id|…'` is parsed as an option, exits 2, and `|| true` then yields '' — so
# the compare is an exact string '0', never `-eq` (which '' would satisfy).
MTR_ANCHOR_FN=$(grep -cx 'missed_tick_report() {' "$BODY_SH" || true)
MTR_ANCHOR_ARM=$(grep -cx '  verify)' "$BODY_SH" || true)
assert "#6939 guard-1 precondition: the script carries the column-0 definition and the verify) label (fn=$MTR_ANCHOR_FN arm=$MTR_ANCHOR_ARM)" "[[ '$MTR_ANCHOR_FN' == '1' && '$MTR_ANCHOR_ARM' == '1' ]]"
for _mtr_f in "$BODY_SH" "$WF_YAML"; do
  _mtr_n=$(grep -vE '^[[:space:]]*#' "$_mtr_f" | grep -c -e '--function-id' -e '--missed-tick' || true)
  assert "#6939 no non-comment --function-id / --missed-tick in $(basename "$_mtr_f") (got '$_mtr_n')" "[[ '$_mtr_n' == '0' ]]"
done

# Workflow shape: a boolean input defaulting to false, mapped into env exactly once. The awk is
# scoped to the input's own block: an unscoped grep is satisfied by any other boolean input.
# shellcheck disable=SC2034  # read inside assert's eval
MTR_INPUT_BLOCK=$(awk '/^      missed_tick_candidates:$/{f=1;next} f&&/^      [a-z_]+:$/{exit} f&&/^  [^ ]/{exit} f' "$WF_YAML")
assert "#6939 input missed_tick_candidates is type: boolean" "grep -qE '^[[:space:]]+type:[[:space:]]*boolean\$' <<<\"\$MTR_INPUT_BLOCK\""
assert "#6939 input missed_tick_candidates defaults to false" "grep -qE '^[[:space:]]+default:[[:space:]]*false\$' <<<\"\$MTR_INPUT_BLOCK\""
MTR_MAP_N=$(grep -cE '^[[:space:]]+CUTOVER_MISSED_TICK_CANDIDATES: \$\{\{ inputs\.missed_tick_candidates \}\}$' "$WF_YAML" || true)
assert "#6939 step env maps CUTOVER_MISSED_TICK_CANDIDATES from the input (got '$MTR_MAP_N')" "[[ '$MTR_MAP_N' == '1' ]]"
MTR_REFS=$(grep -cE '\$\{\{[[:space:]]*inputs\.missed_tick_candidates' "$WF_YAML" || true)
assert "#6939 exactly one \${{ inputs.missed_tick_candidates reference (env only, never run:) (got '$MTR_REFS')" "[[ '$MTR_REFS' == '1' ]]"

# Call site: one exact plain line. A default (:-true) or a trailing `|| exit 1` (which disables
# set -e inside the function) both fail the whole-line match.
MTR_CALL='    missed_tick_report "${CUTOVER_MISSED_TICK_CANDIDATES:-}" "$BODY" "$CRON_PERIOD" "${CUTOVER_WINDOW_FROM:-}" "${CUTOVER_WINDOW_UNTIL:-}"'
MTR_CALL_N=$(grep -cxF -- "$MTR_CALL" "$BODY_SH" || true)
assert "#6939 the call site is the one exact plain line (got '$MTR_CALL_N')" "[[ '$MTR_CALL_N' == '1' ]]"
MTR_CALL_CT=$(grep -cF 'missed_tick_report' "$VERIFY_ARM_FILE" || true)
MTR_CALL_LN=$(grep -nF 'missed_tick_report' "$VERIFY_ARM_FILE" | tail -1 | cut -d: -f1 || true)
MTR_VERDICT_LN=$(grep -nF 'exactly-once VERIFIED' "$VERIFY_ARM_FILE" | tail -1 | cut -d: -f1 || true)
assert "#6939 verify) calls missed_tick_report exactly once (got '$MTR_CALL_CT')" "[[ '$MTR_CALL_CT' == '1' ]]"
assert "#6939 the call sits after the LAST exactly-once VERIFIED echo (call=$MTR_CALL_LN verdict=$MTR_VERDICT_LN)" "[[ -n '$MTR_CALL_LN' && -n '$MTR_VERDICT_LN' && '$MTR_CALL_LN' -gt '$MTR_VERDICT_LN' ]]"
MTR_ARM_LOOP=$(grep -cE 'for fn in|candidate function_id=' "$VERIFY_ARM_FILE" || true)
assert "#6939 verify) has no per-function loop of its own (got '$MTR_ARM_LOOP')" "[[ '$MTR_ARM_LOOP' == '0' ]]"

# Behavioural cases against the EXTRACTED function (column 0 of $BODY_SH; in $WF it is re-indented).
MTR_FN="$(mktemp)"; SCRATCH+=("$MTR_FN")
MTR_OUT="$(mktemp)"; SCRATCH+=("$MTR_OUT")
MTR_CWD="$(mktemp -d)"; SCRATCH+=("$MTR_CWD")
: > "$MTR_CWD/mtr-glob-sentinel"   # an id of `*` that reached a shell glob would print this name
awk '/^missed_tick_report\(\) \{$/,/^\}$/' "$BODY_SH" > "$MTR_FN"
assert "#6939 missed_tick_report() extraction is non-empty and carries its definition" "[[ -s '$MTR_FN' ]] && grep -qx 'missed_tick_report() {' '$MTR_FN'"
MTR_CASES=0
# Runs one case. NEVER call this inside if/||/&&: bash disables set -e for the whole compound,
# including a subshell that re-sets it, so a function whose own errexit is broken would pass.
mtr_run() {  # $1 gate  $2 body-json  $3 win-from  $4 win-until  -> $MTR_OUT, $MTR_RC
  MTR_CASES=$((MTR_CASES + 1))
  set +e
  # shellcheck source=/dev/null  # the extracted missed_tick_report() body
  ( cd "$MTR_CWD"; set -euo pipefail; source "$MTR_FN"; missed_tick_report "$1" "$2" 3600 "$3" "$4" ) > "$MTR_OUT" 2>&1
  MTR_RC=$?
  set -e
}
mtr_cands() { grep -cE '^  candidate ' "$MTR_OUT" || true; }

# Canonical fixture: fn-h (hourly) has no run in the 12:00 bucket; fn-d (daily) ran at 00:00, so
# every window bucket is empty for it — the never-due class this change labels. The window covers
# buckets 11, 12 and 13, so ON prints exactly 4 lines. The count comes from the fixture.
MTR_FIXTURE='{"runs":[
  {"functionID":"fn-h","startedAt":"2026-07-08T10:00:05Z"},
  {"functionID":"fn-h","startedAt":"2026-07-08T11:00:03.2Z"},
  {"functionID":"fn-h","startedAt":"2026-07-08T13:00:01Z"},
  {"functionID":"fn-d","startedAt":"2026-07-08T00:00:02Z"}]}'
# The canonical fixture plus fn-q, whose only run has not started. The function set is still
# `[.runs[].functionID] | unique`, so fn-q contributes 3 more (7). #6940's item 5 (due-tick
# filtering) is EXPECTED to change this count — that is not a regression.
MTR_NULL_FIXTURE='{"runs":[
  {"functionID":"fn-h","startedAt":"2026-07-08T10:00:05Z"},
  {"functionID":"fn-h","startedAt":"2026-07-08T11:00:03.2Z"},
  {"functionID":"fn-h","startedAt":"2026-07-08T13:00:01Z"},
  {"functionID":"fn-d","startedAt":"2026-07-08T00:00:02Z"},
  {"functionID":"fn-q","startedAt":null}]}'
MTR_FULL_FIXTURE='{"runs":[
  {"functionID":"fn-h","startedAt":"2026-07-08T11:00:05Z"},
  {"functionID":"fn-h","startedAt":"2026-07-08T12:00:03.2Z"},
  {"functionID":"fn-h","startedAt":"2026-07-08T13:00:01Z"}]}'
MTR_FROM="2026-07-08T11:30:00Z"
MTR_UNTIL="2026-07-08T13:30:00Z"

# OFF: every gate value that is not exactly `true`. `TRUE`, `1` and `true ` kill a loose gate
# (`== true*`, `-n && != false`) that `""`/`false` alone would let survive.
MTR_OFF_GATES=("" "false" "TRUE" "1" "true ")
for _mtr_g in "${MTR_OFF_GATES[@]}"; do
  mtr_run "$_mtr_g" "$MTR_FIXTURE" "$MTR_FROM" "$MTR_UNTIL"
  _mtr_rc=$MTR_RC
  _mtr_leak=$(grep -cE 'candidate function_id=|fn-h|fn-d|--function-id|--missed-tick' "$MTR_OUT" || true)
  _mtr_ptr=$(grep -cF 'missed-tick candidates NOT EMITTED' "$MTR_OUT" || true)
  _mtr_q=$( { grep -F 'missed-tick candidates NOT EMITTED' "$MTR_OUT" || true; } | tr -cd "'\"" | wc -c | tr -d '[:space:]')
  assert "#6939 OFF gate=[$_mtr_g]: rc is exactly 0 (got $_mtr_rc)" "[[ '$_mtr_rc' == '0' ]]"
  assert "#6939 OFF gate=[$_mtr_g]: no candidate line, fixture id or forbidden flag (got $_mtr_leak)" "[[ '$_mtr_leak' == '0' ]]"
  assert "#6939 OFF gate=[$_mtr_g]: exactly one pointer, with no quote or apostrophe (ptr=$_mtr_ptr quotes=$_mtr_q)" "[[ '$_mtr_ptr' == '1' && '$_mtr_q' == '0' ]]"
  assert "#6939 OFF gate=[$_mtr_g]: pointer names the runbook section and echoes the window" "grep -qF 'knowledge-base/engineering/operations/runbooks/inngest-server.md' '$MTR_OUT' && grep -qF 'Bounded-outage note' '$MTR_OUT' && grep -qF '[$MTR_FROM, $MTR_UNTIL]' '$MTR_OUT'"
done

# OFF never parses the window: a malformed one cannot redden a clean verdict run.
mtr_run "" "$MTR_FIXTURE" "garbage" "$MTR_UNTIL"
assert "#6939 OFF with window-from=garbage: rc 0, printed as <invalid>, pointer present (rc=$MTR_RC)" "[[ '$MTR_RC' == '0' ]] && grep -qF '[<invalid>, $MTR_UNTIL]' '$MTR_OUT' && grep -qF 'NOT EMITTED' '$MTR_OUT'"

# ON, canonical: the exact sorted candidate set, the footer, and nothing command-shaped. A count
# plus a regex would survive an off-by-one bucket range or a bucket-END timestamp.
mtr_run true "$MTR_FIXTURE" "$MTR_FROM" "$MTR_UNTIL"
_mtr_rc=$MTR_RC
MTR_SET=$(grep -E '^  candidate ' "$MTR_OUT" | sed -E 's/^  candidate function_id=([^ ]+) empty_bucket_start=2026-07-08T([0-9]{2}:[0-9]{2}):00Z$/\1@\2/' | LC_ALL=C sort | paste -sd, - || true)
MTR_SHAPE_BAD=$( { grep -E '^  candidate ' "$MTR_OUT" || true; } | grep -cvE '^  candidate function_id=[^ ]+ empty_bucket_start=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || true)
MTR_CMDISH=$( { grep -E '^  candidate ' "$MTR_OUT" || true; } | grep -cE 'soleur:|--' || true)
assert "#6939 ON canonical: rc is exactly 0 (got $_mtr_rc)" "[[ '$_mtr_rc' == '0' ]]"
assert "#6939 ON canonical: UNVERIFIED warning header that says NOT a re-fire list" "grep -qE '^::warning::.*UNVERIFIED' '$MTR_OUT' && grep -qF 'NOT a re-fire list' '$MTR_OUT'"
assert "#6939 ON canonical: exact candidate set (got '$MTR_SET')" "[[ '$MTR_SET' == 'fn-d@11:00,fn-d@12:00,fn-d@13:00,fn-h@12:00' ]]"
assert "#6939 ON canonical: every candidate line has the labelled shape (bad=$MTR_SHAPE_BAD)" "[[ '$MTR_SHAPE_BAD' == '0' ]]"
assert "#6939 ON canonical: no candidate line carries soleur: or -- (got $MTR_CMDISH)" "[[ '$MTR_CMDISH' == '0' ]]"
assert "#6939 ON canonical: the footer counts 4" "grep -qE '^::notice::missed-tick candidates: 4 unverified' '$MTR_OUT'"

# ON, null startedAt: no jq exit 5, and exactly 7 (see the fixture comment for why 7).
mtr_run true "$MTR_NULL_FIXTURE" "$MTR_FROM" "$MTR_UNTIL"
_mtr_rc=$MTR_RC; _mtr_n=$(mtr_cands)
assert "#6939 ON null-startedAt: rc exactly 0 and exactly 7 candidates (rc=$_mtr_rc n=$_mtr_n)" "[[ '$_mtr_rc' == '0' && '$_mtr_n' == '7' ]]"

# ON, full coverage (must-PASS, non-canonical): the guard does not reject everything.
mtr_run true "$MTR_FULL_FIXTURE" "$MTR_FROM" "$MTR_UNTIL"
_mtr_rc=$MTR_RC; _mtr_n=$(mtr_cands)
assert "#6939 ON full coverage: rc 0, zero candidates, footer counts 0 (rc=$_mtr_rc n=$_mtr_n)" "[[ '$_mtr_rc' == '0' && '$_mtr_n' == '0' ]] && grep -qE '^::notice::missed-tick candidates: 0 unverified' '$MTR_OUT'"

# ON, invalid windows: reversed, non-ISO (date -d would accept `tomorrow`), and over 10000 buckets.
# Only the opt-in list fails; the message must say the verdict above STANDS.
MTR_BAD_WINDOWS=("$MTR_UNTIL|$MTR_FROM|reversed" "tomorrow|$MTR_UNTIL|non-ISO" "2020-01-01T00:00:00Z|$MTR_UNTIL|over-10000-buckets")
for _mtr_w in "${MTR_BAD_WINDOWS[@]}"; do
  IFS='|' read -r _mtr_wf _mtr_wu _mtr_wn <<<"$_mtr_w"
  mtr_run true "$MTR_FIXTURE" "$_mtr_wf" "$_mtr_wu"
  _mtr_rc=$MTR_RC; _mtr_n=$(mtr_cands)
  assert "#6939 ON invalid window ($_mtr_wn): rc exactly 1, verdict above STANDS, no candidates (rc=$_mtr_rc n=$_mtr_n)" "[[ '$_mtr_rc' == '1' && '$_mtr_n' == '0' ]] && grep -qE '^::error::.*verdict above STANDS' '$MTR_OUT'"
done

# ON, window not supplied: a warning, rc 0.
mtr_run true "$MTR_FIXTURE" "" "$MTR_UNTIL"
_mtr_rc=$MTR_RC; _mtr_n=$(mtr_cands)
assert "#6939 ON with one window bound empty: warning, rc 0, no candidates (rc=$_mtr_rc n=$_mtr_n)" "[[ '$_mtr_rc' == '0' && '$_mtr_n' == '0' ]] && grep -qE '^::warning::' '$MTR_OUT'"

# P7 — no operator- or host-supplied value can forge an annotation line. GitHub decodes %0A inside
# an annotation, so a CR/LF strip is not enough: window values are validated, not sanitised.
MTR_FORGE=($'x\n::notice::FORGED' $'y\r::notice::FORGED' '%0A::notice::FORGED')
for _mtr_v in "${MTR_FORGE[@]}"; do
  mtr_run false "$MTR_FIXTURE" "$_mtr_v" "$_mtr_v"
  _mtr_rc=$MTR_RC
  _mtr_forged=$(grep -c 'FORGED' "$MTR_OUT" || true)
  assert "#6939 P7 OFF forged window value: rc 0, printed as <invalid>, no FORGED text, pointer present (rc=$_mtr_rc forged=$_mtr_forged)" "[[ '$_mtr_rc' == '0' && '$_mtr_forged' == '0' ]] && grep -qF '[<invalid>, <invalid>]' '$MTR_OUT' && grep -qF 'NOT EMITTED' '$MTR_OUT'"
done
MTR_LONG_ID=$(printf 'x%.0s' $(seq 1 200))
MTR_BAD_ID_FIXTURE=$(jq -nc --arg long "$MTR_LONG_ID" '{runs:[
  {functionID:"*",startedAt:"2026-07-08T12:00:00Z"},
  {functionID:"a\rb",startedAt:"2026-07-08T12:00:00Z"},
  {functionID:$long,startedAt:"2026-07-08T12:00:00Z"},
  {functionID:"fn-h",startedAt:"2026-07-08T11:00:05Z"},
  {functionID:"fn-h",startedAt:"2026-07-08T12:00:05Z"},
  {functionID:"fn-h",startedAt:"2026-07-08T13:00:05Z"}]}')
mtr_run true "$MTR_BAD_ID_FIXTURE" "$MTR_FROM" "$MTR_UNTIL"
_mtr_rc=$MTR_RC; _mtr_n=$(mtr_cands)
_mtr_cr=$(tr -cd '\r' < "$MTR_OUT" | wc -c | tr -d '[:space:]')
_mtr_glob=$(grep -c 'mtr-glob-sentinel' "$MTR_OUT" || true)
_mtr_long=$(grep -cF "$MTR_LONG_ID" "$MTR_OUT" || true)
assert "#6939 P7 ON bad function ids: rc 0 and none printed (rc=$_mtr_rc n=$_mtr_n cr=$_mtr_cr glob=$_mtr_glob long=$_mtr_long)" "[[ '$_mtr_rc' == '0' && '$_mtr_n' == '0' && '$_mtr_cr' == '0' && '$_mtr_glob' == '0' && '$_mtr_long' == '0' ]]"
assert "#6939 P7 ON bad function ids: the shape-check warning counts 3 skipped" "grep -qE '^::warning::missed-tick candidates: 3 function id\\(s\\) failed the shape check' '$MTR_OUT'"

# Anti-vacuity: every declared case actually dispatched (the counter is derived from the tables).
MTR_DECLARED=$(( ${#MTR_OFF_GATES[@]} + 1 + 1 + 1 + 1 + ${#MTR_BAD_WINDOWS[@]} + 1 + ${#MTR_FORGE[@]} + 1 ))
assert "#6939 every declared missed_tick_report case ran (ran=$MTR_CASES declared=$MTR_DECLARED)" "[[ '$MTR_CASES' -eq '$MTR_DECLARED' && '$MTR_CASES' -ge 17 ]]"

rm -rf "$BUCKET_PROGS_DIR"
rm -f "$DF_HARNESS_SRC"
rm -f "$ARM_FILE" "$ROLLBACK_FILE" "$CONFIRM_FILE" "$FWD_ARM_FILE" "$TAIL_FILE" "$PROBE_ARMS_FILE"

# WHOLE-SUITE ANTI-DELETION FLOOR (#7462 review). The only merge gate below is `FAIL -gt 0`, so
# deleting any assertion lowers the pass count silently and exits 0 — measured: removing the
# prod-write region assertion left the suite green. This floor is the full count at the time of
# writing; raise it in lockstep when adding assertions, never lower it to make a removal pass.
#
# 476 -> 496 (+20) at #7674 review: dual-field host isolation + #6616 spoof fixture, the resume G3
#   audibility gate, op-set parity between environment: and the arm token, and the L-dominates-H
#   rows. FLOOR IS NOW THE EXACT DISPATCHED COUNT — slack is attack budget, and the 1 assertion of
#   slack the previous floor carried absorbed exactly the row a mutation had proven load-bearing.
# 471 -> 475 (+4) when the AC3/AC4 chokepoint+ordering assertions landed (#7674).
# 449 -> 471 (+22) when G3.7 gained its second (liveness) signal and the `silent` outcome (#7674).
# 408 -> 449 (+41) when the G3.7 pre-flush-latch gate landed. Stated as a DELTA on purpose: the
# absolute number is only meaningful against the run that produced it, and re-deriving it after a
# rebase is the point at which a silently-dropped sibling assertion would otherwise be papered
# over. Re-measure by running this file, never by copying a remembered figure.
#
# REPORTS DIRECTLY, never through FAIL (ADR-193 #1). It previously did `FAIL=$((FAIL + 1))` and
# fell through to the shared `[[ "$FAIL" -gt 0 ]]` gate at the bottom — so with the assertion
# machinery neutered the floor "fired" into a counter nothing read before exit, and the suite
# printed a clean total and exited 0. A floor enforced through the suspect cannot witness the
# suspect. Caught by scripts/guard-vacuity-floor.test.sh ARM 2b, whose deferred-scope ratchet is
# 0 — this suite was the one member of the deferred population that still had the defect.
# 497 -> 556 (+59) at #8054 (re-measured after two review passes): the op=execute 2.0 dark arm — guarded-call shape, token/case
#   coverage, reader purity, ERG_ provenance, AC7 logic-diff, E11 set-equality against the P1-5
#   source, five rendered arms (H5/silent/read-failure/fsm_silent/H6 + control), and mutate_file
#   rows 17-20 with a known-negative. THE COMPARISON IS NOW EXACT (`-ne`), as the comment above
#   already claimed it was: the operator was `-lt`, and a `-lt` floor is satisfied by
#   delete-one-add-one. The failure text dictates the new number.
# 556 -> 586 (+30) at #6921: 2.1 source/captured_at pins, the P2-b Σ=0 parser render + control, the
#   rendered 2.2 QUIESCED gate (Guard 3 rows, excerpt, two mutate_file rows), the quiesce-web sentinel
#   confirm, and the D5 whole-file stale-token and new-prose pins.
# 586 -> 628 (+42) at PR #8173 review round 1 (contract §9): the §9 2.2 rows (every-body sentinel,
#   000 skipping, DISABLED_UNATTRIBUTED, HTTP-class remedies, excerpt, warning-before-verb) + the
#   every-body mutation, the R1 SOURCE single-writer pin + its mutation, the persisted 2.1 fields +
#   op=capture source, the held_back P2-b rows, the rendered quiesce-web preflight (+ mutation) and
#   poller arms, and the web-1-only / single web-2 statement pins.
# ── #6894: op=luks-cutover / op=luks-rollback — the LUKS blue-green cutover writers ─────────────
# Same contract as the sibling flag writers: the value goes in on STDIN (argv is world-readable via
# /proc), stdout is discarded (`doppler secrets set` prints every remaining secret of the config),
# every guard refuses BEFORE the write, and the on-host FSM is confirmed from Better Stack rather
# than assumed. The distinctive one is the TAG: the confirm and liveness readers must key on
# inngest-luks-cutover, not the flip's tag — the flip timer is enabled on a host where the cutover
# trio never installed, so borrowing its rows would report a silently-undelivered unit as audible.
LUKS_FILE="$(mktemp)"; SCRATCH+=("$LUKS_FILE")
awk '/^            luks-cutover\|luks-rollback\)$/,/^              ;;$/' "$WF" > "$LUKS_FILE"
LUKS_N=$(wc -l < "$LUKS_FILE" | tr -d '[:space:]')
assert "#6894 luks) case body is a real block (non-vacuity for every row below, got $LUKS_N)" \
  "[[ '$LUKS_N' -gt 40 ]]"
assert "#6894 choice list offers luks-cutover and luks-rollback" \
  "grep -qE '^[[:space:]]+-[[:space:]]*luks-cutover\$' '$WF_YAML' && grep -qE '^[[:space:]]+-[[:space:]]*luks-rollback\$' '$WF_YAML'"
assert "#6894 both ops are in the reviewer-gated environment set (an op in the list with an unextended ternary runs ungated)" \
  "printf '%s' \"\$ENV_OPS\" | grep -cF \"inputs.op == 'luks-cutover'\" >/dev/null && printf '%s' \"\$ENV_OPS\" | grep -cF \"inputs.op == 'luks-rollback'\" >/dev/null"
LK_STDIN=0;  grep -qF 'printf '"'"'%s'"'"' "$LK_WANT" | DOPPLER_TOKEN=' "$LUKS_FILE" && LK_STDIN=1
LK_ARGV=0;   grep -qE 'secrets set INNGEST_LUKS_CUTOVER=' "$LUKS_FILE" && LK_ARGV=1
LK_SILENT=0; grep -E 'doppler secrets set INNGEST_LUKS_CUTOVER' "$LUKS_FILE" | grep -c '>/dev/null' >/dev/null && LK_SILENT=1
LK_FLIPW=0;  grep -qE 'secrets set INNGEST_CUTOVER_FLIP' "$LUKS_FILE" && LK_FLIPW=1
# `|| true` because "no match" is a possible answer here, not a crash: an EMPTY line number means
# the anchor moved, and the two assertions below require `-n` on each before comparing — so the
# miss reds THERE, with the value printed, instead of killing the suite here with nothing said.
LK_WRITE_LN=$(grep -n 'doppler secrets set INNGEST_LUKS_CUTOVER' "$LUKS_FILE" | sed -n '1p' | cut -d: -f1) || true
LK_LASTG3_LN=$(grep -n 'G3 REFUSING' "$LUKS_FILE" | tail -1 | cut -d: -f1 || true) || true
LK_TS_LN=$(grep -n 'LK_TS=' "$LUKS_FILE" | sed -n '1p' | cut -d: -f1) || true
LK_G1READ=0; grep -qE 'doppler secrets get INNGEST_LUKS_CUTOVER -p soleur-inngest -c prd --plain' "$LUKS_FILE" && LK_G1READ=1
# BOTH fail-closed arms, by their DISTINCT sentences: one for "the config could not be read at
# all", one for "the name exists but its value could not be read". A count alone (or the shared
# prefix) is satisfied by either, so deleting the second one survived the first revision of this row.
LK_G1FC=0;   grep -qF 'could not be read at all' "$LUKS_FILE" \
             && grep -qF 'EXISTS but its value could not be read' "$LUKS_FILE" \
             && grep -qF 'has("INNGEST_LUKS_CUTOVER")' "$LUKS_FILE" \
             && [[ "$(grep -c 'G1 REFUSING FAIL-CLOSED' "$LUKS_FILE")" -eq 2 ]] && LK_G1FC=1
# ANCHORED as case ARMS, not as substrings: `present:luks-cutover-DISABLED)` contains
# `present:luks-cutover`, so a substring grep passed a mutant that had disabled the arm (measured).
# G1 for luks-rollback ADMITS `aborted` as its own case arm (the pointer decides at G2), and the
# refusal text no longer asserts the FSM "has already restored the plaintext store itself" — false
# for a rollback that refused mid-way (advisor consult at ship). Anchored as an arm, like G2's.
LK_G1RB_ABORTED=0; grep -qE '^[[:space:]]*aborted\)' "$LUKS_FILE" \
             && grep -qF "flag is 'aborted'. Permitted PROVISIONALLY" "$LUKS_FILE" \
             && ! grep -qF 'has already restored the plaintext store itself' "$LUKS_FILE" && LK_G1RB_ABORTED=1
LK_G2=0;     grep -qE '^[[:space:]]*present:luks-cutover\)' "$LUKS_FILE" \
             && grep -qE '^[[:space:]]*absent:luks-rollback\)' "$LUKS_FILE" \
             && grep -qE '^[[:space:]]*unreadable:\*\)' "$LUKS_FILE" \
             && grep -qF '_luks_pointer_state' "$LUKS_FILE" && LK_G2=1
LK_G3TAG=0;  grep -qF '_luks_liveness_count' "$LUKS_FILE" && ! grep -qF 'inngest-cutover-flip' "$LUKS_FILE" && LK_G3TAG=1
LK_CONF=0;   grep -qF 'confirm_luks_state' "$LUKS_FILE" && LK_CONF=1
LK_ISO=0;    grep -qF 'LK_ISO=$(date -u -d "@$LK_TS"' "$LUKS_FILE" && LK_ISO=1
LK_TERM=0;   grep -qE '^[[:space:]]+rolled-back\)$' "$LUKS_FILE" && grep -qE '^[[:space:]]+aborted\)$' "$LUKS_FILE" && LK_TERM=1
LK_ERRS=$(grep -cE '::error::op=' "$LUKS_FILE" || true)
LK_RAWJQ=0;  grep -qE 'jq \.($|[^a-zA-Z_])' "$LUKS_FILE" && LK_RAWJQ=1
assert "#6894 writes INNGEST_LUKS_CUTOVER on STDIN, never on argv (/proc is world-readable)" \
  "[[ '$LK_STDIN' -eq 1 && '$LK_ARGV' -eq 0 ]]"
assert "#6894 the write discards stdout (doppler secrets set prints every remaining secret of the config)" \
  "[[ '$LK_SILENT' -eq 1 ]]"
assert "#6894 neither verb writes the FLIP's flag — the destructive verb and the preserving one stay separate" \
  "[[ '$LK_FLIPW' -eq 0 ]]"
assert "#6894 the write is LAST: every guard refusal is above it (write line $LK_WRITE_LN > last G3 refusal $LK_LASTG3_LN)" \
  "[[ -n '$LK_WRITE_LN' && -n '$LK_LASTG3_LN' && '$LK_WRITE_LN' -gt '$LK_LASTG3_LN' ]]"
assert "#6894 G1 reads the flag AND separates unset from unreadable via the name list (a swallowed read is not 'unset')" \
  "[[ '$LK_G1READ' -eq 1 && '$LK_G1FC' -eq 1 ]]"
assert "#6894 G2 gates on the DURABLE pointer in both directions (absent to cut over, present to roll back, unreadable refuses)" \
  "[[ '$LK_G2' -eq 1 ]]"
assert "#6894 G3 liveness keys on the CUTOVER unit's own tag — a flip row proves nothing about a unit that never installed" \
  "[[ '$LK_G3TAG' -eq 1 ]]"
assert "#6894 the on-host FSM is CONFIRMED from Better Stack, not assumed" \
  "[[ '$LK_CONF' -eq 1 ]]"
assert "#6894 the confirm window is anchored at the WRITE, so a stale terminal row cannot false-succeed" \
  "[[ -n '$LK_TS_LN' && -n '$LK_WRITE_LN' && '$LK_TS_LN' -lt '$LK_WRITE_LN' && '$LK_ISO' -eq 1 ]]"
assert "#6894 a rolled-back or aborted FSM is reported as a FAILED dispatch, never a green one (got $LK_ERRS ::error:: arms)" \
  "[[ '$LK_TERM' -eq 1 && '$LK_ERRS' -ge 8 ]]"
assert "#6894 op=luks-rollback G1 admits 'aborted' as a case arm (G2's pointer decides), and no longer claims the FSM restored plaintext on every abort" \
  "[[ '$LK_G1RB_ABORTED' -eq 1 ]]"
assert "#6894 no raw Better Stack row is echoed by either verb (the standing purity contract)" \
  "! grep -qE 'jq \\.(\$|[^a-zA-Z_])' '$LUKS_FILE'"

# #8079 D4/AC12 — `_bs_read_remedy` no longer hardcodes the step it is reporting for. The census IS
# the assertion, not the number nine: a tenth message added later cannot slip through with a `2.0`
# prefix, and one added with no prefix at all fails the equality arm. Scoped to `$BS_REMEDY_FN` —
# the SAME awk-by-name extraction the renders drive — so the two `execute)` call sites and 2.0's own
# inline `::error::2.0 …` strings are out of frame, and a rename reddens this row too. Herestrings,
# never a pipe into `grep -c`: under `pipefail` an early SIGPIPE would make the count a lie.
_RM_HARDCODED=$(grep -c '::error::2\.0 ' <<<"$BS_REMEDY_FN" || true)
_RM_PARAM=$(grep -c '::error::\$step ' <<<"$BS_REMEDY_FN" || true)
_RM_TOTAL=$(grep -c '::error::' <<<"$BS_REMEDY_FN" || true)
assert "#8079 _bs_read_remedy census: 0 hardcoded '2.0 ' prefixes and all $_RM_TOTAL ::error:: lines carry \$step (hardcoded=$_RM_HARDCODED param=$_RM_PARAM)" \
  "[[ '$_RM_HARDCODED' -eq 0 && '$_RM_PARAM' -eq '$_RM_TOTAL' && '$_RM_TOTAL' -gt 0 ]]"

_DISPATCHED=$((PASS + FAIL))
# 628 -> 630 (+2) at PR #8204 review: the clean-fixture parse-rc and numeric-count rows on the two
# dupe-detector programs (a jq crash on CLEAN_FIXTURE must not read as 'clean').
# 630 -> 648 (+18) at the page-overlap dedupe fix: both-arms presence, 7 executed rows per site x2
#   (id key incl. same-millisecond keep + no-id fallback), loop-ran, incomplete-scan gate, fallback qualifier.
# RAISED 648 -> 649 (#8178), ITEMISED — one assertion: the bs_read_classify
# extraction non-vacuity check, added because _bs_read_remedy now calls the shared
# partition and an empty awk range would inline cleanly while leaving the rc=22 arm
# dead. Derived from main's value at ship time, not carried as a literal.
# 649 -> 664 (+15) at #6894: the op=luks-cutover / op=luks-rollback writer rows (stdin-not-argv,
#   stdout discarded, guards-before-write ordering, the pointer gate in both directions, the
#   own-tag liveness + confirm, the write-anchored confirm window, and the terminal-flag reporting).
#   Re-derived at the merge with main's #8178 row: 649 + 15, measured, not summed from memory.
# 665 -> 726 (+61) at #8079, measured on the tree rebased onto main at 665 (never summed
#   from memory): the D4 census, the gate-consumer census + whole-file total, PROBE_ARMS_CODE
#   non-vacuity, three D10 guards (token loop, plumbing parity + its control, cross-arm remedy
#   + twin pointers), the probe region extraction + selection control, AC2/3/8/9/10 static
#   rows, the 2x2 fixture control, fifteen direct renders, and seven range-scoped mutation rows.
# 726 -> 753 (+27) at the #8079 review round, measured: the per-arm exit/no-SSH row replacing
#   the two aggregate floors (net -1), the emptier's positive control, the other-entry-point
#   row, both region markers exactly-once, end-marker-then-;;, H3, the per-token fixture
#   control, the heartbeat read-failure render, eight per-token refusal renders, the H2
#   aborted must-PASS, the dark-warning truth row, and eleven mutation rows (M1.1, M1.2, the
#   same-line second call, M2.6, M2.7, M2.8, S1, M2.9, the nested $(gh …), S3, S6).
# 753 -> 759 (+6) at #7761, measured: the #7761 probe-parity block — probe-reason extraction
#   non-vacuity, probe-exists, the parity row, the delete and comment-out negative controls, and the
#   EXPECTED_GUARD == GUARD_REV row.
# 759 -> 877 (+118) G3 generation scope (the 2026-09-24 host-replace fix), measured on the tree merged
#   with main at 759: the `predecessor` RED row, 4 extraction rows, the jq self-check, H1, 14 lv_case
#   rows + 2 notice-counter rows, 5 notice/warning/token-shape rows, 14 anchor modes x 4 rows + the
#   mode counter, the absent/HTTP-class/no-token rows, 6 token-hygiene/transport rows, the set -e row,
#   12 decode rows + their counter, 4 LUKS rows, the unfloored-latch row, 3 invariant pins, the
#   workflow-knob row and 2 refusal-wording pins.
# 877 -> 885 (+8) at the #8759 review round, measured: the trailing-newline timestamp row, the
#   skew and malformed warnings, the fallback-token notice, the rejected-token name, the filter-fault
#   warning, the seventh-token refusal and the host-pair closure pin.
# 885 -> 914 (+29) at the #8759 test-design review, measured: one sentinel-absence row per lv_case
#   (+17), the dt-minus and extra-field decode rows, the 590/610 s and young-but-shipping warning rows,
#   the rc28/rc6 cause rows, the read/write mask row, 7 one-definition pins, the latch-body pin, the
#   stub-miss ledger and its positive control; minus one (xfield left the failure loop).
# 914 -> 964 (+50) #6939 missed-tick de-fang, measured: 51 rows in the #6939 block (guard-1
#   precondition + 2 file-wide flag rows, 4 workflow-shape rows, 4 call-site rows, the extraction row,
#   5 OFF gates x 4, the garbage-window row, 6 ON-canonical rows, the null/full rows, 3 invalid-window
#   rows, the empty-bound row, 3 P7 window rows, 2 P7 function-id rows, the case counter), minus the
#   retired vacuous `auto-emits the missed-tick trigger-cron list` grep.
_EXACT_FLOOR=964
if [[ "$_DISPATCHED" -lt "$_EXACT_FLOOR" ]]; then
  printf '\n[FATAL] anti-deletion floor: suite dispatched %d assertions, floor is %d — an assertion was removed or skipped.\n' "$_DISPATCHED" "$_EXACT_FLOOR" >&2
  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
elif [[ "$_DISPATCHED" -ne "$_EXACT_FLOOR" ]]; then
  printf '\n[FATAL] STALE FLOOR: suite dispatched %d assertions, _EXACT_FLOOR is %d — set _EXACT_FLOOR=%d (the count is exact by design; an assertion was added without updating it).\n' "$_DISPATCHED" "$_EXACT_FLOOR" "$_DISPATCHED" >&2
  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi
echo "  PASS: anti-deletion floor (exactly $_DISPATCHED assertions dispatched)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
