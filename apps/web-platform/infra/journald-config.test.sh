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
# grep -c reads all input (no early close) so the `!` reflects the real match state. `>/dev/null`
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
  "[[ \$(grep -nE '^[[:space:]]*mkdir -p /var/log/journal$' '$SCRIPT_DIR/inngest-bootstrap.sh' | cut -d: -f1 | head -1) -lt \$(grep -nE '^[[:space:]]*systemctl restart vector\\.service' '$SCRIPT_DIR/inngest-bootstrap.sh' | cut -d: -f1 | head -1) ]]"
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

# CF-4 negative: inngest-boot-phone-home.sh is a pure `curl` POST straight to the Better Stack
# HTTP ingest — it never calls `logger`, so it has NO journald channel and an allowlist entry
# for it would be a permanently-dead no-op that reads like coverage. Keep it out.
assert "CF-4: \"inngest-boot-phone-home\" is NOT in the Source 4 allowlist (no journald channel)" \
  "! grep -qE '^[[:space:]]*\"inngest-boot-phone-home\",\$' <<<\"\$HSJ\""
assert "CF-4 corroboration: inngest-boot-phone-home.sh never calls logger" \
  "! grep -qE '^[[:space:]]*logger[[:space:]]' <<<\"\$(awk '/^  - path: \/usr\/local\/bin\/inngest-boot-phone-home\.sh\$/{f=1;next} f&&/^  - path: /{f=0} f' '$INNGEST_CI')\""

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

echo ""
echo "=== Results: $PASS/$TOTAL passed ==="
if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test(s) failed"
  exit 1
fi
echo "OK"
