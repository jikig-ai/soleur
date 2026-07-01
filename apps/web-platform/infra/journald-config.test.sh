#!/usr/bin/env bash
# Tests the persistent + bounded journald storage feature added in #4792
# (#4773 follow-up — the soleur-web-platform container moved to
# `--log-driver journald`, so the host journal must be persistent + sized).
#
# Three coupled parts, all asserted structurally here (no host/docker needed):
#   1. journald-soleur.conf  — the source-of-truth drop-in (Storage=persistent +
#      SystemMaxUse/SystemKeepFree/RuntimeMaxUse caps under [Journal]).
#   2. cloud-init.yml — fresh-host parity: a write_files entry that renders the
#      drop-in at /etc/systemd/journald.conf.d/00-soleur.conf via the
#      `${journald_soleur_conf_b64}` templatefile var (byte-identical by
#      construction — same file() both paths read), AND a runcmd step that
#      creates /var/log/journal + restarts/flushes journald BEFORE the
#      soleur-web-platform container starts.
#   3. server.tf — terraform_data.journald_persistent: the sole apply path to
#      the already-running host (server.tf carries ignore_changes=[user_data],
#      so a cloud-init-only edit never reaches live prod). SSH connection +
#      triggers_replace = sha256(file(drop-in)) + file provisioner +
#      remote-exec with create-dir → restart → flush → positive assertions.
#
# Byte-parity strategy: BOTH the cloud-init write_files entry and the server.tf
# file provisioner derive from the same journald-soleur.conf via file()/
# base64encode(file()), exactly like the fail2ban-sshd.local two-path pattern
# (server.tf fail2ban_tuning + cloud-init b64 entry). So parity is guaranteed at
# render time; the test asserts the WIRING (both paths reference the one file)
# rather than diffing two hand-maintained copies.
#
# Static grep + AWK + python3 yaml only — no docker/terraform required.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"
SERVER_TF="$SCRIPT_DIR/server.tf"
DROPIN="$SCRIPT_DIR/journald-soleur.conf"

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

echo "=== journald persistent-storage (#4792) tests ==="
echo ""

# --- File existence ---
echo "--- File existence ---"
assert "journald-soleur.conf exists" "[[ -f '$DROPIN' ]]"
assert "cloud-init.yml exists"       "[[ -f '$CLOUD_INIT' ]]"
assert "server.tf exists"            "[[ -f '$SERVER_TF' ]]"

# --- AC1: drop-in content (the load-bearing sizing config) ---
echo ""
echo "--- AC1: journald-soleur.conf [Journal] section + caps ---"
assert "drop-in declares [Journal] section" \
  "grep -qE '^\[Journal\]' '$DROPIN'"
assert "Storage=persistent" \
  "grep -qE '^Storage=persistent$' '$DROPIN'"
assert "SystemMaxUse=1G" \
  "grep -qE '^SystemMaxUse=1G$' '$DROPIN'"
assert "SystemKeepFree=2G (load-bearing hard floor)" \
  "grep -qE '^SystemKeepFree=2G$' '$DROPIN'"
assert "RuntimeMaxUse=200M" \
  "grep -qE '^RuntimeMaxUse=200M$' '$DROPIN'"

# --- AC2: cloud-init write_files renders the drop-in (fresh-host parity) ---
echo ""
echo "--- AC2: cloud-init write_files entry for the drop-in ---"
assert "write_files targets /etc/systemd/journald.conf.d/00-soleur.conf" \
  "grep -qE '^[[:space:]]+- path: /etc/systemd/journald\.conf\.d/00-soleur\.conf' '$CLOUD_INIT'"
# b64 templatefile var = byte-identical by construction (same file() the .tf
# provisioner pushes raw). Asserting the var reference proves the parity wiring.
assert "drop-in content sourced from \${journald_soleur_conf_b64} (byte-parity by construction)" \
  "grep -qE 'content: \\\$\{journald_soleur_conf_b64\}' '$CLOUD_INIT'"
assert "drop-in entry is b64-encoded" \
  "awk '/path: \/etc\/systemd\/journald\.conf\.d\/00-soleur\.conf/{f=1} f&&/encoding: b64/{print; exit}' '$CLOUD_INIT' | grep -q 'encoding: b64'"

# --- AC3: server.tf wires base64encode(file(drop-in)) into the templatefile ---
echo ""
echo "--- AC3: server.tf templatefile + provisioner wiring ---"
assert "templatefile passes journald_soleur_conf_b64 = base64encode(file(...))" \
  "grep -qE 'journald_soleur_conf_b64[[:space:]]*=[[:space:]]*base64encode\(file\(\"\\\$\{path\.module\}/journald-soleur\.conf\"\)\)' '$SERVER_TF'"
assert "terraform_data.journald_persistent resource declared" \
  "grep -qE 'resource \"terraform_data\" \"journald_persistent\"' '$SERVER_TF'"

# --- AC4: terraform_data.journald_persistent block shape ---
echo ""
echo "--- AC4: journald_persistent provisioner shape (SSH + triggers + file + remote-exec) ---"
# Extract the resource block (from its declaration to the next top-level
# `resource`/`locals`/`}` at column 0) so assertions are scoped to it.
# shellcheck disable=SC2034  # consumed via `eval "$condition"` in assert()
BLOCK=$(awk '
  /^resource "terraform_data" "journald_persistent"/ { f=1 }
  f { print }
  f && /^}/ { exit }
' "$SERVER_TF")
assert "block is non-empty" "[[ -n \"\$BLOCK\" ]]"
assert "triggers_replace = sha256(file(journald-soleur.conf))" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'triggers_replace[[:space:]]*=[[:space:]]*sha256\(file\(\"\\\$\{path\.module\}/journald-soleur\.conf\"\)\)'"
assert "SSH connection block (type=ssh)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'type[[:space:]]*=[[:space:]]*\"ssh\"'"
# `agent = true` was stale post-#4845: server.tf now uses the dual-context
# toggle `agent = var.ci_ssh_private_key == null` (operator ssh-agent locally,
# explicit Doppler key in CI). The conditional regex below cannot false-match
# the #4829 dual-context comment (which reads literal `agent = true`).
assert "connection uses the dual-context ssh-agent toggle agent = var.ci_ssh_private_key == null" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key[[:space:]]*==[[:space:]]*null'"
assert "connection host = hcloud_server.web[\"web-1\"].ipv4_address" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'host[[:space:]]*=[[:space:]]*hcloud_server\.web\[\"web-1\"\]\.ipv4_address'"
assert "file provisioner pushes drop-in to /etc/systemd/journald.conf.d/00-soleur.conf" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'destination[[:space:]]*=[[:space:]]*\"/etc/systemd/journald\.conf\.d/00-soleur\.conf\"'"
# The drop-in dir is NOT created by default on Ubuntu and scp won't create
# parents — a preceding remote-exec mkdir is load-bearing or the first apply
# fails. (Regression guard for the review P1.)
assert "remote-exec creates the drop-in dir before the file provisioner pushes into it" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'mkdir -p /etc/systemd/journald\.conf\.d'"
assert "remote-exec creates /var/log/journal" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'mkdir -p /var/log/journal'"
assert "remote-exec restarts systemd-journald" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'systemctl restart systemd-journald'"
assert "remote-exec flushes the journal" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'journalctl --flush'"
# Positive post-assertions (fail2ban_tuning pattern): prove persistence took,
# don't just observe it.
assert "remote-exec positively asserts /var/log/journal exists" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'test -d /var/log/journal'"
assert "remote-exec asserts persistent storage via journalctl --header" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'journalctl --header'"

# --- AC5: runcmd creates /var/log/journal BEFORE the container starts ---
echo ""
echo "--- AC5: runcmd journald-persistence step ordered before container start ---"
JOURNALD_RUNCMD_LINE=$(grep -nE '^[[:space:]]+- (mkdir -p /var/log/journal|systemd-tmpfiles --create --prefix /var/log/journal)' "$CLOUD_INIT" | head -1 | cut -d: -f1)
# Match the runcmd container-start invocation (`--name soleur-web-platform`),
# NOT the write_files webhook.service ExecStart references.
WEBPLATFORM_LINE=$(grep -nE '^[[:space:]]+--name soleur-web-platform' "$CLOUD_INIT" | head -1 | cut -d: -f1)
assert "runcmd journald-persistence step found"     "[[ -n '$JOURNALD_RUNCMD_LINE' ]]"
assert "soleur-web-platform container-start found"   "[[ -n '$WEBPLATFORM_LINE' ]]"
assert "journald persistence is set up BEFORE the container starts" \
  "(( JOURNALD_RUNCMD_LINE < WEBPLATFORM_LINE ))"
assert "runcmd restarts systemd-journald" \
  "grep -qE '^[[:space:]]+- systemctl restart systemd-journald' '$CLOUD_INIT'"

# --- AC6: cloud-init.yml still parses as valid YAML ---
echo ""
echo "--- AC6: cloud-init.yml YAML round-trip ---"
assert "cloud-init.yml parses as valid YAML" \
  "python3 -c \"import yaml; yaml.safe_load(open('$CLOUD_INIT'))\""

# --- AC7: cat-deploy-state.sh exposes journald_storage (no-SSH verification) ---
echo ""
echo "--- AC7: cat-deploy-state.sh journald_storage field (no-SSH post-apply check) ---"
CAT_STATE="$SCRIPT_DIR/cat-deploy-state.sh"
assert "cat-deploy-state.sh exists" "[[ -f '$CAT_STATE' ]]"
assert "cat-deploy-state.sh emits a journald_storage field" \
  "grep -qE 'journald_storage' '$CAT_STATE'"
assert "cat-deploy-state.sh is bash -n clean" \
  "bash -n '$CAT_STATE'"

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
