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
  assert "workflow targets \$BASE/$hook" "grep -qE 'BASE/$hook[?\"]' '$WF'"
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
assert "verify auto-emits the missed-tick trigger-cron list (P2-16)" "grep -qE 'soleur:trigger-cron' '$WF'"
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
assert "inventory outer curl --max-time 30 present" "grep -qE 'curl -s --max-time 30 -o /tmp/inv-body' '$WF'"
assert "doublefire outer curl --max-time 120 present (#6919)" "grep -qE 'curl -s --max-time 120 -o /tmp/verify-runs' '$WF'"

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
assert "inventory hook returns output on error (exit 1 → non-200)" "grep -A4 '\"id\": \"inngest-inventory\"' '$HOOKS_TMPL' | grep -q 'include-command-output-in-response-on-error.*true'"
assert "doublefire hook returns output on error (exit 1 → non-200)" "grep -A4 '\"id\": \"inngest-doublefire-probe\"' '$HOOKS_TMPL' | grep -q 'include-command-output-in-response-on-error.*true'"
assert "registry-probe hook returns output on error (exit 1 → non-200)" "grep -A4 '\"id\": \"inngest-registry-probe\"' '$HOOKS_TMPL' | grep -q 'include-command-output-in-response-on-error.*true'"
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
assert "DI-C3 execute inventory gate is NOT wrapped in a retry (single-shot)" "! grep -B2 'BASE/inngest-inventory\" || echo \"000\")' '$WF' | grep -q 'exec-inv.*for attempt'"
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
W_START=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | head -1 | cut -d: -f1) || true
W_END=$(grep -nF "printf '%s' 'armed'" "$ARM_FILE" | head -1 | cut -d: -f1) || true
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
# #7674: the query itself moved into the shared _flip_query_rows helper (one reader, two
# callers). The no-SSH / no-deploy-status invariant is asserted on the HELPER below; what is
# assertable HERE is that confirm still routes through it rather than growing a second reader.
assert "confirm reads through the shared _flip_query_rows helper (no second reader)" "grep -qE '_flip_query_rows ' '$CONFIRM_FILE' && ! grep -qE 'deploy-status' '$CONFIRM_FILE'"
assert "confirm never dumps a raw Better Stack row (no 'jq .')" "! grep -qE 'jq \\.($|[^a-zA-Z_])' '$CONFIRM_FILE'"
assert "confirm distinguishes a query-path failure from FSM-not-terminal (::warning:: CONFIRM PATH)" "grep -qE 'CONFIRM PATH' '$CONFIRM_FILE'"
# Emitter parity: the on-host emitter MUST actually stamp the flag states the confirm greps for.
EMITTER="$REPO_ROOT/apps/web-platform/infra/inngest-cutover-flip.sh"
assert "emitter stamps flag 'done' (the confirm's success key) + an aborted path" "grep -qF 'flag_set \"done\"' '$EMITTER' && grep -qF 'aborted' '$EMITTER'"

# op=arm calls the shared confirm with a SPACE-form timestamp betterstack-query.sh accepts (NOT the ISO
# T/Z form its ClickHouse cast rejects — the P2 that would false-negative every confirm).
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
G3ABORT_LN=$(grep -nF 'g3_action "$G3_OUTCOME"' "$ARM_FILE" | head -1 | cut -d: -f1) || true
G3ABORT_PGW=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | head -1 | cut -d: -f1) || true
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
awk '/^_flip_query_rows\(\) \{$/,/^\}$/' "$BODY_SH" > "$FLQ_FN"
FLQ_FN_N=$(wc -l < "$FLQ_FN" | tr -d '[:space:]')
assert "#7674 _flip_query_rows extraction is non-vacuous (>3 lines, got $FLQ_FN_N)" "[[ '$FLQ_FN_N' -gt 3 ]]"
# The no-SSH invariant, migrated here from confirm_flip_state when the reader was extracted.
assert "#7674 the shared reader queries via betterstack-query.sh (no SSH, no new transport)" \
  "grep -qE 'betterstack-query.sh' '$FLQ_FN' && ! grep -qE 'deploy-status' '$FLQ_FN'"
assert "#7674 the shared reader queries via prd_terraform (the betterstack-query cred config)" \
  "grep -qF -- '-c prd_terraform' '$FLQ_FN'"

FLV_ARGV="$(mktemp)"; SCRATCH+=("$FLV_ARGV")
FLV_OUT=""; FLV_RC=0
call_flip_liveness_count() { # $1 = rows | foreign | empty | fail
  local mode="$1"
  set +e
  FLV_OUT=$(
    eval "$(cat "$FLQ_FN")"
    eval "$(cat "$FLV_FN")"
    # shellcheck disable=SC2317  # invoked indirectly, by the eval'd reader above
    doppler() {
      printf '%s\n' "$*" > "$FLV_ARGV"
      case "$mode" in
        rows)
          printf '%s\n' '{"dt":"2026-08-25 10:20:51.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"x\"}"}'
          printf '%s\n' '{"dt":"2026-08-25 10:20:52.000000","raw":"{\"host\":\"soleur-inngest\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"y\"}"}'
          return 0 ;;
        foreign)
          # web-1 rows in the SAME multiplexed source — must NOT count as dedicated-host liveness.
          printf '%s\n' '{"dt":"2026-08-25 10:20:51.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-web-platform\",\"message\":\"x\"}"}'
          printf '%s\n' '{"dt":"2026-08-25 10:20:52.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-web-platform\",\"message\":\"y\"}"}'
          return 0 ;;
        spoofed)
          # THE #6616 COLLISION, FIXTURED: a WEB host self-labelling with the dedicated node's
          # sed-rendered host_name literal (#6616 is OPEN precisely because this was observed).
          # host_name ALONE counts these as our liveness -> H>0 -> `clear` -> the exact fail-open
          # this gate exists to close. The `host` conjunct is what excludes them, so this fixture
          # is what makes the dual-field filter load-bearing rather than decorative.
          printf '%s\n' '{"dt":"2026-08-25 10:20:51.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"x\"}"}'
          printf '%s\n' '{"dt":"2026-08-25 10:20:52.000000","raw":"{\"host\":\"soleur-web-platform\",\"host_name\":\"soleur-inngest-prd\",\"message\":\"y\"}"}'
          return 0 ;;
        empty) return 0 ;;
        *)     return 7 ;;
      esac
    }
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
    _flip_liveness_count 2>/dev/null
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
assert "#7674 the liveness reader decodes .raw before matching the host (raw is double-encoded)" \
  "grep -qE '\\.raw' '$FLV_FN'"
# DELIBERATELY A LITERAL, not env-overridable (#7674 review): it is not mapped into
# cutover-inngest.yml's step env, so an override would be an unperformable remediation (the
# #6617 dead-remediation class), and widening this window is the FAIL-OPEN direction.
assert "#7674 FLIP_LIVENESS_SINCE is the literal 15m (shape alone let 365d pass — fail-open)" \
  "grep -qE '^FLIP_LIVENESS_SINCE=\"15m\"$' '$BODY_SH'"
assert "#7674 FLIP_LIVENESS_SINCE is NOT plumbed into the workflow env (would be a dead knob)" \
  "! grep -qF 'FLIP_LIVENESS_SINCE' '$WF_YAML'"

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
RSL_RD=$(grep -nF 'RS_LIVE_N="$(_flip_liveness_count)"' "$RESUME_FILE" | head -1 | cut -d: -f1) || true
RSL_WR=$(grep -nE "secrets set INNGEST_CUTOVER_FLIP " "$RESUME_FILE" | head -1 | cut -d: -f1) || true
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
FLQ_SITES=$(grep -cE '^[[:space:]]*(rows=\$\()?_flip_query_rows ' "$BODY_SH") || true
assert "#7674 the shared reader has exactly 2 call sites (confirm + liveness), got $FLQ_SITES" \
  "[[ '$FLQ_SITES' -eq 2 ]]"
FLV_SITES=$(grep -cE '^[[:space:]]+FLIP_LIVENESS_N="?\$\(_flip_liveness_count' "$ARM_FILE") || true
assert "arm) reads liveness via _flip_liveness_count exactly once, got $FLV_SITES" \
  "[[ '$FLV_SITES' -eq 1 ]]"
FLV_LN=$(grep -nE '^[[:space:]]+FLIP_LIVENESS_N=' "$ARM_FILE" | head -1 | cut -d: -f1) || true
FLD_LN=$(grep -nE '^[[:space:]]+FL_OUTCOME=' "$ARM_FILE" | head -1 | cut -d: -f1) || true
assert "arm) the liveness reader is invoked BEFORE flush_latch_decide (H is never stale/unset)" \
  "[[ -n '$FLV_LN' && -n '$FLD_LN' && '$FLV_LN' -lt '$FLD_LN' ]]"
assert "arm) flush_latch_decide is called with BOTH signals (a one-arg call is the old fail-open)" \
  "grep -qE 'flush_latch_decide \"\\\$FLUSH_LATCH_N\" \"\\\$FLIP_LIVENESS_N\"' '$ARM_FILE'"
assert "arm) no G3.7 outcome arm carries its own exit (the gate decides)" \
  "! grep -qE '^[[:space:]]+(clear|latched|unreadable|silent)\\)[^#]*exit 1' '$ARM_FILE'"
# shellcheck disable=SC2016  # literal search pattern, not an expansion (G3ABORT_LN precedent)
FL_GATE_LN=$(grep -nF 'if [[ "$FL_OUTCOME" != "clear" ]]; then exit 1; fi' "$ARM_FILE" | head -1 | cut -d: -f1) || true
FL_PGW_LN=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | head -1 | cut -d: -f1) || true
FL_ARMW_LN=$(grep -nE "secrets set INNGEST_CUTOVER_FLIP " "$ARM_FILE" | head -1 | cut -d: -f1) || true
assert "arm) the G3.7 gate precedes the first prod write (pre-G4, not merely pre-G5)" \
  "[[ -n '$FL_GATE_LN' && -n '$FL_PGW_LN' && '$FL_GATE_LN' -lt '$FL_PGW_LN' ]]"
assert "arm) the G3.7 gate precedes the 'armed' write (the double-fire window it closes)" \
  "[[ -n '$FL_GATE_LN' && -n '$FL_ARMW_LN' && '$FL_GATE_LN' -lt '$FL_ARMW_LN' ]]"
# It must run AFTER G3.6 — both are pre-write refusals, and the cheaper Doppler read should not
# be gated behind a Better Stack round-trip.
FL_DIAG_LN=$(grep -nE 'case "\$\(diag_boot_decide ' "$ARM_FILE" | head -1 | cut -d: -f1) || true
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
G36_LN=$(grep -nF 'G3.6 REFUSING' "$ARM_FILE" | head -1 | cut -d: -f1) || true
G36_PGW_LN=$(grep -nE 'secrets set INNGEST_POSTGRES_URI ' "$ARM_FILE" | head -1 | cut -d: -f1) || true
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
  "grep -A4 'BS_API=\$(doppler secrets get BETTERSTACK_API_TOKEN' '$ROLLBACK_FILE' | grep -qF '::add-mask::'"
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
assert "#6617 probe arms make exactly 2 network/tool calls" "[[ \"\$(grep -cE '(^|[^a-z-])(curl|wget|nc|ncat|socat|python3?|perl|gh|aws|doppler|hcloud)[[:space:]]' '$PROBE_ARMS_FILE')\" == '2' ]]"
assert "#6617 both are curl -X GET" "[[ \"\$(grep -c -- '-X GET' '$PROBE_ARMS_FILE')\" == '2' ]]"
assert "#6617 both are bounded (--max-time)" "[[ \"\$(grep -c -- '--max-time' '$PROBE_ARMS_FILE')\" == '2' ]]"

# 2. No request body, by any tool or flag spelling.
assert "#6617 probe arms send NO request body" "! grep -qE '(^|[[:space:]])(-d|--data|--data-binary|--data-raw|--data-urlencode|--post-data|--post-file|-T|--upload-file)([[:space:]]|=)' '$PROBE_ARMS_FILE'"
assert "#6617 probe arms use NO non-GET method flag" "! grep -qE '(-X|--request)[[:space:]]*(POST|PUT|PATCH|DELETE)' '$PROBE_ARMS_FILE'"

# 3. No mutating tool present at all, whatever its flag order.
assert "#6617 probe arms invoke NO doppler at all" "! grep -qE '(^|[^a-z-])doppler([[:space:]]|\$)' '$PROBE_ARMS_FILE'"
assert "#6617 probe arms invoke NO wget/nc/socat egress" "! grep -qE '(^|[^a-z-])(wget|ncat|socat)([[:space:]]|\$)' '$PROBE_ARMS_FILE'"

# 4. No cutover-state transition — matching the JSON form the workflow uses,
#    not the bare token that only ever appears in prose.
assert "#6617 probe arms perform NO reminder capture" "! grep -qE '\"mode\"[[:space:]]*:[[:space:]]*\"capture\"|mode=capture' '$PROBE_ARMS_FILE'"
assert "#6617 probe arms perform NO deploy-hook write" "! grep -qE 'hooks/deploy' '$PROBE_ARMS_FILE'"
assert "#6617 probe arms touch NO flip/quiesce/rearm hook" "! grep -qE 'inngest-(arm|flip|quiesce|rearm|wiped)' '$PROBE_ARMS_FILE'"

# --- Single-shot: no retry loop, whatever the keyword (B-AC4) ---
# Anchored at LINE START: a loop keyword only ever begins a statement there.
# The unanchored form matched the word "for" inside this arm's own comments —
# the same comment-vs-code collision cq-assert-anchor-not-bare-token warns about.
assert "#6617 probe arms add NO retry loop" "! grep -qE '^[[:space:]]*(for|while|until)[[:space:]]' '$PROBE_ARMS_FILE'"

# --- Reviewer-gate membership (B-AC3, amended #7228) -----------------------------------------
# This was a byte-identity pin on the environment: expression, whose purpose is to stop the
# approval gate being WIDENED — i.e. to stop ops being added that write prod without review.
# #7228 adds op=resume, which writes INNGEST_CUTOVER_FLIP=flushed and therefore AUTHORIZES a prod
# scheduler start: it must be INSIDE the gate, not outside it. A byte-identity pin cannot express
# "this set may only grow toward MORE review", so it is replaced by a membership assertion in
# both directions — every prod-writing op is gated, and the read-only probe ops still are not.
# That is strictly stronger than the byte pin: it would also catch a REMOVAL, which byte identity
# only caught incidentally.
ENV_EXPR=$(grep -E '^[[:space:]]+environment:' "$WF" | head -1 || true)
assert "#7228 the environment: expression was located (else these pins are vacuous)" \
  "[[ -n \"\$ENV_EXPR\" ]]"
for _op in arm rollback resume; do
  assert "#7228 prod-writing op '\$_op' is INSIDE the required-reviewer gate" \
    "printf '%s' \"\$ENV_EXPR\" | grep -qF \"inputs.op == '\$_op'\""
done
assert "#7228 the gate still resolves to the inngest-cutover environment" \
  "printf '%s' \"\$ENV_EXPR\" | grep -qF \"'inngest-cutover'\""
# THE OP SET IS DUPLICATED IN TWO EXPRESSIONS AND NOTHING TIED THEM TOGETHER (#7674 review).
# `environment:` decides WHO MUST APPROVE; the DOPPLER_TOKEN_INNGEST_ARM expression decides WHO
# GETS THE PROD-WRITE TOKEN. Adding an op to the token expression but not the environment one
# hands that op an arm-capable credential with NO required reviewer — and every pre-existing
# assertion here passed, because they check the two expressions independently. Pin the SETS equal.
ENV_OPS=$(printf '%s' "$ENV_EXPR" | grep -oE "inputs\.op == '[a-z-]+'" | sort -u) || true
TOK_EXPR=$(grep -E 'DOPPLER_TOKEN_INNGEST_ARM:' "$WF" | head -1) || true
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

assert "#6617 neither probe op appears in the environment: expression" "! grep -E '^[[:space:]]+environment:' '$WF' | grep -qE 'registry-probe|doublefire-probe'"

# --- Scope caveat carried verbatim from op=verify 2.6 (B-AC7) ---
assert "#6617 doublefire-probe carries the 2.6 scope caveat" "grep -qF 'NOT a web-2 double-fire detector' '$PROBE_ARMS_FILE'"

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
  "! grep -vE '^[[:space:]]*#' '$WF' | grep -qE '\.registry_empty[[:space:]]*//'"
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
NULL_FIXTURE='{"runs":[
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:02:00Z"},
  {"functionID":"fn-b","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-c","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-c","startedAt":"2026-07-08T10:40:00Z"}]}'
# A fixture with NO duplicate at all — proves the dupe detector can say "clean", so an
# always-reports-a-dupe mutation cannot pass by satisfying only the positive case.
CLEAN_FIXTURE='{"runs":[
  {"functionID":"fn-q","startedAt":null},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:00:00Z"},
  {"functionID":"fn-a","startedAt":"2026-07-08T10:40:00Z"},
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
    clean_n=$(jq -c --argjson period 1200 -f "$prog" <<<"$CLEAN_FIXTURE" 2>/dev/null | jq 'length')
    assert "#6178 $pname reports ZERO groups on a genuinely clean fixture (detector can say clean)" "[[ '$clean_n' -eq 0 ]]"
  else
    # The missed-tick OBSERVED program: a deduplicated (fn, bucket) set, nulls excluded.
    obs_n=$(jq -c --argjson period 1200 -f "$prog" <<<"$NULL_FIXTURE" 2>/dev/null | jq 'length')
    assert "#6178 $pname yields 4 distinct (fn,bucket) pairs, nulls excluded" "[[ '$obs_n' -eq 4 ]]"
  fi
done

# --- NON-VACUITY HARD GATE (AC-V3), enforced in code rather than by operator diligence. ---
assert "#6178 op=verify READS the server's total_count (it was emitted and never consumed)" \
  "grep -qE 'TOTAL_COUNT=.*jq -r .\\.total_count' '$VERIFY_ARM_FILE'"
assert "#6178 op=verify HARD-FAILS a vacuous scan rather than reporting a verdict" \
  "grep -qF 'VACUOUS SCAN' '$VERIFY_ARM_FILE'"
assert "#6178 the vacuity gate covers 0, unknown, absent AND run_count==0" \
  "grep -qF '\"\$TOTAL_COUNT\" == \"0\"' '$VERIFY_ARM_FILE' && grep -qF '\"\$TOTAL_COUNT\" == \"unknown\"' '$VERIFY_ARM_FILE' && grep -qF '\"\$TOTAL_COUNT\" == \"absent\"' '$VERIFY_ARM_FILE' && grep -qF '\"\$RUN_COUNT\" -eq 0' '$VERIFY_ARM_FILE'"
assert "#6178 the vacuity gate EXITS (a warning would still let the verdict print)" \
  "grep -A3 'VACUOUS SCAN' '$VERIFY_ARM_FILE' | grep -qE 'exit 1'"
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
if [[ "$PASS" -lt 497 ]]; then
  printf '\n[FATAL] anti-deletion floor: suite dispatched %d assertions, floor is 497 — an assertion was removed or skipped.\n' "$PASS" >&2
  echo ""
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi
echo "  PASS: anti-deletion floor ($PASS >= 497 assertions dispatched)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
