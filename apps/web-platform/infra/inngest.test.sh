#!/usr/bin/env bash
# Tests for inngest.tf (PR-F follow-up, #3960).
#
# Validates the IaC contract without standing up real providers:
#   - inngest.tf is syntactically valid HCL (`terraform fmt -check` + grep checks).
#   - Required resources are declared (6 random_id, 7 doppler_secret,
#     1 betteruptime_heartbeat, conditional betteruptime_policy).
#   - Distinctness invariants encoded via random_id ensure prd ≠ dev and
#     signing ≠ event by construction.
#   - `betteruptime_policy.inngest` `count` expression is gated on
#     var.betterstack_paid_tier.
#
# `terraform validate` against the live providers is gated to Phase 2 (apply
# time) because it requires `doppler` and `betteruptime` providers initialized
# with real credentials.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNGEST_TF="$SCRIPT_DIR/inngest.tf"
MAIN_TF="$SCRIPT_DIR/main.tf"
VARS_TF="$SCRIPT_DIR/variables.tf"
OUTPUTS_TF="$SCRIPT_DIR/outputs.tf"
BOOTSTRAP_SH="$SCRIPT_DIR/inngest-bootstrap.sh"

PASS=0
FAIL=0
TOTAL=0

assert() {
  local description="$1"
  local condition="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$condition"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        condition: $condition"
  fi
}

echo "=== inngest.tf tests ==="
echo ""

# --- File existence ---
echo "--- File existence ---"
assert "inngest.tf exists"             "[[ -f '$INNGEST_TF' ]]"
assert "main.tf updated with providers" "grep -qE 'DopplerHQ/doppler'    '$MAIN_TF'"
assert "main.tf updated with BetterStack" "grep -qE 'BetterStackHQ/better-uptime' '$MAIN_TF'"
assert "main.tf has doppler provider block" "grep -qE '^provider \"doppler\"' '$MAIN_TF'"
assert "main.tf has betteruptime provider block" "grep -qE '^provider \"betteruptime\"' '$MAIN_TF'"

# --- Variables ---
echo ""
echo "--- Variables (3 new) ---"
assert "doppler_token_tf variable exists"  "grep -qE '^variable \"doppler_token_tf\"'  '$VARS_TF'"
assert "betterstack_api_token variable exists" "grep -qE '^variable \"betterstack_api_token\"' '$VARS_TF'"
assert "betterstack_paid_tier variable exists" "grep -qE '^variable \"betterstack_paid_tier\"' '$VARS_TF'"

# --- random_id resources (6: signing+event × prd+dev + manual-trigger × prd+dev) ---
echo ""
echo "--- random_id resources (6) ---"
assert "random_id.inngest_signing_key_prd" "grep -qE 'resource \"random_id\" \"inngest_signing_key_prd\"' '$INNGEST_TF'"
assert "random_id.inngest_signing_key_dev" "grep -qE 'resource \"random_id\" \"inngest_signing_key_dev\"' '$INNGEST_TF'"
assert "random_id.inngest_event_key_prd"   "grep -qE 'resource \"random_id\" \"inngest_event_key_prd\"'   '$INNGEST_TF'"
assert "random_id.inngest_event_key_dev"   "grep -qE 'resource \"random_id\" \"inngest_event_key_dev\"'   '$INNGEST_TF'"
assert "random_id.inngest_manual_trigger_secret_prd" "grep -qE 'resource \"random_id\" \"inngest_manual_trigger_secret_prd\"' '$INNGEST_TF'"
assert "random_id.inngest_manual_trigger_secret_dev" "grep -qE 'resource \"random_id\" \"inngest_manual_trigger_secret_dev\"' '$INNGEST_TF'"
assert "random_id uses byte_length 32 (>=6)" "[[ \$(grep -c 'byte_length = 32' '$INNGEST_TF') -ge 6 ]]"

# --- doppler_secret resources (7: 4 keys + heartbeat URL prd + 2 manual-trigger) ---
echo ""
echo "--- doppler_secret resources (7) ---"
assert "doppler_secret.inngest_signing_key_prd" "grep -qE 'resource \"doppler_secret\" \"inngest_signing_key_prd\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_signing_key_dev" "grep -qE 'resource \"doppler_secret\" \"inngest_signing_key_dev\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_event_key_prd"   "grep -qE 'resource \"doppler_secret\" \"inngest_event_key_prd\"'   '$INNGEST_TF'"
assert "doppler_secret.inngest_event_key_dev"   "grep -qE 'resource \"doppler_secret\" \"inngest_event_key_dev\"'   '$INNGEST_TF'"
assert "doppler_secret.inngest_heartbeat_url_prd" "grep -qE 'resource \"doppler_secret\" \"inngest_heartbeat_url_prd\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_manual_trigger_secret_prd" "grep -qE 'resource \"doppler_secret\" \"inngest_manual_trigger_secret_prd\"' '$INNGEST_TF'"
assert "doppler_secret.inngest_manual_trigger_secret_dev" "grep -qE 'resource \"doppler_secret\" \"inngest_manual_trigger_secret_dev\"' '$INNGEST_TF'"
assert "INNGEST_MANUAL_TRIGGER_SECRET name present (prd+dev)" "[[ \$(grep -cE 'name[[:space:]]+= \"INNGEST_MANUAL_TRIGGER_SECRET\"' '$INNGEST_TF') -eq 2 ]]"

# Distinctness: signing keys carry signkey-prod-/signkey-test- prefixes ensuring prd ≠ dev.
assert "signkey-prod- prefix on prd signing key" "grep -qE '\"signkey-prod-' '$INNGEST_TF'"
assert "signkey-test- prefix on dev signing key" "grep -qE '\"signkey-test-' '$INNGEST_TF'"

# Every doppler_secret has lifecycle ignore_changes on value (rotation safety).
assert "lifecycle ignore_changes [value] on each doppler_secret" \
  "[[ \$(grep -c 'ignore_changes = \\[value\\]' '$INNGEST_TF') -ge 7 ]]"

# --- BetterStack heartbeat + policy ---
echo ""
echo "--- BetterStack ---"
assert "betteruptime_heartbeat.inngest_prd"   "grep -qE 'resource \"betteruptime_heartbeat\" \"inngest_prd\"' '$INNGEST_TF'"
assert "betteruptime_policy.inngest exists"   "grep -qE 'resource \"betteruptime_policy\" \"inngest\"' '$INNGEST_TF'"
assert "policy count gated on paid_tier"      "grep -qE 'count = var.betterstack_paid_tier \\? 1 : 0' '$INNGEST_TF'"
assert "heartbeat policy_id is ternary on paid_tier" \
  "grep -qE 'policy_id .* var.betterstack_paid_tier' '$INNGEST_TF'"

# --- Outputs ---
echo ""
echo "--- Outputs ---"
assert "inngest_heartbeat_url output (sensitive)" \
  "grep -qzE 'output \"inngest_heartbeat_url\".*sensitive[[:space:]]*=[[:space:]]*true' '$OUTPUTS_TF'"

# --- Inngest CLI locals (Phase 0.3 pin) ---
echo ""
echo "--- Inngest CLI version pin ---"
assert "inngest_cli_version local set"       "grep -qE 'inngest_cli_version *= *\"v[0-9]+\\.[0-9]+\\.[0-9]+\"' '$INNGEST_TF'"
assert "inngest_cli_sha256 local set (64 hex)" "grep -qE 'inngest_cli_sha256 *= *\"[0-9a-f]{64}\"' '$INNGEST_TF'"

# --- Heartbeat unit shape in inngest-bootstrap.sh (#4116) ---
echo ""
echo "--- Heartbeat unit shape (inngest-bootstrap.sh) ---"
assert "inngest-bootstrap.sh exists" "[[ -f '$BOOTSTRAP_SH' ]]"

# Extract the heartbeat unit's heredoc body so the assertions only fire on the
# HEARTBEAT_UNIT block (not the unrelated UNITEOF block for inngest-server).
HEARTBEAT_BLOCK=$(awk '/cat > "\$HEARTBEAT_UNIT" <</,/^HEARTBEATEOF$/' "$BOOTSTRAP_SH")

# Reference the block BY NAME ("$HEARTBEAT_BLOCK"), never by embedding its
# value ('$HEARTBEAT_BLOCK'): the block's comments contain apostrophes
# (e.g. "inngest-server.service's"), which break the single-quoted eval form.
assert "heartbeat unit uses doppler run" \
  "[[ -n \"\$HEARTBEAT_BLOCK\" ]] && printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE 'run --project soleur --config prd'"
assert "heartbeat unit ExecStart is exactly one line" \
  "[[ \$(printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -c '^ExecStart=') -eq 1 ]]"
assert "heartbeat unit ExecStart wraps HEARTBEAT_SCRIPT under doppler" \
  "printf '%s\n' \"\$HEARTBEAT_BLOCK\" | grep -qE '^ExecStart=.* run --project soleur --config prd -- \\\$\\{HEARTBEAT_SCRIPT\\}'"
DOPPLER_BIN_LINE=$(grep -nE 'DOPPLER_BIN=.*command -v doppler' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
# Single-quotes are intentional — the regex matches the literal shell text
# `cat > "$HEARTBEAT_UNIT"` in the bootstrap script's source.
HEARTBEAT_UNIT_LINE=$(grep -nE 'cat > "\$HEARTBEAT_UNIT"' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
assert "DOPPLER_BIN resolved via command -v before HEARTBEAT_UNIT write" \
  "[[ -n '$DOPPLER_BIN_LINE' && -n '$HEARTBEAT_UNIT_LINE' && '$DOPPLER_BIN_LINE' -lt '$HEARTBEAT_UNIT_LINE' ]]"

# --- Inngest-SERVER unit ExecStart: poll-interval + sdk-url (#4652) ---
echo ""
echo "--- Inngest-server unit ExecStart (#4652 poll-interval/sdk-url) ---"
# Extract the inngest-SERVER unit's heredoc body (single-quoted 'UNITEOF'
# marker, distinct from the heartbeat HEARTBEATEOF block). Start anchor is the
# literal `cat > "$UNIT_FILE" <<'UNITEOF'`; end anchor is a line that is exactly
# `UNITEOF` (no self-match — the start line ends in `<<'UNITEOF'`, not `UNITEOF`
# alone).
# shellcheck disable=SC2016
SERVER_UNIT_BLOCK=$(awk '/cat > "\$UNIT_FILE" <</,/^UNITEOF$/' "$BOOTSTRAP_SH")
# Reference BY NAME ("$SERVER_UNIT_BLOCK") — the server ExecStart contains
# single quotes (`bash -c '...'`), so the value-embedded '$VAR' form would
# break the eval (same fragility fixed in the heartbeat assert above).
assert "inngest-server unit block extracted (non-empty)" \
  "[[ -n \"\$SERVER_UNIT_BLOCK\" ]] && [[ \$(printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | wc -l) -ge 5 ]]"
# AC1: each new flag asserted independently (flag-order-insensitive).
assert "server ExecStart sets --poll-interval 60" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qE 'inngest start .*--poll-interval 60'"
assert "server ExecStart sets --sdk-url loopback app route (port 3000)" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qF 'sdk-url http://127.0.0.1:3000/api/inngest'"
# Regression guard: the signing-key strip + event-key must survive the edit
# (the systemd `$$` escape must not be accidentally unescaped — Sharp Edge).
assert "server ExecStart keeps signing-key strip + event-key" \
  "printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qF 'INNGEST_SIGNING_KEY#signkey-prod-' && printf '%s\n' \"\$SERVER_UNIT_BLOCK\" | grep -qF 'INNGEST_EVENT_KEY'"
# --- #5547 Gap 2: REDIS_READY-gated durable/SQLite-fail-safe ExecStart ---
# The durable backend flags (#5450) moved OUT of the single-quoted server-unit
# heredoc into a REDIS_READY-gated BACKEND_FLAGS fragment that is substituted
# into the written unit (the heredoc carries a literal @@BACKEND_FLAGS@@
# sentinel). This keeps inngest-server AVAILABLE on a SQLite-only ExecStart when
# Redis is unprovisioned instead of crash-looping on 127.0.0.1:6379 (the ~3.5h
# #5542 outage). The asserts below therefore scope the durable-flag checks to
# the fragment ASSIGNMENT line, not SERVER_UNIT_BLOCK (AC8 reconcile).
echo ""
echo "--- #5547 Gap 2: REDIS_READY-gated durable/SQLite ExecStart fragment ---"

# AC2 — REDIS_READY is assigned AFTER the /etc/default/inngest-server env-file
# materialization (the Redis unit reads it for the Doppler-injected password —
# the load-bearing ordering dependency) AND BEFORE the server-unit cat> (so the
# substitution can branch the ExecStart on it).
ENV_FILE_LINE=$(grep -nE 'cat > /etc/default/inngest-server <<DOPPLEREOF' "$BOOTSTRAP_SH" | head -1 | cut -d: -f1 || true)
REDIS_READY_LINE=$(grep -nE '^[[:space:]]*REDIS_READY=' "$BOOTSTRAP_SH" | head -1 | cut -d: -f1 || true)
SERVER_CAT_LINE=$(grep -nE 'cat > "\$UNIT_FILE" <<' "$BOOTSTRAP_SH" | head -1 | cut -d: -f1 || true)
TOTAL=$((TOTAL + 1))
if [[ -n "$ENV_FILE_LINE" && -n "$REDIS_READY_LINE" && -n "$SERVER_CAT_LINE" \
      && "$ENV_FILE_LINE" -lt "$REDIS_READY_LINE" && "$REDIS_READY_LINE" -lt "$SERVER_CAT_LINE" ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: REDIS_READY assigned after env-file materialization, before server-unit cat> (#5547 AC2)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: ordering env-file($ENV_FILE_LINE) < REDIS_READY($REDIS_READY_LINE) < server-cat($SERVER_CAT_LINE) (#5547 AC2)"
fi

# AC3 — the heredoc carries the @@BACKEND_FLAGS@@ sentinel on the inngest start
# line, --sqlite-dir /var/lib/inngest is in the SHARED prefix (present in BOTH
# branches), and a (non-sed) substitution strips the sentinel so none survives
# in the written unit.
SENTINEL_IN_HEREDOC=$(printf '%s\n' "$SERVER_UNIT_BLOCK" | grep -cE 'inngest start .*@@BACKEND_FLAGS@@' || true)
SQLITE_IN_HEREDOC=$(printf '%s\n' "$SERVER_UNIT_BLOCK" | grep -cF -- '--sqlite-dir /var/lib/inngest' || true)
SENTINEL_SUBST=$(grep -cE '@@BACKEND_FLAGS@@/' "$BOOTSTRAP_SH" || true)
TOTAL=$((TOTAL + 1))
if [[ "$SENTINEL_IN_HEREDOC" -ge 1 && "$SQLITE_IN_HEREDOC" -ge 1 && "$SENTINEL_SUBST" -ge 1 ]]; then
  PASS=$((PASS + 1))
  echo "  PASS: heredoc carries @@BACKEND_FLAGS@@ sentinel + --sqlite-dir shared prefix; substitution strips it (#5547 AC3)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: AC3 (sentinel_in_heredoc=$SENTINEL_IN_HEREDOC sqlite_shared=$SQLITE_IN_HEREDOC sentinel_subst=$SENTINEL_SUBST)"
fi

# Durable fragment (#5450 build-time guard, reconciled to the fragment shape —
# AC8). Both flags MUST be present; the session pooler MUST be :5432 (transaction
# :6543 breaks inngest's prepared statements — verdict 0.5).
DURABLE_FRAGMENT=$(grep -E "^[[:space:]]*BACKEND_FLAGS='--postgres-uri" "$BOOTSTRAP_SH" | head -1 || true)
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$DURABLE_FRAGMENT" | grep -qF -- '--postgres-uri' \
   && printf '%s\n' "$DURABLE_FRAGMENT" | grep -qF -- '--redis-uri "redis://:' \
   && printf '%s\n' "$DURABLE_FRAGMENT" | grep -qE -- '--postgres-max-open-conns [0-9]+' \
   && ! printf '%s\n' "$DURABLE_FRAGMENT" | grep -qF ':6543'; then
  PASS=$((PASS + 1))
  echo "  PASS: durable BACKEND_FLAGS fragment sets --postgres-uri + --redis-uri (loopback) + --postgres-max-open-conns, never :6543 (#5547 AC8/#5450)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: durable fragment shape (line: $DURABLE_FRAGMENT)"
fi

# AC4 — the durable fragment preserves the LITERAL $${INNGEST_*} Doppler tokens
# (systemd unescapes $$→$, then bash -c expands the doppler-injected env). grep -F
# single-quoted so the $$ is matched literally (never the shell PID).
TOTAL=$((TOTAL + 1))
if printf '%s\n' "$DURABLE_FRAGMENT" | grep -qF '$${INNGEST_POSTGRES_URI}' \
   && printf '%s\n' "$DURABLE_FRAGMENT" | grep -qF '$${INNGEST_REDIS_PASSWORD}'; then
  PASS=$((PASS + 1))
  echo "  PASS: durable fragment preserves literal \$\${INNGEST_POSTGRES_URI}/\$\${INNGEST_REDIS_PASSWORD} (#5547 AC4)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: durable fragment must preserve literal \$\${INNGEST_*} tokens (line: $DURABLE_FRAGMENT)"
fi

# SQLite-only fail-safe: an EMPTY fragment is assigned when Redis is not ready,
# so the written ExecStart omits --postgres-uri/--redis-uri and inngest stays
# available on SQLite (verify_inngest_health then SKIPs the durable gate).
TOTAL=$((TOTAL + 1))
if grep -qE "^[[:space:]]*BACKEND_FLAGS=(''|\"\")[[:space:]]*\$" "$BOOTSTRAP_SH"; then
  PASS=$((PASS + 1))
  echo "  PASS: SQLite-only fail-safe assigns an empty BACKEND_FLAGS when REDIS_READY=0 (#5547 AC3)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: missing empty BACKEND_FLAGS branch for the SQLite-only fail-safe (#5547)"
fi

# AC2: an ExecStart change must take effect on redeploy. Two guarantees:
#   (a) reconcile-always — the server unit write lives OUTSIDE the
#       SKIP_BINARY_INSTALL guard (so a same-CLI-version redeploy still
#       rewrites the unit), matching the heartbeat/Vector precedent; and
#   (b) explicit `systemctl restart inngest-server.service` (a running unit
#       ignores a new ExecStart until restart — the Vector enable→restart fix).
echo ""
echo "--- Inngest-server unit reconcile-always + restart (#4652 AC2) ---"
# shellcheck disable=SC2016
GUARD_CLOSE_LINE=$(grep -nE '^fi  # end SKIP_BINARY_INSTALL guard' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
# shellcheck disable=SC2016
SERVER_UNIT_WRITE_LINE=$(grep -nE 'cat > "\$UNIT_FILE" <<' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
assert "server unit write is OUTSIDE the SKIP_BINARY_INSTALL guard (reconcile-always)" \
  "[[ -n '$GUARD_CLOSE_LINE' && -n '$SERVER_UNIT_WRITE_LINE' && '$GUARD_CLOSE_LINE' -lt '$SERVER_UNIT_WRITE_LINE' ]]"
assert "bootstrap restarts inngest-server.service (new ExecStart loads on redeploy)" \
  "grep -qE '^systemctl restart inngest-server.service' '$BOOTSTRAP_SH'"
# The upgrade-drain resume must still run after the restart (R2 — restart must
# not orphan the pause/resume pairing). Match the actual resume COMMAND
# (`"$INSTALL_PATH" resume`) precisely — no broad `|| grep resume` fallback,
# which would vacuously pass on any comment line merely mentioning "resume".
assert "upgrade-drain resume command still present (pause/resume pairing intact)" \
  "grep -qE '\"\\\$INSTALL_PATH\" resume' '$BOOTSTRAP_SH'"

# --- Durable backend assets (#5450) ---
echo ""
echo "--- Durable backend: Redis assets + secrets (#5450) ---"
REDIS_CONF="$SCRIPT_DIR/inngest-redis.conf"
REDIS_SERVICE="$SCRIPT_DIR/inngest-redis.service"
REDIS_BOOTSTRAP="$SCRIPT_DIR/inngest-redis-bootstrap.sh"
assert "inngest-redis.conf exists"        "[[ -f '$REDIS_CONF' ]]"
assert "inngest-redis.service exists"     "[[ -f '$REDIS_SERVICE' ]]"
assert "inngest-redis-bootstrap.sh exists + executable" "[[ -x '$REDIS_BOOTSTRAP' ]]"
# redis.conf required durability settings (AC).
assert "redis.conf appendonly yes"        "grep -qE '^appendonly yes' '$REDIS_CONF'"
assert "redis.conf appendfsync everysec"  "grep -qE '^appendfsync everysec' '$REDIS_CONF'"
assert "redis.conf maxmemory-policy noeviction" "grep -qE '^maxmemory-policy noeviction' '$REDIS_CONF'"
assert "redis.conf bounds maxmemory"      "grep -qE '^maxmemory [0-9]' '$REDIS_CONF'"
assert "redis.conf bounds AOF rewrite"    "grep -qE '^auto-aof-rewrite-percentage' '$REDIS_CONF' && grep -qE '^auto-aof-rewrite-min-size' '$REDIS_CONF'"
assert "redis.conf dir on /mnt/data"      "grep -qE '^dir /mnt/data/redis' '$REDIS_CONF'"
assert "redis.conf loopback bind"         "grep -qE '^bind 127.0.0.1' '$REDIS_CONF'"
# The unit MUST pin to the persistent mount (architecture P1-2) + inject the
# password via doppler (never a literal in the file).
assert "redis.service RequiresMountsFor=/mnt/data" "grep -qE '^RequiresMountsFor=/mnt/data' '$REDIS_SERVICE'"
assert "redis.service requirepass injected from Doppler" "grep -qF 'requirepass \"\$INNGEST_REDIS_PASSWORD\"' '$REDIS_SERVICE'"
assert "redis.service runs under doppler run prd" "grep -qE 'doppler run --project soleur --config prd' '$REDIS_SERVICE'"
# #5450 F1 regression guard: the conf MUST live under /mnt/data/redis, NOT
# /etc/redis — on the existing-host deploy the bootstrap runs inside
# webhook.service's ProtectSystem=strict namespace where /etc is read-only and
# only ReadWritePaths (incl. /mnt/data) are writable. A conf install to
# /etc/redis fails-closed at cutover. Lock both the unit's read path and the
# bootstrap's write path to /mnt/data/redis.
assert "redis.service reads conf from /mnt/data/redis (not /etc/redis)" \
  "grep -qF '/mnt/data/redis/inngest-redis.conf' '$REDIS_SERVICE' && ! grep -qF '/etc/redis' '$REDIS_SERVICE'"
assert "redis-bootstrap installs conf under /mnt/data (never /etc/redis)" \
  "grep -qF '\$REDIS_DATA_DIR/inngest-redis.conf' '$REDIS_BOOTSTRAP' && ! grep -qE 'install .* /etc/redis' '$REDIS_BOOTSTRAP'"
assert "inngest-bootstrap does not write the conf into /etc/redis (namespace trap)" \
  "! grep -qE 'install .* /etc/redis|mkdir -p /etc/redis' '$BOOTSTRAP_SH'"
# Secrets: random_password (not operator-mint) + doppler_secret.
assert "random_password.inngest_redis_password_prd" "grep -qE 'resource \"random_password\" \"inngest_redis_password_prd\"' '$INNGEST_TF'"
assert "INNGEST_REDIS_PASSWORD doppler_secret"      "grep -qE 'name[[:space:]]+= \"INNGEST_REDIS_PASSWORD\"' '$INNGEST_TF'"
# inngest-bootstrap runs the redis bootstrap (the REDIS_READY probe) BEFORE the
# inngest-server restart (the ExecStart is branched on REDIS_READY). Anchor on
# the INVOCATION line (`if /usr/local/bin/inngest-redis-bootstrap.sh; then`), not
# the `install …` line — after the #5547 reorder the install line still ends in
# `inngest-redis-bootstrap.sh` and a `$`-anchored `tail -1` could pick it; the
# invocation is the line whose ordering vs the restart actually matters.
REDIS_RUN_LINE=$(grep -nE 'if /usr/local/bin/inngest-redis-bootstrap.sh; then' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
RESTART_LINE=$(grep -nE '^systemctl restart inngest-server.service' "$BOOTSTRAP_SH" 2>/dev/null | head -1 | cut -d: -f1 || true)
assert "bootstrap runs inngest-redis-bootstrap.sh (REDIS_READY probe) BEFORE the inngest-server restart" \
  "[[ -n '$REDIS_RUN_LINE' && -n '$RESTART_LINE' && '$REDIS_RUN_LINE' -lt '$RESTART_LINE' ]]"

# --- `terraform fmt -check` for HCL hygiene ---
echo ""
echo "--- terraform fmt -check ---"
if command -v terraform >/dev/null 2>&1; then
  if (cd "$SCRIPT_DIR" && terraform fmt -check -diff=false inngest.tf >/dev/null 2>&1); then
    PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1))
    echo "  PASS: inngest.tf is properly formatted"
  else
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
    echo "  FAIL: inngest.tf needs 'terraform fmt' (run: terraform fmt apps/web-platform/infra/inngest.tf)"
  fi
else
  echo "  SKIP: terraform not installed locally"
fi

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
