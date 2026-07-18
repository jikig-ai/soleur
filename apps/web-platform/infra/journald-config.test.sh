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

# --- AC2: fresh-host parity via the baked host-scripts set (#5921) ---
# The journald drop-in used to be an inline cloud-init write_files: base64 blob, but that
# was the biggest remaining user_data expansion (2.4 KB) and #5921 moved it into the baked
# /opt/soleur/host-scripts/ set: server.tf.local.host_script_files bakes journald-soleur.conf,
# the Dockerfile COPYs it, and soleur-host-bootstrap.sh installs + applies it at boot. Assert
# that delivery path (the inline write_files entry MUST be gone — else user_data re-bloats).
echo ""
echo "--- AC2: fresh-host delivery via baked host-scripts (#5921) ---"
BOOTSTRAP="$SCRIPT_DIR/soleur-host-bootstrap.sh"
assert "journald drop-in is NOT an inline cloud-init write_files entry anymore" \
  "! grep -qE '^[[:space:]]+- path: /etc/systemd/journald\.conf\.d/00-soleur\.conf' '$CLOUD_INIT'"
assert "journald_soleur_conf_b64 is NOT re-inlined in cloud-init" \
  "! grep -qE 'content: \\\$\{journald_soleur_conf_b64\}' '$CLOUD_INIT'"
assert "journald-soleur.conf is in server.tf host_script_files (baked set)" \
  "awk '/host_script_files = \[/,/^  \]/' '$SERVER_TF' | grep -qE '\"journald-soleur\.conf\"'"
assert "Dockerfile bakes journald-soleur.conf into /opt/soleur/host-scripts/" \
  "grep -qE '/app/infra/journald-soleur\.conf' '$SCRIPT_DIR/../Dockerfile'"
assert "bootstrap installs the drop-in to /etc/systemd/journald.conf.d/00-soleur.conf" \
  "grep -qE 'install -D -m 0644 .* /etc/systemd/journald\.conf\.d/00-soleur\.conf' '$BOOTSTRAP'"
assert "bootstrap applies journald persistence (restart + flush)" \
  "grep -q 'systemctl restart systemd-journald' '$BOOTSTRAP' && grep -q 'journalctl --flush' '$BOOTSTRAP'"

# --- AC3: server.tf wires the running-host SSH provisioner (unchanged by #5921) ---
echo ""
echo "--- AC3: server.tf provisioner wiring (running-host path) ---"
# #5921: journald_soleur_conf_b64 was REMOVED from the cloud-init templatefile map (baked
# instead); the running-host delivery via terraform_data.journald_persistent is unchanged.
assert "journald_soleur_conf_b64 is NOT passed to the cloud-init templatefile" \
  "! awk '/user_data = templatefile\(\"\\\$\{path.module\}\/cloud-init.yml\"/,/^  \}\)/' '$SERVER_TF' | grep -qE 'journald_soleur_conf_b64'"
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
assert "triggers_replace hashes journald-soleur.conf (re-delivery on drop-in change; now a join with vector.toml)" \
  "printf '%s' \"\$BLOCK\" | grep -qE 'file\(\"\\\$\{path\.module\}/journald-soleur\.conf\"\)'"
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
echo "--- AC5: journald-persistence runs (in the bootstrap) before the container start ---"
# #5921: journald persistence (mkdir /var/log/journal + tmpfiles + restart + flush) moved
# from an inline cloud-init runcmd step into soleur-host-bootstrap.sh, which the extraction
# launcher runs BEFORE the terminal --log-driver journald container. Assert the bootstrap
# carries the persistence steps AND that the extraction launcher precedes the container start.
assert "bootstrap sets up journald persistence (mkdir + tmpfiles + restart + flush)" \
  "grep -q 'mkdir -p /var/log/journal' '$BOOTSTRAP' && grep -q 'systemd-tmpfiles --create --prefix /var/log/journal' '$BOOTSTRAP' && grep -q 'systemctl restart systemd-journald' '$BOOTSTRAP' && grep -q 'journalctl --flush' '$BOOTSTRAP'"
EXTRACT_LINE=$(grep -nE 'BEGIN host-script extraction' "$CLOUD_INIT" | head -1 | cut -d: -f1)
WEBPLATFORM_LINE=$(grep -nE '^[[:space:]]+--name soleur-web-platform' "$CLOUD_INIT" | head -1 | cut -d: -f1)
assert "host-script extraction (runs the bootstrap) found" "[[ -n '$EXTRACT_LINE' ]]"
assert "soleur-web-platform container-start found"          "[[ -n '$WEBPLATFORM_LINE' ]]"
assert "the bootstrap runs BEFORE the container starts" \
  "(( EXTRACT_LINE < WEBPLATFORM_LINE ))"

# --- AC6: cloud-init.yml still parses as valid YAML (templatefile directives stripped) ---
# #6178: cloud-init.yml carries col-0 `%{ if web_colocate_inngest ~}` / `%{ endif ~}`
# templatefile directives (YAML rejects `%` at column 0 as a directive indicator). Strip
# them before parsing the NON-rendered source — same fix as cloud-init-inngest-bootstrap.test.sh
# AC3. Rendered-state YAML validity is asserted in that file's terraform-render leg.
echo ""
echo "--- AC6: cloud-init.yml YAML round-trip (directives stripped) ---"
assert "cloud-init.yml (templatefile directives stripped) parses as valid YAML" \
  "grep -v '^%{' '$CLOUD_INIT' | python3 -c \"import sys,yaml; yaml.safe_load(sys.stdin)\""

# --- AC7: cat-deploy-state.sh exposes journald_storage (no-SSH verification) ---
echo ""
echo "--- AC7: cat-deploy-state.sh journald_storage field (no-SSH post-apply check) ---"
CAT_STATE="$SCRIPT_DIR/cat-deploy-state.sh"
assert "cat-deploy-state.sh exists" "[[ -f '$CAT_STATE' ]]"
assert "cat-deploy-state.sh emits a journald_storage field" \
  "grep -qE 'journald_storage' '$CAT_STATE'"
assert "cat-deploy-state.sh is bash -n clean" \
  "bash -n '$CAT_STATE'"

# --- vector.toml delivery folded into journald_persistent (#6438/#6548 Source-4 delivery) ---
# web-1 installs vector ONLY at cloud-init boot and never re-runs cloud-init (ignore_changes=
# [user_data]), so vector.toml's Source-4 probe SyslogIdentifiers were file-only, never live on
# the running host — the 3 probes' own FATAL stderr never reached Better Stack. The sole live-prod
# apply path is a terraform_data SSH provisioner; fold the vector.toml re-delivery + agent reload
# into journald_persistent (already SSHes web-1, already on the workflow -target list). Assert the
# wiring is present AND that triggers_replace hashes vector.toml (else the re-delivery never fires
# — the "plan unchanged defers the real test to prod" trap).
echo ""
echo "--- vector.toml delivery folded into journald_persistent (Source 4 live on web-1) ---"
JP="$(awk '/resource \"terraform_data\" \"journald_persistent\"/,/^}/' "$SERVER_TF")"
# Anchor on the actual delivery CONSTRUCT (install to the live /etc/vector path + the staging file
# provisioner), NOT a bare 'vector.toml' token — the block's header comments mention vector.toml, so a
# bare grep passes on comment text alone even if the delivery were deleted (test-design + pattern review).
assert "journald_persistent delivers vector.toml to the live /etc/vector on web-1 (install construct)" \
  "grep -qE 'install -m 0644 .*/etc/vector/vector.toml' <<<\"\$JP\""
assert "journald_persistent stages vector.toml via a file provisioner" \
  "grep -qE 'destination[[:space:]]*=[[:space:]]*\"/tmp/soleur-vector.toml.staged\"' <<<\"\$JP\""
assert "journald_persistent triggers_replace hashes file(vector.toml) (re-delivery on config change)" \
  "grep -qE 'file\\(\"\\\$\\{path.module\\}/vector.toml\"\\)' <<<\"\$JP\""
assert "journald_persistent reloads the vector agent (restart vector.service)" \
  "grep -qE 'systemctl.*vector.service|restart vector' <<<\"\$JP\""
# Scope the identifier check to the [sources.host_scripts_journald] BLOCK (the Source 4 include list),
# not the whole file — a name relocated into a comment / exclude / other sink would defeat a file-wide
# grep while breaking Source-4 delivery (test-design + pattern review).
HSJ="$(awk '/^\[sources\.host_scripts_journald\]/{f=1;next} f&&/^\[[a-z]/{f=0} f' "$SCRIPT_DIR/vector.toml")"
assert "Source 4 (host_scripts_journald) include list carries all 3 probe SyslogIdentifiers" \
  "grep -q 'web-zot-consumer-probe' <<<\"\$HSJ\" && grep -q 'web-git-data-probe' <<<\"\$HSJ\" && grep -q 'web-nic-guard' <<<\"\$HSJ\""

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
