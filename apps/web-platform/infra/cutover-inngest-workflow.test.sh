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
  assert "workflow targets \$BASE/$hook" "grep -qE 'BASE/$hook\"' '$WF'"
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
assert "SEAM arms the Doppler flip (INNGEST_CUTOVER_FLIP=armed)" "grep -qE 'INNGEST_CUTOVER_FLIP=armed' '$WF'"

# D.3 / AC-VERIFY — op=verify: precondition registry NON-empty (2.4 landed,
# P1-9/P2-17), 2.6 via the doublefire hook, RunsFilterV2 + STARTED_AT bucketing,
# and NO scheduled_tick anywhere in the workflow.
assert "verify calls the doublefire-probe hook (2.6/P1-12)" "grep -qE 'BASE/inngest-doublefire-probe\"' '$WF'"
assert "verify preconditions on registry NON-empty (P1-9/P2-17)" "grep -qE 'verify precondition' '$WF'"
assert "verify buckets by floor(startedAt / cron_period) (no scheduled_tick)" "grep -qE 'fromdateiso8601' '$WF'"
assert "verify auto-emits the missed-tick trigger-cron list (P2-16)" "grep -qE 'soleur:trigger-cron' '$WF'"
assert "workflow contains NO 'scheduled_tick' anywhere (AC-VERIFY)" "! grep -qE 'scheduled_tick' '$WF'"

# D.6 / AC-ROLLBACK (P1-13) — op=rollback re-enables inngest across the host-set
# (reverse of 2.2) and confirms via inventory.
assert "rollback re-enables inngest on the host-set (restart fan-out)" "grep -qE 'restart inngest _ latest' '$WF'"
assert "rollback confirms via the inventory hook" "grep -qE 'BASE/inngest-inventory\"' '$WF'"
assert "rollback iterates the SAME \$CUTOVER_HOSTS set (P1-13)" "grep -qE 'reverse of 2.2 quiesce' '$WF'"

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
assert "doublefire in-script deadline (50) < outer curl --max-time 60 (SUM bound)" "[[ -n '$DF_DEADLINE' && '$DF_DEADLINE' -lt 60 ]]"
assert "inventory clamps per-page curl to the remaining budget (not a fixed const)" "grep -qE 'max-time \"\\\$max_time\"' '$INV_SH' && grep -qE 'remaining=\\\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' '$INV_SH'"
assert "doublefire clamps per-page curl to the remaining budget" "grep -qE 'max-time \"\\\$max_time\"' '$DF_SH' && grep -qE 'remaining=\\\$\(\( PREFLIGHT_DEADLINE_S - elapsed \)\)' '$DF_SH'"
# outer curl budgets present (the ceiling the sum must stay under).
assert "inventory outer curl --max-time 30 present" "grep -qE 'curl -s --max-time 30 -o /tmp/inv-body' '$WF'"
assert "doublefire outer curl --max-time 60 present" "grep -qE 'curl -s --max-time 60 -o /tmp/verify-runs' '$WF'"

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

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
