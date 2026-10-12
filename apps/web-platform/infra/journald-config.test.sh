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
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
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
# grep -cE (reads ALL input) not grep -qE (closes the pipe on first match): the awk range now
# streams ~90 lines and "journald-soleur.conf" matches EARLY (line ~34), so grep -q would SIGPIPE
# the still-streaming awk and — under this file's `set -o pipefail` — flake the pipeline non-zero
# even on a match (2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards; #6459 P2.2
# widened the baked set past the match, tipping this latent flake). `>/dev/null` drops -c's count.
assert "journald-soleur.conf is in server.tf host_script_files (baked set)" \
  "awk '/host_script_files = \[/,/^  \]/' '$SERVER_TF' | grep -cE '\"journald-soleur\.conf\"' >/dev/null"
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
# grep -cE not grep -qE (same SIGPIPE-under-pipefail class as above): this NEGATIVE assert would
# fail OPEN if the b64 arg were ever re-inlined — grep -q matches early, SIGPIPEs the streaming awk,
# the pipeline flakes non-zero, and `!` inverts that into a spurious PASS, masking the regression.
# printf|grep -c|>/dev/null, not printf|grep -q: grep -c reads all input (no early close) so the `!` reflects the real match state.
# drops the count so the `!` sees only the exit code.
assert "journald_soleur_conf_b64 is NOT passed to the cloud-init templatefile" \
  "! { awk '/user_data = templatefile\(\"\\\$\{path.module\}\/cloud-init.yml\"/,/^  \}\)/' '$SERVER_TF' | grep -cE 'journald_soleur_conf_b64' >/dev/null; }"
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
  "grep -qE 'file\(\"\\\$\{path\.module\}/journald-soleur\.conf\"\)' <<<\"\$BLOCK\""
assert "SSH connection block (type=ssh)" \
  "grep -qE 'type[[:space:]]*=[[:space:]]*\"ssh\"' <<<\"\$BLOCK\""
# `agent = true` was stale post-#4845: server.tf now uses the dual-context
# toggle `agent = var.ci_ssh_private_key == null` (operator ssh-agent locally,
# explicit Doppler key in CI). The conditional regex below cannot false-match
# the #4829 dual-context comment (which reads literal `agent = true`).
assert "connection uses the dual-context ssh-agent toggle agent = var.ci_ssh_private_key == null" \
  "grep -qE 'agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key[[:space:]]*==[[:space:]]*null' <<<\"\$BLOCK\""
assert "connection host = hcloud_server.web[\"web-1\"].ipv4_address" \
  "grep -qE 'host[[:space:]]*=[[:space:]]*hcloud_server\.web\[\"web-1\"\]\.ipv4_address' <<<\"\$BLOCK\""
assert "file provisioner pushes drop-in to /etc/systemd/journald.conf.d/00-soleur.conf" \
  "grep -qE 'destination[[:space:]]*=[[:space:]]*\"/etc/systemd/journald\.conf\.d/00-soleur\.conf\"' <<<\"\$BLOCK\""
# The drop-in dir is NOT created by default on Ubuntu and scp won't create
# parents — a preceding remote-exec mkdir is load-bearing or the first apply
# fails. (Regression guard for the review P1.)
assert "remote-exec creates the drop-in dir before the file provisioner pushes into it" \
  "grep -qE 'mkdir -p /etc/systemd/journald\.conf\.d' <<<\"\$BLOCK\""
assert "remote-exec creates /var/log/journal" \
  "grep -qE 'mkdir -p /var/log/journal' <<<\"\$BLOCK\""
assert "remote-exec restarts systemd-journald" \
  "grep -qE 'systemctl restart systemd-journald' <<<\"\$BLOCK\""
assert "remote-exec flushes the journal" \
  "grep -qE 'journalctl --flush' <<<\"\$BLOCK\""
# Positive post-assertions (fail2ban_tuning pattern): prove persistence took,
# don't just observe it.
assert "remote-exec positively asserts /var/log/journal exists" \
  "grep -qE 'test -d /var/log/journal' <<<\"\$BLOCK\""
assert "remote-exec asserts persistent storage via journalctl --header" \
  "grep -qE 'journalctl --header' <<<\"\$BLOCK\""

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

# --- P3-6: /var/log/journal must exist on EVERY host whose vector.toml reads it -------------
# All four vector.toml journald sources hardcode journal_directory = "/var/log/journal", a
# PERSISTENT journal. journald_persistent creates it — but its connection block targets
# hcloud_server.web["web-1"] ONLY. The inngest host has no such provisioner and gets the
# directory purely by OS-image accident; an image shipping Storage=volatile would make every
# journald source on that host silently read nothing, taking the #6617a liveness probe dark
# through the very channel it was built to light up. First pin the premise, then the fix.
assert "P3-6 premise: journald_persistent's provisioner targets web-1 ONLY (not the inngest host)" \
  "grep -qE 'hcloud_server\\.web\\[\"web-1\"\\]\\.ipv4_address' <<<\"\$JP\" && ! grep -q 'inngest' <<<\"\$(grep -E \"host[[:space:]]*=\" <<<\"\$JP\")\""
assert "P3-6 premise: every vector.toml journald source hardcodes journal_directory=/var/log/journal" \
  "[[ \$(grep -cE '^journal_directory[[:space:]]*=[[:space:]]*\"/var/log/journal\"' '$SCRIPT_DIR/vector.toml') -ge 1 ]]"
# The fix: the inngest boot path creates the directory itself instead of inheriting the accident.
assert "P3-6 inngest bootstrap creates /var/log/journal before starting Vector" \
  "grep -qE '^[[:space:]]*mkdir -p /var/log/journal$' '$SCRIPT_DIR/inngest-bootstrap.sh'"
assert "P3-6 inngest bootstrap applies journald's tmpfiles ownership/ACL rule (as web-1 does)" \
  "grep -qE 'systemd-tmpfiles --create --prefix /var/log/journal' '$SCRIPT_DIR/inngest-bootstrap.sh'"
# Creating it silently is not enough — a mkdir that fails (read-only /var, full disk) must be
# LOUD, and on this host loud means the Vector-independent phone-home channel, since the
# failure mode is precisely "journald->Vector ships nothing".
assert "P3-6 a failed /var/log/journal creation reports via the Vector-INDEPENDENT phone-home" \
  "grep -qE 'inngest-boot-phone-home\\.sh journal-dir-MISSING' '$SCRIPT_DIR/inngest-bootstrap.sh'"
# Ordering is load-bearing: created AFTER the fact, Vector's journald sources have already
# opened (or failed to open) the directory. Assert the mkdir precedes the vector restart.
assert "P3-6 the journal dir is created BEFORE vector.service is restarted (ordering)" \
  "[[ \$(grep -nE '^[[:space:]]*mkdir -p /var/log/journal$' '$SCRIPT_DIR/inngest-bootstrap.sh' | cut -d: -f1 | sed -n '1p') -lt \$(grep -nE '^[[:space:]]*systemctl restart vector\\.service' '$SCRIPT_DIR/inngest-bootstrap.sh' | cut -d: -f1 | sed -n '1p') ]]"
# Scope the identifier check to the [sources.host_scripts_journald] BLOCK (the Source 4 include list),
# not the whole file — a name relocated into a comment / exclude / other sink would defeat a file-wide
# grep while breaking Source-4 delivery (test-design + pattern review).
HSJ="$(awk '/^\[sources\.host_scripts_journald\]/{f=1;next} f&&/^\[[a-z]/{f=0} f' "$SCRIPT_DIR/vector.toml")"
assert "Source 4 (host_scripts_journald) include list carries all 3 probe SyslogIdentifiers" \
  "grep -q 'web-zot-consumer-probe' <<<\"\$HSJ\" && grep -q 'web-git-data-probe' <<<\"\$HSJ\" && grep -q 'web-nic-guard' <<<\"\$HSJ\""

# --- #6617c (A5): the dedicated-host tag trio, asserted on BOTH sides of the join ---
# Source 4's include_matches.SYSLOG_IDENTIFIER is sd_journal_add_match EXACT-VALUE equality,
# never a prefix/regex — so an allowlist entry with no unit emitting that exact tag is a
# silent no-op, and a unit tag with no allowlist entry is a silent drop. The #6617 lesson is
# that the two halves were maintained independently and three of four tags could never match:
#   - inngest-redis.service set NO SyslogIdentifier= -> journald tagged it from the ExecStart
#     basename `doppler` (same defect class as #6536's heartbeat unit).
#   - inngest-nftables.service set NO SyslogIdentifier= -> tagged `inngest-nftables.sh` (.sh).
# So each tag below is asserted TWICE: once on the emitting unit, once on the allowlist. A
# one-sided assertion is the exact shape that passed while the channel was dead.
#
# Anchors are syntactic constructs, not bare tokens (cq-assert-anchor-not-bare-token): the
# unit side anchors `^SyslogIdentifier=<tag>$` (a directive line — a comment cannot satisfy
# it), the vector side anchors `^\s*"<tag>",$` (a quoted TOML array element — the surrounding
# rationale comments in this very file mention every one of these names in prose).
echo ""
echo "--- #6617c (A5): inngest tag trio — unit SyslogIdentifier= <-> Source 4 allowlist ---"
REDIS_UNIT="$SCRIPT_DIR/inngest-redis.service"
INNGEST_CI="$SCRIPT_DIR/cloud-init-inngest.yml"
INNGEST_BOOTSTRAP="$SCRIPT_DIR/inngest-bootstrap.sh"
assert "inngest-redis.service exists"   "[[ -f '$REDIS_UNIT' ]]"
assert "cloud-init-inngest.yml exists"  "[[ -f '$INNGEST_CI' ]]"
assert "inngest-bootstrap.sh exists"    "[[ -f '$INNGEST_BOOTSTRAP' ]]"

# Scope the nftables assertion to that unit's OWN write_files entry, so a SyslogIdentifier=
# added to a neighbouring unit cannot satisfy it.
NFT_UNIT_BLOCK="$(awk '/^  - path: \/etc\/systemd\/system\/inngest-nftables\.service$/{f=1;next} f&&/^  - path: /{f=0} f' "$INNGEST_CI")"
assert "nftables unit block extracted from cloud-init-inngest.yml" \
  "[[ -n \"\$NFT_UNIT_BLOCK\" ]]"

# Unit side (emitter): each tag is set EXPLICITLY.
assert "unit side: inngest-redis.service sets SyslogIdentifier=inngest-redis (was tagged 'doppler')" \
  "grep -qE '^SyslogIdentifier=inngest-redis\$' '$REDIS_UNIT'"
assert "unit side: inngest-nftables.service sets SyslogIdentifier=inngest-nftables (was tagged 'inngest-nftables.sh')" \
  "grep -qE '^[[:space:]]*SyslogIdentifier=inngest-nftables\$' <<<\"\$NFT_UNIT_BLOCK\""
assert "unit side: inngest-server-probe.service sets SyslogIdentifier=inngest-server-probe (#6617a)" \
  "grep -qE '^SyslogIdentifier=inngest-server-probe\$' '$INNGEST_BOOTSTRAP'"

# Vector side (allowlist): each tag is a quoted element of Source 4's include list.
assert "vector side: Source 4 allowlists \"inngest-redis\"" \
  "grep -qE '^[[:space:]]*\"inngest-redis\",\$' <<<\"\$HSJ\""
assert "vector side: Source 4 allowlists \"inngest-nftables\"" \
  "grep -qE '^[[:space:]]*\"inngest-nftables\",\$' <<<\"\$HSJ\""
assert "vector side: Source 4 allowlists \"inngest-server-probe\"" \
  "grep -qE '^[[:space:]]*\"inngest-server-probe\",\$' <<<\"\$HSJ\""

# --- #7695 (A5 extension): the LUKS boot-stage tag, asserted on BOTH sides -----------------
LUKS_UNIT_BLOCK="$(awk '/^  - path: \/etc\/systemd\/system\/inngest-luks-open\.service$/{f=1;next} f&&/^  - path: /{f=0} f' "$INNGEST_CI")"
assert "LUKS reopen unit block extracted from cloud-init-inngest.yml" \
  "[[ -n \"\$LUKS_UNIT_BLOCK\" ]]"
# Same exact-value contract as the trio above: a unit tag with no allowlist entry is a silent
# DROP, and an allowlist entry with no emitting unit is a silent NO-OP. Two emitters share this
# tag on purpose (the cloud-init runcmd stage and the boot-reopen unit), so the unit-side
# assertion checks the reopen unit specifically -- it is the one whose absence would only show
# up on a SECOND boot, which is exactly the case cloud-init runcmd cannot cover.
assert "unit side: inngest-luks-open.service declares SyslogIdentifier=inngest-luks-stage" \
  "grep -qE '^[[:space:]]*SyslogIdentifier=inngest-luks-stage\$' <<<\"\$LUKS_UNIT_BLOCK\""
assert "emitter side: the cloud-init LUKS stage logs under the same tag" \
  "grep -qE 'logger -t inngest-luks-stage' '$INNGEST_CI'"
assert "vector side: Source 4 allowlists \"inngest-luks-stage\"" \
  "grep -qE '^[[:space:]]*\"inngest-luks-stage\",\$' <<<\"\$HSJ\""

# --- #6894: the LUKS cutover unit's tag — DERIVED from the unit, then required on both sides -----
# Equality against the unit's OWN value rather than a literal repeated here: renaming the tag in one
# file and not the other is the silent-drop this block exists to catch, and a literal in the test
# would have to be renamed too — i.e. it would be a third copy, not a check.
CUTOVER_UNIT="$SCRIPT_DIR/inngest-luks-cutover.service"
CUTOVER_TAG="$(sed -n 's/^SyslogIdentifier=\([A-Za-z0-9._-]*\)$/\1/p' "$CUTOVER_UNIT" 2>/dev/null | sed -n '1p')"
assert "unit side: inngest-luks-cutover.service declares exactly one SyslogIdentifier (read: '$CUTOVER_TAG')" \
  "[[ -n \"\$CUTOVER_TAG\" && \$(grep -c '^SyslogIdentifier=' '$CUTOVER_UNIT') -eq 1 ]]"
assert "vector side: Source 4 allowlists the cutover unit's own SyslogIdentifier" \
  "[[ -n \"\$CUTOVER_TAG\" ]] && grep -qxF \"  \\\"\$CUTOVER_TAG\\\",\" <<<\"\$HSJ\""
assert "emitter side: inngest-luks-cutover.sh logs under the unit's tag (LOG_TAG)" \
  "[[ -n \"\$CUTOVER_TAG\" ]] && grep -qxF \"readonly LOG_TAG=\\\"\$CUTOVER_TAG\\\"\" '$SCRIPT_DIR/inngest-luks-cutover.sh'"

# CF-4 (#7228): INVERTED from a negative pair to a POSITIVE one, in the direction the EMITTER
# dictates. It used to assert that "inngest-boot-phone-home" was ABSENT from the allowlist, on
# the explicitly stated condition that the script "never calls logger, so an allowlist entry
# would be a permanently-dead no-op that reads like coverage". That condition no longer holds:
# the emitter is the single delivery path for every SOLEUR_INNGEST_BOOT_STAGE marker and all
# three of its failure modes were `exit 0` with no output, so it could not report that the boot
# trace had died — the cq-silent-fallback-must-mirror-to-sentry violation #7228 exists to fix.
# It now emits on its own failure arms, so the entry is live rather than dead.
#
# journald is the correct channel BECAUSE the emitter's own POST is what failed, and the two are
# independent at the credential level: the emitter reads the cloud-init-staged token file, while
# vector.service resolves BETTERSTACK_LOGS_TOKEN from Doppler at ExecStart. The failure that
# silences the emitter therefore leaves this channel up.
#
# Same lockstep shape as R1-1.8 below: an allowlist entry with no matching emitter is a dead
# no-op, and an emitter whose tag is not allowlisted is silence that reads as health. Both
# halves are asserted, and the tag is DERIVED from the emitter on one side rather than restated
# twice — two hardcoded copies would agree with each other while both disagreeing with reality.
PHONE_HOME_BODY="$(awk '/^  - path: \/usr\/local\/bin\/inngest-boot-phone-home\.sh$/{f=1;next} f&&/^  - path: /{f=0} f' "$INNGEST_CI")"
PHONE_HOME_TAG="$(grep -oP '^[[:space:]]*logger -t \K[a-z0-9-]+' <<<"$PHONE_HOME_BODY" | sed -n '1p' || true)"
assert "CF-4a: inngest-boot-phone-home.sh DOES call logger on its failure arms (it must report its own death)" \
  "[[ -n \"\$PHONE_HOME_TAG\" ]]"
assert "CF-4b: its tag ('${PHONE_HOME_TAG:-<none>}') IS in the Source 4 allowlist (an unallowlisted tag is silence that reads as health)" \
  "[[ -n \"\$PHONE_HOME_TAG\" ]] && grep -qE \"^[[:space:]]*\\\"\$PHONE_HOME_TAG\\\",\\\$\" <<<\"\$HSJ\""
# The half that keeps the channel BOUNDED. Every marker call site would otherwise ship a journald
# row on a perfectly healthy boot (~15/boot of pure duplication — the POST already carries the
# marker), converting a failure channel into a standing quota cost. The success path must not
# reach a logger call: assert every logger invocation in the body sits inside a failure branch.
assert "CF-4c: the emitter is SILENT ON SUCCESS (every logger call is inside a failure arm, not the main path)" \
  "[[ \$(grep -cP '^[[:space:]]*logger -t ' <<<\"\$PHONE_HOME_BODY\") -eq \$(grep -cP '^[[:space:]]*logger -t .*reason=' <<<\"\$PHONE_HOME_BODY\") ]]"
# P1-SEC, applied to the tag this change opens: the new route carries this script's output to
# Better Stack, and on the missing-token arm the redaction at :125 has not run yet. So $detail
# must never appear on a logger line.
assert "CF-4d: no logger row in the emitter carries \$detail (redaction has not run on the early arms)" \
  "! grep -qP '^[[:space:]]*logger -t .*\\\$detail' <<<\"\$PHONE_HOME_BODY\""

echo ""
echo "--- P1-SEC: the inngest-redis channel opened above is a CREDENTIAL path ---"
# The two assertions above (SyslogIdentifier=inngest-redis + the Source 4 allowlist entry)
# together opened a NEW route from that unit's RAW STDERR to Better Stack. Two credentials
# ride that route:
#   - redis-server echoes an offending directive VERBATIM on any config parse failure
#     (`>>> 'requirepass "<live prd password>"'`), and the unit's ExecStart passes the
#     password as exactly that directive;
#   - INNGEST_POSTGRES_URI (a postgres://<user>:<pw>@host DSN) is in the same unit's env.
# Raw stderr is not JSON, so pii_scrub_structured skips it and it lands in pii_scrub_string,
# which redacted only userid=, OAuth query params, email, and Authorization Bearer/Basic.
# Neither shape was covered, so this allowlist entry was a credential-exfil channel.
#
# Asserted BEHAVIOURALLY, and on the credential SHAPE rather than a bare '://': scripts on
# this host legitimately print credential-LESS internal URLs (http://10.0.1.40:8288/), so a
# '://' ban would either false-fire on those or get muted. Mirrors the DSN-shape probe at
# inngest-registry-probe.test.sh ("no user:pass@host:port DSN in ANY journald line").
PSS="$(awk '/^\[transforms\.pii_scrub_string\]/{f=1;next} f&&/^\[[a-z]/{f=0} f' "$SCRIPT_DIR/vector.toml")"
assert "pii_scrub_string block extracted from vector.toml (carries replace() rules)" \
  "[[ -n \"\$PSS\" ]] && grep -qF 'replace(msg,' <<<\"\$PSS\""

# Rule presence anchored on the `replace(msg, r'…'` CALL shape, never a bare token: the block
# is full of prose that names these very shapes, and a token grep would pass vacuously
# against a deleted rule (cq-assert-anchor-not-bare-token).
assert "pii_scrub_string carries a requirepass rule (redis echoes the directive verbatim on parse failure)" \
  "grep -qE \"replace\\(msg, r'[^']*requirepass\" <<<\"\$PSS\""
assert "pii_scrub_string carries a URI-credential (DSN) rule" \
  "grep -qE \"replace\\(msg, r'[^']*://\" <<<\"\$PSS\""
# vector.toml is rendered through Terraform's templatefile(), so a capture ref MUST be
# written $${N}. A bare ${N} is consumed at render time: validate-infra-templates.sh catches
# the render-fatal half, this catches the silent half where the rule loses its capture.
assert "every pii_scrub_string capture ref is templatefile-escaped (\$\${N}, never a bare \${N})" \
  "! grep -qE '[^$][\$]\{[0-9]\}' <<<\"\$PSS\""

# Run the PRODUCTION regexes against fixtures. The pattern and replacement are EXTRACTED from
# vector.toml rather than re-typed here: a re-typed copy drifts, and this guard would then
# keep passing against a defanged config (the drift-guard-extraction-mirrors-the-producer
# rule). `$${N}` is unescaped to the `${N}` Vector itself sees before perl runs it.
vrl_rule_apply() {
  local marker="$1" input="$2" line re rep
  line="$(grep -F 'replace(msg,' <<<"$PSS" | grep -F "$marker" | head -1)"
  # Missing rule -> return the input UNCHANGED, so the redaction assertions below go red.
  # Erroring here instead would make a deleted rule look like a harness fault.
  if [[ -z "$line" ]]; then printf '%s\n' "$input"; return 0; fi
  re="$(sed -E "s/^[^']*r'//; s/'.*\$//" <<<"$line")"
  rep="$(sed -E "s/^.*', \"//; s/\"\).*\$//" <<<"$line")"
  rep="${rep//\$\$\{/\$\{}"
  PAT="$re" REP="$rep" perl -pe 'BEGIN{$p=$ENV{PAT};$r=$ENV{REP}} s/$p/my @g=($1,$2,$3);(my $o=$r)=~s{\$\{(\d)\}}{defined $g[$1-1]?$g[$1-1]:q()}ge;$o/ge' <<<"$input"
}

# Synthesized fixtures only (cq-test-fixtures-synthesized-only) — the `fixture-only-` prefix
# is what the leak assertions grep for, so a real secret could never satisfy them.
REDIS_LEAK='fixture-only-redis-parse-pw'
DSN_LEAK='fixture-only-dsn-pw'
# Shape of redis-server's real parse-failure echo: the offending directive, verbatim.
REDIS_FIXTURE=">>> 'requirepass \"$REDIS_LEAK\"'"
# Built by concatenation so no contiguous `scheme://<user>:<pw>@host` literal exists in SOURCE
# (gitleaks flags the shape even when the password is a `fixture-only-` variable — the leak
# detector reads the file, not the runtime value). The assembled string is byte-identical to
# the one-liner, so the scrub assertions below still exercise the real credential shape.
DSN_FIXTURE="FATAL: could not connect to postgres:""//inngest_user:$DSN_LEAK""@10.0.1.40:5432/inngest"
# The credential-LESS internal URL this host really does log (cloud-init-inngest.yml's
# loopback probe, and the server-probe marker). It must survive BOTH rules byte-identical.
BENIGN_FIXTURE='SOLEUR_INNGEST_SERVER_PROBE probed http://10.0.1.40:8288/ http_code=200'

REDIS_SCRUBBED="$(vrl_rule_apply 'requirepass' "$REDIS_FIXTURE")"
DSN_SCRUBBED="$(vrl_rule_apply '://' "$DSN_FIXTURE")"
BENIGN_SCRUBBED="$(vrl_rule_apply '://' "$(vrl_rule_apply 'requirepass' "$BENIGN_FIXTURE")")"

# Non-vacuity first: prove the harness CAN see each credential shape when it is present.
# Without these, both redaction assertions pass against a fixture that never carried a secret.
assert "P1-SEC non-vacuity: the redis parse-failure fixture DOES carry the password pre-scrub" \
  "[[ \$(grep -c '$REDIS_LEAK' <<<\"\$REDIS_FIXTURE\") -eq 1 ]]"
assert "P1-SEC non-vacuity: the DSN fixture DOES carry the scheme://<user>:<pw>@ shape pre-scrub" \
  "[[ \$(grep -cE '://[^:/ ]+:[^@ ]+@' <<<\"\$DSN_FIXTURE\") -eq 1 ]]"

assert "P1-SEC pii_scrub_string redacts the requirepass value redis echoes on a config parse failure" \
  "[[ \$(grep -c '$REDIS_LEAK' <<<\"\$REDIS_SCRUBBED\") -eq 0 ]]"
assert "P1-SEC pii_scrub_string redacts the INNGEST_POSTGRES_URI password" \
  "[[ \$(grep -c '$DSN_LEAK' <<<\"\$DSN_SCRUBBED\") -eq 0 ]]"
assert "P1-SEC no scheme://<user>:<pw>@ credential shape survives pii_scrub_string" \
  "[[ \$(grep -cE '://[^:/ ]+:[^@ ]+@' <<<\"\$DSN_SCRUBBED\") -eq 0 ]]"
# The rule must redact the USERINFO and nothing else. `@host:port` is the diagnostic half —
# which DB the failing connection was aimed at — and destroying it would trade a credential
# leak for a blind operator, the exact failure mode this whole change exists to end.
assert "P1-SEC the DSN's @host:port diagnostic SURVIVES (userinfo redacted, not the whole DSN)" \
  "grep -qF '@10.0.1.40:5432/inngest' <<<\"\$DSN_SCRUBBED\""
assert "P1-SEC a credential-LESS internal URL passes through untouched (shape-based, not a '://' ban)" \
  "[[ \"\$BENIGN_SCRUBBED\" == \"\$BENIGN_FIXTURE\" ]]"


# --- #7103 R1 (1.8): ci-deploy's journald channel, asserted in BOTH directions -----------
#
# During the 2026-08-01 recovery the deploy path's own stderr was the thing nobody could
# read. `ci-deploy` IS in the Source 4 allowlist today -- but "is in the allowlist" and "is
# actually shipped" are different claims, and the pair only holds if the allowlist entry and
# the emitter's tag are the same string. An allowlist entry with no matching emitter is a
# dead no-op, and an emitter whose tag is not allowlisted is silence that reads as health.
# This file already guards that trap negatively for inngest-boot-phone-home (CF-4); this is
# the positive case for the channel the incident actually needed.
#
# The tag is DERIVED from ci-deploy.sh, never restated. Two hardcoded copies of "ci-deploy"
# would agree with each other while both disagreeing with the script -- a guard that passes
# precisely when it is wrong. Deriving one side makes a rename fail here instead of in prod.
CI_DEPLOY_SH="$SCRIPT_DIR/ci-deploy.sh"
# `|| true` is load-bearing under this file's `set -euo pipefail`. This derivation feeds R1-1.8a,
# whose entire job is catching a LOG_TAG rename — and on a rename the grep matches nothing, the
# capture returns non-zero, and the suite DIES here rather than reporting. Measured: renaming
# `readonly LOG_TAG=` took the suite from "79/79 passed" to no summary line, no FAIL:, and all
# nine later assertions (R1-1.8a/b/c, R3-4.5a–f) never executing. The guard fired by killing the
# run that would have reported it. The emptiness check on the next line is the real assertion.
CI_DEPLOY_TAG="$(grep -oE '^readonly LOG_TAG="[^"]+"' "$CI_DEPLOY_SH" | sed -n '1p' | cut -d'"' -f2 || true)"

assert "R1-1.8a: ci-deploy.sh declares exactly ONE literal LOG_TAG (derivation is unambiguous)" \
  "[[ -n \"\$CI_DEPLOY_TAG\" ]] && [[ \"\$(grep -cE '^readonly LOG_TAG=' \"\$CI_DEPLOY_SH\")\" == 1 ]]"

assert "R1-1.8b: ci-deploy.sh's LOG_TAG ('$CI_DEPLOY_TAG') IS in the Source 4 allowlist" \
  "grep -qE \"^[[:space:]]*\\\"\$CI_DEPLOY_TAG\\\",?\\\$\" <<<\"\$HSJ\""

# Corroboration, mirroring CF-4's shape: the allowlist entry is only load-bearing if the
# script actually routes through `logger -t "$LOG_TAG"`. Without this, deleting every
# logger call would leave 1.8b green against a channel that emits nothing.
assert "R1-1.8c: ci-deploy.sh emits via logger -t \"\\\$LOG_TAG\" (the allowlist entry is not dead)" \
  "grep -qE 'logger -t \"\\\$LOG_TAG\"' \"\$CI_DEPLOY_SH\""

# --- #7103 R3 (4.5): the Source-4 POSITIVE CONTROL, tied to its wiring ---------------------
#
# betterstack-assert-absence.sh refuses to report `clean` unless it can read a canary back
# through the sink for the host under test. That guarantee is only as good as the four links
# below, and each one fails SILENTLY: a missing allowlist entry, a mismatched SyslogIdentifier,
# a deleted emit, or an emit that runs inside the credential wrapper all produce the same
# observable — no canary — which the helper then reports as `unshipping`. That is the correct
# runtime behaviour, but it would be a permanent false alarm rather than a real signal, and the
# operator would learn to ignore it (the review-fatigue class #6454 names).
#
# No new file and no mutation ceremony: these are one-line greps whose runtime backstop is
# `unshipping` at the sink.
ZOT_PROBE_SH="$SCRIPT_DIR/web-zot-consumer-probe.sh"
ZOT_PROBE_UNIT="$SCRIPT_DIR/web-zot-consumer-probe.service"

# (i) The probe's identifier is in Source 4's allowlist. include_matches.SYSLOG_IDENTIFIER is
# exact-value equality, never a prefix match, so this is a byte-for-byte join.
assert "R3-4.5a: web-zot-consumer-probe is in the Source 4 allowlist" \
  "grep -qE '^[[:space:]]*\"web-zot-consumer-probe\",?\$' <<<\"\$HSJ\""

# (ii) The unit sets that literal identifier. Derived from the unit rather than restated, so a
# rename fails here instead of silently unshipping in prod.
assert "R3-4.5b: the unit sets SyslogIdentifier=web-zot-consumer-probe (the join's other half)" \
  "grep -qE '^SyslogIdentifier=web-zot-consumer-probe\$' \"\$ZOT_PROBE_UNIT\""

# (iii) The probe still emits the marker the helper's control reads.
# ANCHORED ON THE EMISSION, not the bare token. `grep -q 'SOLEUR_PROBE_CANARY'` matched the
# VARIABLE NAME (SOLEUR_PROBE_CANARY_MARKER, the rate-limit path) as well as the echo, so
# deleting the emit line entirely left this arm green — mutation-verified. A marker that is
# named but never emitted is exactly the dead-allowlist-entry this assertion exists to rule out.
assert "R3-4.5c: the probe EMITS SOLEUR_PROBE_CANARY (the allowlist entry is not dead)" \
  "grep -qE '^[[:space:]]*echo \"\\[zot-probe\\] SOLEUR_PROBE_CANARY ' \"\$ZOT_PROBE_SH\""

# (iv) THE 4.3 INVARIANT. The emit site must be OUTSIDE the `doppler run` wrapper.
#
# The ExecStart runs the probe inside `doppler run --project soleur --config prd`, so on a dead
# prd token doppler exits before the probe ever execs. A canary emitted only from there is
# gated behind the exact credential whose failure it is used to rule out — and its absence then
# reads as "vector is dead" rather than "the token is dead". That inversion is what made
# #7095's telemetry unfalsifiable. One refactor collapsing ExecStartPre back into ExecStart
# would silently restore it, so it is pinned here.
assert "R3-4.5d: the canary is emitted from an ExecStartPre OUTSIDE the doppler wrapper" \
  "grep -qE '^ExecStartPre=-?/usr/local/bin/web-zot-consumer-probe\.sh --canary-only\$' \"\$ZOT_PROBE_UNIT\""
assert "R3-4.5e: that ExecStartPre line does NOT route through doppler run" \
  "! grep -E '^ExecStartPre=' \"\$ZOT_PROBE_UNIT\" | grep -c 'doppler' >/dev/null"
# ORDERING, anchored on the BRANCH rather than on any occurrence of the flag name. The previous
# form took `grep -n -- '--canary-only' | sed -n '1p'`, and the first occurrence in the probe is a
# COMMENT (line 86) explaining the flag, twelve lines above the code that implements it (line
# 100). So moving the real branch BELOW the credential FATAL guards — the precise regression
# this arm names — left it green while the mutant FATALed instead of emitting. Mutation-verified.
assert "R3-4.5f: the --canary-only BRANCH precedes the credential FATAL guards" \
  "[[ \"\$(grep -nE '^if \\[ \"\\\$\\{1:-\\}\" = \"--canary-only\" \\]' \"\$ZOT_PROBE_SH\" | sed -n '1p' | cut -d: -f1)\" -lt \"\$(grep -n 'ZOT_PULL_USER/ZOT_PULL_TOKEN unset' \"\$ZOT_PROBE_SH\" | sed -n '1p' | cut -d: -f1)\" ]]"

# --- #9963: the SYSLOG_IDENTIFIER=systemd positive-control emit, tied to its wiring -----
#
# Two evidence surfaces — betterstack-assert-absence.sh's --control read and the rehearsal
# capture's inngest_failed_check — depend on `SYSLOG_IDENTIFIER=systemd` journald rows
# shipping. They DO ship: Vector's journald source spawns `journalctl` with NO match
# arguments and evaluates contains_match as an OR over all record fields (journald.rs @
# v0.43.1, the vector.tf:13 pin), so Source 1's `include_matches.PRIORITY = ["0".."4"]`
# admits a PRIORITY-3 row from ANY unit and ANY identifier. The
# SOLEUR_SYSTEMD_JOURNALD_CONTROL row is the positive control for that discriminated
# path: same admission arm, same discriminator field, so its absence can never read as a
# vacuous clean. Each link fails SILENTLY, so each is pinned here:
#   - a deleted/renamed emit           -> no control rows -> consumers report unshipping
#   - `-t` drift (leaves the systemd    -> a '"SYSLOG_IDENTIFIER":"systemd"' field-scoped
#     discriminator field)                control read can never be satisfied -> unshipping
#   - `-p` drift (err -> notice)       -> PRIORITY 5 leaves the {0..4} arm -> unshipping
#   - "systemd" added to Source 4      -> ships ALL PID-1 chatter incl. every PRIORITY-6
#     (the tempting "deliberate" fix)     Started/Stopped line — the quota blow the
#                                        Source 4 header names. NEVER add it.
#
# Anchored on the EMISSION (the `logger` invocation line inside the probe heredoc), never
# a bare marker token — the R3-4.5c lesson: a marker named but never emitted is the
# dead-entry shape this exists to rule out, and the marker text is quoted verbatim by
# consumers' recipes (a bare grep passes on those files alone).
PROBE_BODY="$(awk "/<<'?PROBESCRIPTEOF/{f=1;next} f&&/^PROBESCRIPTEOF\$/{exit} f" "$INNGEST_BOOTSTRAP")"
assert "9963a: PROBESCRIPTEOF heredoc body extracted (the control's only emission chokepoint)" \
  "[[ -n \"\$PROBE_BODY\" ]] && printf '%s\n' \"\$PROBE_BODY\" | grep -cF 'SOLEUR_INNGEST_SERVER_PROBE' >/dev/null"

# `|| true` is load-bearing under `set -euo pipefail` — pre-fix this grep matches nothing,
# the capture returns non-zero, and the suite would die mid-run rather than reporting the
# FAIL rows (the CI_DEPLOY_TAG :471-477 lesson). The emptiness asserts are the real check.
CONTROL_EMIT="$(printf '%s\n' "$PROBE_BODY" | grep -nE '^[[:space:]]*/usr/bin/logger .*SOLEUR_SYSTEMD_JOURNALD_CONTROL' | sed -n '1p' || true)"
PROBE_EMIT_LN="$(printf '%s\n' "$PROBE_BODY" | grep -nE '^[[:space:]]*logger -t "\$LOG_TAG" "SOLEUR_INNGEST_SERVER_PROBE' | sed -n '1p' | cut -d: -f1 || true)"
CONTROL_LN="${CONTROL_EMIT%%:*}"

assert "9963b: the probe script EMITS SOLEUR_SYSTEMD_JOURNALD_CONTROL via /usr/bin/logger (emission-anchored, not a bare token)" \
  "[[ -n \"\$CONTROL_EMIT\" ]]"
assert "9963c: the control emit carries -t systemd (the discriminator field consumers field-scope on — boundary-anchored: -t systemd-journald or a message-embedded -t systemd must not satisfy it)" \
  "printf '%s\n' \"\$CONTROL_EMIT\" | grep -cE -- '-t[[:space:]]+systemd([^a-zA-Z0-9-]|$)' >/dev/null"
assert "9963d: the control emit's ARGV is exactly 'logger -t systemd -p err' (PRIORITY 3 — inside Source 1's {0..4} admission arm; -t must be the first flag, -p err the second and immediately before the message quote — a message-embedded pair, -t doppler -p err, a reordered pair, -p errx, or trailing flags like -n/--socket must not satisfy it; equivalent spellings like -p user.err are deliberately flagged — the contract is exactly -t systemd -p err)" \
  "printf '%s\n' \"\$CONTROL_EMIT\" | grep -cE -- '/usr/bin/logger[[:space:]]+-t[[:space:]]+systemd[[:space:]]+-p[[:space:]]+err[[:space:]]+\"[^\"]*\"[[:space:]]*\$' >/dev/null"

# UNCONDITIONALITY, same ADR-117 invariant. A CLOSED-FORM pin, because every window
# narrower than the property admitted a wrap (two fix rounds named the escapes:
# `exit`/`return` between emits, `fi`/`esac`/`done` closing a gate opened BEFORE
# the probe emit, a conditional wrapping BOTH emits, mid-line `; if` openers,
# indented `if`/`fi` pairs, `{`/`(`/`coproc`/`&&` scopes, `done`/`fi` tokens in
# prose lines, and suffix code on the emit line itself). So the pin is set-shaped,
# not keyword-shaped: between the LAST col-0 conditional closer before the probe
# emit and the post-emit `if [ "$vector_active" ]` tail gate (ADR-117's sanctioned
# post-emit branch), the ONLY non-comment non-blank code lines allowed are exactly
# the two emit lines. A gate opened anywhere in that region, closed anywhere, or
# hidden behind a `;` suffix adds or alters a code line and fails the count; the
# two emits must also carry no `;` separator, so code cannot ride an anchored line.
LAST_CLOSER_LN=""
TAIL_LN=""
REGION_CODE=0
EMIT_SEP=-1
EMIT_DEPTH=-1
BODY_DEPTH=-1
TAIL_CODE=-1
CLOSER_LINE_CLEAN=""
if [[ -n "$PROBE_EMIT_LN" && -n "$CONTROL_LN" && "$CONTROL_LN" =~ ^[0-9]+$ && "$PROBE_EMIT_LN" =~ ^[0-9]+$ && "$CONTROL_LN" -gt "$PROBE_EMIT_LN" ]]; then
  LAST_CLOSER_LN="$(printf '%s\n' "$PROBE_BODY" | awk -v b="$PROBE_EMIT_LN" 'NR<b && $0 ~ /^(fi|esac|done)([[:space:];)]|$)/ {last=NR} END{print last+0}')"
  TAIL_LN="$(printf '%s\n' "$PROBE_BODY" | grep -nE '^[[:space:]]*if \[ "\$vector_active"' | sed -n '1p' | cut -d: -f1 || true)"
  # The closer LINE must be exactly the closer keyword — a `esac; if …` rider would
  # re-anchor the region boundary while opening a gate on the boundary line itself
  # (test-design E1), invisible to both the depth scan and the region count.
  CLOSER_LINE_CLEAN=""
  [[ "$LAST_CLOSER_LN" =~ ^[0-9]+$ ]] && CLOSER_LINE_CLEAN="$(printf '%s\n' "$PROBE_BODY" | awk -v n="$LAST_CLOSER_LN" 'NR==n' | grep -cE '^(fi|esac|done)[[:space:]]*$' || true)"
  # DEPTH at the control line must be ZERO at any indentation: an opener whose
  # closer lands after the control wraps it. Indented opens count (a wrap is
  # legal bash at any indent); `if (`/`for (` are excluded — the heredoc
  # embeds an awk program and those are ITS keyword shapes, not shell's.
  EMIT_DEPTH="$(printf '%s\n' "$PROBE_BODY" | awk -v b="$CONTROL_LN" 'NR<b && $0 !~ /^[[:space:]]*#/ { if ($0 ~ /^[[:space:]]*(if|for|while|until|select|case)[[:space:]]+[^ (]/) d++; n = gsub(/(^|[[:space:];(])(fi|esac|done)([[:space:];)]|$)/, " ", $0); d -= n } END{print d+0}')"
  # Whole-body net depth must ALSO be zero: a DEPTH-invisible opener (mid-line
  # `; if`, `if (`-subshell) before the region whose closer lands AFTER the tail
  # leaves an unmatched counted closer → net -1 → red (code-quality fix-round
  # spanning-wrap residual).
  BODY_DEPTH="$(printf '%s\n' "$PROBE_BODY" | awk '$0 !~ /^[[:space:]]*#/ { if ($0 ~ /^[[:space:]]*(if|for|while|until|select|case)[[:space:]]+[^ (]/) d++; n = gsub(/(^|[[:space:];(])(fi|esac|done)([[:space:];)]|$)/, " ", $0); d -= n } END{print d+0}')"
  if [[ "$TAIL_LN" =~ ^[0-9]+$ && "$TAIL_LN" -gt "$CONTROL_LN" ]]; then
    REGION_CODE="$(printf '%s\n' "$PROBE_BODY" | awk -v a="$LAST_CLOSER_LN" -v b="$TAIL_LN" 'NR>a && NR<b' | grep -cvE '^[[:space:]]*(#|$)' || true)"
    # `;`/`&`/`|` on an emit line: a `logger … &&` continuation makes the control
    # the RHS of a short-circuit; a `; if` rider hides a gate (test-design E4).
    # A `;`/`|`/`&` INSIDE the emitted message would also trip — over-pin fails
    # loud on a benign edit, the right direction for an ADR-117 invariant.
    EMIT_SEP="$(printf '%s\n' "$PROBE_BODY" | awk -v a="$PROBE_EMIT_LN" -v b="$CONTROL_LN" 'NR==a || NR==b' | grep -c '[;&|<>]' || true)"
    # Post-tail code census: the sanctioned tail is if/phone-home-call/fi/exit 0
    # = 4 code lines. A `{`/`}`/`fi`/`esac`/`done`/`fi`-beyond-tail wrap adds a
    # code line (test-design E2).
    TAIL_CODE="$(printf '%s\n' "$PROBE_BODY" | awk -v b="$TAIL_LN" 'NR>=b' | grep -cvE '^[[:space:]]*(#|$)' || true)"
  fi
fi
assert "9963e: the control emit is UNCONDITIONAL — depth zero at the emit AND net zero over the whole body, the closer line carries no rider, the region holds ONLY the two emits (no ;/&/| on either), and the tail is exactly the sanctioned 4-line gate" \
  "[[ \"$CONTROL_LN\" =~ ^[0-9]+\$ && \"$PROBE_EMIT_LN\" =~ ^[0-9]+\$ && \"$CONTROL_LN\" -gt \"$PROBE_EMIT_LN\" && \"$LAST_CLOSER_LN\" =~ ^[0-9]+\$ && \"$LAST_CLOSER_LN\" -lt \"$PROBE_EMIT_LN\" && \"$CLOSER_LINE_CLEAN\" -eq 1 && \"$EMIT_DEPTH\" -eq 0 && \"$BODY_DEPTH\" -eq 0 && \"$TAIL_LN\" =~ ^[0-9]+\$ && \"$CONTROL_LN\" -lt \"$TAIL_LN\" && \"$REGION_CODE\" -eq 2 && \"$EMIT_SEP\" -eq 0 && \"$TAIL_CODE\" -eq 4 ]]"

# Single emission chokepoint: the PROBESCRIPTEOF heredoc is the only place this marker may
# be emitted. A second emit site — a sibling unit, a prefixed `env logger`, a `systemd-cat`
# line, an ExecStartPost=, a marker-bearing `sed -i` injector, an ssh step in a workflow, or
# a write_files script body in cloud-init-inngest.yml (all verified escape shapes) — would
# multiply the row cost, fork the chokepoint these pins watch, or forge the path.
# The sweep counts NON-COMMENT code lines carrying the marker across the host-emission
# surface — line-shape anchors cannot see the non-`logger` channels, so the marker itself
# is the discriminator. Comment lines may quote the marker freely (docs carry it).
# Sweep scope: the host-emission surfaces — infra deploy artifacts (all file
# types incl. .service/.timer/.tf/extensionless) + workflows + composite actions
# (SSH bridges can reach the host). Deliberately NOT swept: scripts/ (CI-side —
# its journald rows carry a CI-runner host, invisible to the host-scoped control
# read) and knowledge-base/docs. Constructed markers ("SOLEUR_SYSTEMD""_JOURNALD_CONTROL",
# variable-assembled) leave no literal line — documented residual, P2-A5.
CONTROL_EMIT_COUNT="$(grep -rnF 'SOLEUR_SYSTEMD_JOURNALD_CONTROL' --exclude='*.test.sh' --exclude='*.md' \
    "$REPO_ROOT"/apps/web-platform/infra/ "$REPO_ROOT"/.github/workflows/ "$REPO_ROOT"/.github/actions/ | grep -cvE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
assert "9963f: exactly ONE non-comment code line carries SOLEUR_SYSTEMD_JOURNALD_CONTROL across the host-emission surface (infra scripts + cloud-init write_files + workflow ssh steps)" \
  "[[ \"$CONTROL_EMIT_COUNT\" -eq 1 ]]"


assert "9963g: 'systemd' is ABSENT from the Source 4 include_matches.SYSLOG_IDENTIFIER allowlist (never-add pin)" \
  "! printf '%s\n' \"\$HSJ\" | grep -cE '^[[:space:]]*\"systemd\",?\$' >/dev/null"


# Known residuals (documented, not silent): a member written as a bare token inside
# triple quotes (no inner double-quotes to tokenize), and an early `]` inside a
# comment or a member value truncating the awk range. A TOML-parser extraction
# (tomllib) would close both; kept out of this round to hold the suite's
# dependency surface at grep/awk. TOML unicode escapes (`"syst\u0065md"`)
# decode to `systemd` but extract no token — same deferred class (E10).
# Tokenized never-add, over EVERY include_matches.SYSLOG_IDENTIFIER array in the file —
# the property is "no exact-tag membership widens the systemd class", and a whole-line
# element pin misses layout variants (`["sshd", "systemd"]` inline, `'systemd'` quoted,
# `"""systemd"""`, trailing-comment members) and the same membership added under the
# other journald sources (review: five include_matchers can carry it; 9963g covers
# only Source 4's). Extract every array body through its `]`, strip comments,
# tokenize quoted members, compare exactly.
SYSLOG_ID_MEMBERS="$(awk '/include_matches\.SYSLOG_IDENTIFIER/{f=1} f{print} f&&/\]/{f=0}' "$SCRIPT_DIR/vector.toml" | sed 's/#.*$//' | grep -oE '"[a-zA-Z0-9._-]+"|'"'"'[a-zA-Z0-9._-]+'"'"'' | tr -d '"'"'"'"'"'" | sort -u || true)"
assert "9963h: NO include_matches.SYSLOG_IDENTIFIER array in vector.toml carries a 'systemd' member (tokenized, all sources, all layout variants)" \
  "! printf '%s\n' \"$SYSLOG_ID_MEMBERS\" | grep -cx 'systemd' >/dev/null"


# Alternate TOML key spellings (P1-C1 fix-round): `include_matches.SYSLOG_IDENTIFIER`
# can be written with whitespace (`include_matches . SYSLOG_IDENTIFIER`), a quoted
# key (`include_matches."SYSLOG_IDENTIFIER"`), or an inline table
# (`include_matches = { SYSLOG_IDENTIFIER = ["systemd"] }`) — semantically identical
# to the dotted form but invisible to the array-body tokenizer above. Pin all
# spelling variants absent by refusing ANY non-canonical reference form.
assert "9963i: EVERY SYSLOG_IDENTIFIER occurrence in comment-stripped vector.toml lives on a canonical include_matches.SYSLOG_IDENTIFIER line (covers asymmetric whitespace, quoted keys, single/multiline inline-table members, [sources.*.include_matches] sub-table bodies, VRL assignments, and merge-literal forges)" \
  "! sed 's/#.*$//' \"$SCRIPT_DIR/vector.toml\" | grep -E 'SYSLOG_IDENTIFIER' | grep -cvE 'include_matches\.SYSLOG_IDENTIFIER' >/dev/null"
assert "9963i-bis: no BARE include_matches table exists (a bare include_matches = { or a [sources.*.include_matches] sub-table header opens member lines the canonical-form pin would flag, but refuse the container itself too — drift must fail loud, not route around)" \
  "! sed 's/#.*$//' \"$SCRIPT_DIR/vector.toml\" | grep -cE 'include_matches[[:space:]]*=[[:space:]]*\{|^\[[^]]*include_matches[^]]*\]' >/dev/null"

assert "9963j: NO VRL transform assigns .SYSLOG_IDENTIFIER (a stamped tag would forge the own-field read; quoted-segment spellings and single-line VRL bodies covered — the check is unanchored over comment-stripped text)" \
  "! sed 's/#.*$//' \"$SCRIPT_DIR/vector.toml\" | grep -cE '(^|[^a-zA-Z_])\.[^a-zA-Z_]?SYSLOG_IDENTIFIER[^a-zA-Z_]?[[:space:]]*=' >/dev/null"

# Syntax-dead probe body (P1-A2 fix-round): all the emission pins read TEXT. A
# probe body that fails to parse (a stray paren or unbalanced quote introduced
# anywhere above the emit) produces zero rows while every textual pin stays
# green. bash -n validates the generated script's grammar.
# PRIORITY widening under the OTHER journald sources (fix-round N2): an added
# include_matches.PRIORITY under app_container/egress_gw/host_scripts would
# OR-admit everything at those priorities — the same quota trap property C
# guards for SYSLOG_IDENTIFIER, one field over. Pin the field to Sources 1/2.
assert "9963l: include_matches.PRIORITY exists ONLY under inngest_journald and system_journald (a PRIORITY arm added under any other journald source OR-admits the whole journal)" \
  "! awk '/^\[sources\./{src=\$1} /^include_matches\.PRIORITY/{print src}' \"$SCRIPT_DIR/vector.toml\" | grep -vE 'inngest_journald|system_journald' | grep -c . >/dev/null"

assert "9963k: the PROBESCRIPTEOF probe body is syntactically valid under BOTH bash and sh (it declares #!/bin/sh — a bashism that passed bash -n would die under dash at runtime; a parse-dead body emits zero rows)" \
  "printf '%s\n' \"\$PROBE_BODY\" > /tmp/probe-body-\$\$.sh; rc=0; { bash -n /tmp/probe-body-\$\$.sh && sh -n /tmp/probe-body-\$\$.sh; } || rc=1; rm -f /tmp/probe-body-\$\$.sh; [[ \$rc -eq 0 ]]"


echo ""

# Anti-vacuity floor (ADR-193): a stranded run must never report clean. Floor, not
# equality — developer-incremented. Reports directly, never through assert/pass/fail.
MIN_TOTAL=101
if (( TOTAL < MIN_TOTAL )); then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$TOTAL" "$MIN_TOTAL" >&2
  exit 1
fi

echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
