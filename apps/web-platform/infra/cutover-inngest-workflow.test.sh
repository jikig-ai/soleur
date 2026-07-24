#!/usr/bin/env bash
# Tests for .github/workflows/cutover-inngest.yml — the no-SSH cutover driver
# (#5450, AC5/Test-Scenario-5). The live workflow can only be exercised post-merge
# (a NEW workflow 404s on `gh workflow run --ref <feature-branch>`, R4), so these
# assert the YAML shape + the safety/poll invariants statically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/cutover-inngest.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    cond: $cond"; FAIL=$((FAIL + 1)); fi
}

echo "=== cutover-inngest.yml workflow tests ==="

assert "workflow file exists" "[[ -f '$WF' ]]"

# YAML parses
assert "YAML parses (pyyaml)" "python3 -c 'import yaml,sys; yaml.safe_load(open(\"$WF\"))'"

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
assert "execute prints the operator SEAM only after the gate" "grep -qE 'SEAM . operator maintenance-window steps' '$WF'"
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
# INVARIANT (negative): the cost lever is functionIDs + a 200d (> the 182d = 2×quarterly floor)
# window — the TIME window is NEVER narrowed to hours/days (that would surface false missed-ticks
# at :704-743 → operator re-fire → the exact DOUBLE-FIRE the cutover prevents).
assert "#6919 doublefire_from is ≥ 200 days (⊇ the 182d invariant, never a day/hour narrow)" "grep -qF '200 * 86400' '$WF' && grep -qF '200 days ago' '$WF'"

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

ARM_FILE="$(mktemp)"; ROLLBACK_FILE="$(mktemp)"
awk '/^            arm\)$/,/^              ;;$/' "$WF" > "$ARM_FILE"
awk '/^            rollback\)$/,/^              ;;$/' "$WF" > "$ROLLBACK_FILE"
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
assert "arm) G3 rejects the :6543 transaction pooler" "grep -qF ':6543' '$ARM_FILE'"
assert "arm) G3 requires the :5432 session pooler" "grep -qF ':5432' '$ARM_FILE'"
assert "arm) G3 refuses when prod == dark (PG == PG_DARK)" "grep -qE 'PG.*==.*PG_DARK' '$ARM_FILE'"
assert "arm) G1 reads the current INNGEST_CUTOVER_FLIP from soleur-inngest (pre-write state guard)" "grep -qE 'doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest' '$ARM_FILE'"
assert "arm) G1 refuses re-arm over a non-safe FSM state (DI-C2 REFUSING)" "grep -qE 'G1 REFUSING' '$ARM_FILE'"

# AC9 FSM confirm — the confirm logic is the SHARED confirm_flip_state() function (used by op=arm G6
# AND op=rollback). Extract it and assert it keys on the emitter's `flag` field, NOT `reason`: the
# on-host emitter (apps/web-platform/infra/inngest-cutover-flip.sh `emit_state exit_code dbsize reason
# flag`) puts the TERMINAL STATE in `flag` (done/aborted/rolled-back) and a CAUSE in `reason` (which
# NEVER equals done/aborted). A confirm keyed on `"reason":"done"` would match no row → every op=arm
# times out. This block is the cross-file parity that stops that silent drift.
CONFIRM_FILE="$(mktemp)"
awk '/^          confirm_flip_state\(\) \{$/,/^          \}$/' "$WF" > "$CONFIRM_FILE"
CONFIRM_N=$(wc -l < "$CONFIRM_FILE")
assert "confirm_flip_state() is defined + non-empty (F6 non-vacuity)" "[[ '$CONFIRM_N' -gt 5 ]]"
assert "confirm keys on the emitter FLAG field (\"flag\":\"done\" + exit_code:0 — NOT reason)" "grep -qF '\"flag\":\"done\"' '$CONFIRM_FILE' && grep -qF '\"exit_code\":0' '$CONFIRM_FILE'"
assert "confirm does NOT key on \"reason\":\"done\" (the field-mismatch bug the review caught)" "! grep -qF '\"reason\":\"done\"' '$CONFIRM_FILE'"
assert "confirm detects the aborted terminal flag (fail-loud path)" "grep -qF '\"flag\":\"aborted\"' '$CONFIRM_FILE'"
assert "confirm detects the rolled-back terminal flag" "grep -qF '\"flag\":\"rolled-back\"' '$CONFIRM_FILE'"
assert "confirm reads via betterstack-query.sh (no-SSH), never a deploy-status poll" "grep -qE 'betterstack-query.sh --since' '$CONFIRM_FILE' && ! grep -qE 'deploy-status' '$CONFIRM_FILE'"
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
assert "arm) G3 pins the prod project-ref (stronger than a bare 'supabase' substring)" "grep -qF 'pigsfuxruiopinouvjwy' '$ARM_FILE'"
assert "arm) G1 fail-CLOSED: probes config readability (DOPPLER_PROJECT) before trusting an empty flip" "grep -qF 'config-readability probe failed' '$ARM_FILE' && grep -qE 'doppler secrets get DOPPLER_PROJECT -p soleur-inngest' '$ARM_FILE'"
assert "arm) G3 fail-CLOSED on an empty PG_DARK read (no silent equality-pass)" "grep -qF 'could not read the current dark INNGEST_POSTGRES_URI' '$ARM_FILE'"
assert "arm) adds NO deploy-status poll (Better Stack read only — QMAX/RMAX untouched, AC9)" "! grep -qE 'deploy-status' '$ARM_FILE'"

# AC13 no ssh in the arm block.
assert "arm) contains no ssh (AC-NOSSH/AC13)" "! grep -qE '(^|[^[:alnum:]])ssh[[:space:]]' '$ARM_FILE'"

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
FWD_ARM_FILE="$(mktemp)"
awk '/^[[:space:]]+armed\|flipping\|flushed\|done\)$/,/^[[:space:]]+;;$/' "$WF" > "$FWD_ARM_FILE"
FWD_ARM_N=$(wc -l < "$FWD_ARM_FILE" | tr -d '[:space:]')
TAIL_FILE="$(mktemp)"
awk '/^[[:space:]]*esac$/,0' "$ROLLBACK_FILE" > "$TAIL_FILE"
TAIL_N=$(wc -l < "$TAIL_FILE" | tr -d '[:space:]')
assert "#6552 rollback DELETEs INNGEST_HEARTBEAT_URL from soleur-inngest/prd (inverse of arm G4)" "grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL -p soleur-inngest -c prd' '$ROLLBACK_FILE'"
assert "#6552 delete is value-silent (--yes + stdout redirected)" "grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL.*--yes.*>/dev/null' '$ROLLBACK_FILE'"
assert "#6552 forward-state inner arm extraction is non-vacuous (F6)" "[[ '$FWD_ARM_N' -gt 3 ]]"
assert "#6552 delete is UNCONDITIONAL — NOT nested in the armed|flipping|flushed|done) case arm" "! grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL' '$FWD_ARM_FILE'"
assert "#6552 after-inner-esac tail is non-vacuous" "[[ '$TAIL_N' -gt 3 ]]"
assert "#6552 delete runs in the unconditional Half-B tail (after inner esac) — reached for aborted/unset/re-dispatch" "grep -qE 'doppler secrets delete INNGEST_HEARTBEAT_URL' '$TAIL_FILE'"

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
PROBE_ARMS_FILE="$(mktemp)"
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

# --- No reviewer-gate widening (B-AC3). The environment: expression must stay
# byte-identical; both new ops fall through to '' (no approval gate). ---
assert "#6617 environment: expression unchanged (no gate widening)" "grep -qFx \"    environment: \\\${{ (inputs.op == 'arm' || inputs.op == 'rollback') && 'inngest-cutover' || '' }}\" '$WF'"
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

rm -f "$ARM_FILE" "$ROLLBACK_FILE" "$CONFIRM_FILE" "$FWD_ARM_FILE" "$TAIL_FILE" "$PROBE_ARMS_FILE"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
