#!/usr/bin/env bash
# Drift-guard for terraform_data.infra_config_handler_bootstrap (#4811, Ref #4804).
#
# The bug this resource fixes: infra-config-apply.sh (the /hooks/infra-config
# webhook handler) had NO deploy path to a running host. It reaches the host only
# via (1) cloud-init write_files — dead on the existing host because
# hcloud_server.web carries ignore_changes=[user_data] — and (2) the
# deploy_pipeline_fix triggers_replace hash, which re-fires push-infra-config.sh,
# which pushes the OTHER 7 files but NOT the handler itself (the handler is not in
# push-infra-config.sh's payload nor in its own FILE_MAP). Net: a handler/hooks.json
# drift on the host was unrecoverable through the webhook path, because the recovery
# itself routes through the stale handler.
#
# The fix is a dedicated SSH terraform_data bootstrap resource that delivers
# infra-config-apply.sh + cat-infra-config-state.sh + the rendered hooks.json
# directly to the running host over SSH (independent of the on-host handler),
# mirroring the 7 existing SSH-provisioner siblings (closest precedent:
# journald_persistent).
#
# Static grep + AWK only — no docker/terraform/SSH required (the convention every
# sibling .test.sh follows, e.g. journald-config.test.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"
HANDLER="$SCRIPT_DIR/infra-config-apply.sh"
STATE_SCRIPT="$SCRIPT_DIR/cat-infra-config-state.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INFRA_VALIDATION="$REPO_ROOT/.github/workflows/infra-validation.yml"

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

echo "=== infra-config-handler-bootstrap (#4811) drift-guard ==="
echo ""

# --- File existence ---
echo "--- File existence ---"
assert "server.tf exists"                    "[[ -f '$SERVER_TF' ]]"
assert "infra-config-apply.sh exists"        "[[ -f '$HANDLER' ]]"
assert "cat-infra-config-state.sh exists"    "[[ -f '$STATE_SCRIPT' ]]"

# --- AC1: resource declared ---
echo ""
echo "--- AC1: terraform_data.infra_config_handler_bootstrap declared ---"
assert "resource declared" \
  "grep -qE 'resource \"terraform_data\" \"infra_config_handler_bootstrap\"' '$SERVER_TF'"

# Extract the resource block (from its declaration to the next column-0 `}`) so
# all subsequent assertions are scoped to it. Relies on `terraform fmt` canonical
# indentation: every nested block's closing brace is indented, so the first
# column-0 `}` is the resource terminator (fmt is gated in infra-validation.yml).
# shellcheck disable=SC2034  # consumed via `eval "$condition"` in assert()
BLOCK=$(awk '
  /^resource "terraform_data" "infra_config_handler_bootstrap"/ { f=1 }
  f { print }
  f && /^}/ { exit }
' "$SERVER_TF")
assert "block is non-empty" "[[ -n \"\$BLOCK\" ]]"

# --- AC2: SSH connection block (the 7-sibling shape) ---
echo ""
echo "--- AC2: SSH connection block matches the 7-sibling shape ---"
assert "SSH connection block (type = ssh)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'type[[:space:]]*=[[:space:]]*\"ssh\"'"
assert "connection host = hcloud_server.web[\"web-1\"].ipv4_address" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'host[[:space:]]*=[[:space:]]*hcloud_server\.web\[\"web-1\"\]\.ipv4_address'"
assert "connection user = root" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'user[[:space:]]*=[[:space:]]*\"root\"'"
# `agent = true` was stale post-#4845: server.tf now uses the dual-context
# toggle `agent = var.ci_ssh_private_key == null` (operator ssh-agent locally,
# explicit Doppler key in CI). The literal-`true` regex previously false-passed
# by matching this block's #4829 dual-context comment prose, not real config;
# the conditional regex below matches only the real `agent = var…` line.
assert "connection uses the dual-context ssh-agent toggle agent = var.ci_ssh_private_key == null" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key[[:space:]]*==[[:space:]]*null'"

# --- AC3: triggers_replace references all three trigger inputs ---
echo ""
echo "--- AC3: triggers_replace complete (handler + status script + hooks.json) ---"
assert "triggers_replace uses the sha256(join(...)) wrapper" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'triggers_replace[[:space:]]*=[[:space:]]*sha256\(join\('"
assert "triggers_replace references infra-config-apply.sh" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'file\(\"\\\$\{path\.module\}/infra-config-apply\.sh\"\)'"
assert "triggers_replace references cat-infra-config-state.sh" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'file\(\"\\\$\{path\.module\}/cat-infra-config-state\.sh\"\)'"
assert "triggers_replace references local.hooks_json" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'local\.hooks_json'"

# --- AC4: handler delivered (the load-bearing anti-regression invariant) ---
echo ""
echo "--- AC4: resource DELIVERS the handler via provisioner \"file\" ---"
# This is the file deploy_pipeline_fix CANNOT deliver. The delivery must be
# anchored to the provisioner "file" source/destination PAIR, NOT the bare path
# — the path string also appears in the chown/chmod/test-x lifecycle lines, so a
# bare-path grep would stay green even if the `provisioner "file"` delivery block
# were deleted (the exact regression this test exists to catch). Assert both the
# destination (only ever on the scp block) AND the path.module source.
assert "file provisioner delivers infra-config-apply.sh to /usr/local/bin (destination)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'destination[[:space:]]*=[[:space:]]*\"/usr/local/bin/infra-config-apply\.sh\"'"
assert "file provisioner sources infra-config-apply.sh from path.module" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'source[[:space:]]*=[[:space:]]*\"\\\$\{path\.module\}/infra-config-apply\.sh\"'"
assert "file provisioner delivers cat-infra-config-state.sh to /usr/local/bin (destination)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'destination[[:space:]]*=[[:space:]]*\"/usr/local/bin/cat-infra-config-state\.sh\"'"
assert "file provisioner sources cat-infra-config-state.sh from path.module" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'source[[:space:]]*=[[:space:]]*\"\\\$\{path\.module\}/cat-infra-config-state\.sh\"'"
assert "resource writes /etc/webhook/hooks.json" \
  "printf '%s' \"\$BLOCK\" | grep -qE '/etc/webhook/hooks\.json'"
# hooks.json is a secret-bearing templatefile() render (not on disk), so it must
# be delivered via a base64 heredoc, not a provisioner \"file\" source.
assert "hooks.json delivered via base64encode(local.hooks_json) heredoc" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'base64encode\(local\.hooks_json\)'"

# --- AC5: positive post-write assertions (prove it took, don't observe it) ---
echo ""
echo "--- AC5: positive assertions in remote-exec ---"
assert "asserts hooks.json re-registers infra-config-status hook" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'infra-config-status'"
assert "asserts hooks.json maps cat_infra_config_state_sh_b64 key" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'cat_infra_config_state_sh_b64'"
assert "asserts the webhook unit is active (is-active)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'systemctl is-active webhook'"

# --- AC7: #4827 — bridge also bootstraps the escalation helper + sudoers grant ---
# The webhook handler's prod-mode escalation needs BOTH infra-config-install AND
# the INFRA_CONFIG_INSTALL sudoers alias present before `sudo infra-config-install`
# is permitted, and it cannot deliver either itself (the helper is OUT of FILE_MAP;
# writing the sudoers requires the alias). Root SSH is the only non-circular
# bootstrap — these assertions pin that delivery so it cannot silently regress.
echo ""
echo "--- AC7: escalation helper + sudoers delivered over root SSH (#4827) ---"
assert "triggers_replace references infra-config-install.sh" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'file\(\"\\\$\{path\.module\}/infra-config-install\.sh\"\)'"
assert "triggers_replace references deploy-inngest-bootstrap.sudoers" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'file\(\"\\\$\{path\.module\}/deploy-inngest-bootstrap\.sudoers\"\)'"
assert "file provisioner delivers infra-config-install (destination)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'destination[[:space:]]*=[[:space:]]*\"/usr/local/bin/infra-config-install\"'"
assert "file provisioner sources infra-config-install.sh from path.module" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'source[[:space:]]*=[[:space:]]*\"\\\$\{path\.module\}/infra-config-install\.sh\"'"
assert "file provisioner sources the sudoers grant from path.module" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'source[[:space:]]*=[[:space:]]*\"\\\$\{path\.module\}/deploy-inngest-bootstrap\.sudoers\"'"
assert "remote-exec visudo-validates the staged sudoers before install" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'visudo -cf /tmp/deploy-inngest-bootstrap\.sudoers\.staged'"
assert "remote-exec atomically installs the sudoers grant root:root 0440" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'install -o root -g root -m 0440 /tmp/deploy-inngest-bootstrap\.sudoers\.staged /etc/sudoers\.d/deploy-inngest-bootstrap'"
assert "remote-exec asserts the helper is executable (test -x)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'test -x /usr/local/bin/infra-config-install'"
assert "remote-exec asserts the INFRA_CONFIG_INSTALL grant landed" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'grep -q INFRA_CONFIG_INSTALL /etc/sudoers\.d/deploy-inngest-bootstrap'"

# --- AC6: wired into CI (infra-validation.yml) ---
echo ""
echo "--- AC6: drift-guard wired into infra-validation.yml ---"
assert "infra-validation.yml exists" "[[ -f '$INFRA_VALIDATION' ]]"
assert "infra-validation.yml invokes this drift-guard" \
  "grep -qE 'bash apps/web-platform/infra/infra-config-handler-bootstrap\.test\.sh' '$INFRA_VALIDATION'"

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
