# =============================================================================
# LUKS-at-rest for the LIVE /workspaces volume (#6588, ADR-119)
# =============================================================================
#
# WHAT THIS CLOSES
# ----------------
# `hcloud_volume.workspaces` (server.tf) holds every user's checked-out source code
# as plaintext ext4, while docs/legal/{privacy-policy,gdpr-policy,data-protection-
# disclosure}.md tell data subjects it is LUKS-encrypted. The operator's decision is
# to make the claim true rather than retract it. This file declares the ADDITIVE
# encrypted volume that ADR-119 cuts over to.
#
# SHARP EDGE — encryption-at-rest is GUEST-SIDE LUKS, NOT an hcloud_volume attribute.
# There is no hcloud `encrypted` flag. `cryptsetup` runs on the host, unlocked by the
# Doppler-injected WORKSPACES_LUKS_KEY — never an argv positional, never baked into
# user_data. Mirrors git-data-luks.tf, with three DELIBERATE divergences called out
# below (no `format`, dedicated-config rationale, web-1 singleton).
#
# THE ISSUE'S PREMISE WAS WRONG, AND THE CORRECTION IS LOAD-BEARING
# -----------------------------------------------------------------
# #6588 asserts `hcloud_volume.format` is ForceNew, so a naive apply destroys the
# volume. That is a RED HERRING: LUKS is guest-side, so `format` never changes on the
# live volume. The REAL data-destroyer is the idempotence guard inverting:
# `if ! cryptsetup isLuks "$DEV"; then luksFormat` (cloud-init-git-data.yml) is false
# on a POPULATED PLAINTEXT device ⇒ luksFormat ⇒ live user code wiped. The precedent
# is safe only because git-data's volume is born fresh. Never point that guard at the
# live volume. This file's guard therefore never runs against `hcloud_volume.workspaces`.
#
# WHY ADDITIVE AND NOT BLUE-GREEN (the issue's preferred approach)
# ---------------------------------------------------------------
# Blue-green needs a new host. `cx33` is `available = false` in ALL THREE EU
# datacentres (live Hetzner API 2026-07-16; corroborated at
# tests/scripts/test-stock-preflight-gate.sh). A `-replace` of hcloud_server.web
# ["web-1"] would DESTROY the sole prod host and then fail to recreate it, leaving the
# platform unrebuildable. See ADR-119 §Alternatives Considered.

# --- Passphrase ---------------------------------------------------------------
# Minted by terraform, never operator-supplied (hr-tf-variable-no-operator-mint-default).
# `special = false` keeps it shell/stdin-safe for the `printf %s | cryptsetup
# --key-file -` pipe; 40 alphanumeric chars is ~238 bits.
#
# NO ignore_changes — rotation is operator-explicit via `-replace`, matching
# git-data-luks.tf:26-30 and live-verify.tf:30-31.
#
# ROTATION IS NOT A RE-KEY, AND THAT IS A TERMINAL HAZARD (C19).
# `terraform apply -replace=random_password.workspaces_luks` mints a new passphrase
# and updates Doppler, but DOES NOT re-key the existing LUKS header. Post-wipe of the
# plaintext backstop, that permanently strands every workspace. The cutover gate MUST
# assert `luks_passphrase_touched == 0` (precedent: git-data-host-replace-gate.sh).
# If rotation must ever be supported, it is `cryptsetup luksChangeKey`, NOT -replace.
resource "random_password" "workspaces_luks" {
  length  = 40
  special = false
}

# --- Key escrow ---------------------------------------------------------------
# DIVERGENCE FROM git-data, AND THE RATIONALE IS NOT git-data's.
#
# git-data isolates its key in a dedicated config for HOST blast-radius reduction.
# That argument does NOT port: web-1 already carries a full-prd DOPPLER_TOKEN, so
# there is no host blast radius left to buy. An attacker on web-1 reads the full-prd
# token and gets the key regardless.
#
# The real reason is a DIFFERENT boundary — host-vs-CONTAINER, not host-vs-host:
# cloud-init.yml runs `doppler secrets download --config prd > "$TMPENV"` and then
# `docker run --env-file "$TMPENV"`, so EVERY secret in the shared `prd` config is
# injected into the agent container's environment. A WORKSPACES_LUKS_KEY in `prd`
# would be readable via /proc/self/environ BY THE VERY AGENT CODE WHOSE DATA IT
# ENCRYPTS (CWE-522) — reducing the at-rest guarantee to zero against in-container
# compromise or prompt-injection exfiltration.
#
# THE MECHANISM IS INHERITANCE DIRECTIONALITY, AND IT IS THE ONLY THING LOAD-BEARING.
# Doppler resolves root → branch: a secret written to the `prd_workspaces_luks` BRANCH
# does not appear in a `--config prd` download. That asymmetry — and nothing else — is
# what keeps the key out of `--env-file`.
#
# ⚠️ THIS IS NOT LEAST PRIVILEGE, AND SAYING SO WOULD BE FALSE.
# The inverse does NOT hold — established EMPIRICALLY (the learning cited below), NOT from the
# blanket "a branch config INHERITS the full root secret set" premise, which #7159's 2026-08-02
# census FALSIFIED (ADR-164). The measured conclusion is retained unchanged and is deliberately
# not re-derived here:
# `doppler_service_token.workspaces_luks` below resolves ~116 `prd` secrets including
# SUPABASE_SERVICE_ROLE_KEY. It is materially a full-prd token. The repo established
# this empirically and is tracking it:
#   knowledge-base/project/learnings/security-issues/
#     2026-07-07-doppler-branch-config-does-not-isolate-secrets.md  (severity: high)
#   #6122 fixed zot by moving to a SEPARATE PROJECT; #6167 audits the rest — including
#   `prd_git_data`, the precedent this file mirrors.
# It costs nothing on web-1 (which already carries a full-prd DOPPLER_TOKEN at
# cloud-init.yml:409, so there is no host blast radius left to buy), which is why the
# CWE-522 container boundary still genuinely holds. True isolation would be a separate
# Doppler project — that is #6167's scope, not this PR's.
#
# Asserted by workspaces-luks.test.sh A7 (relocation ⇒ RED) AND A11 (ADDITION of any
# resource writing to `config = "prd"` ⇒ RED). A7 alone was addition-blind: a SECOND
# doppler_secret writing this key to shared `prd`, unmasked, passed 20/20 green.
#
# OPERATOR PRECONDITION: the `prd_workspaces_luks` config must exist in Doppler
# BEFORE `terraform apply` — the provider manages environments and configs as a unit
# and will not create a bare config.
#
# git-data USED to carry this same precondition; #6977 DELETED it by declaring the config
# in Terraform (see `resource "doppler_config" "git_data_prd"` in git-data-luks.tf), which
# is why the birth route's post-merge operator checklist is empty. This resource is now
# the one holding the manual step, and that git-data block is the pattern to copy when
# closing it — do NOT re-derive the deleted operator note.
resource "doppler_secret" "workspaces_luks_key" {
  project    = "soleur"
  config     = "prd_workspaces_luks"
  name       = "WORKSPACES_LUKS_KEY"
  value      = random_password.workspaces_luks.result
  visibility = "masked"
}

# The host resolves the passphrase at unlock time via this token. `access = "read"`
# is real (it cannot WRITE secrets) — but it is NOT a narrower READ scope than the
# host's existing full-prd token: this token reads all ~116 prd secrets too — MEASURED, not
# inferred from the "branch configs inherit the root" premise that #7159 falsified (ADR-164,
# 2026-08-02 census; see the escrow comment above, #6167). Do not describe it
# as least-privilege.
#
# ⚠️ #6604 (the cutover) MUST read it with `doppler secrets get WORKSPACES_LUKS_KEY
# --plain --config prd_workspaces_luks`. The natural-looking alternatives are exactly
# the CWE-522 hole this file exists to close, because inheritance drags the root in:
#   `doppler run --config prd_workspaces_luks -- …`      → injects all ~116 + the key
#   `doppler secrets download --config prd_workspaces_luks` → same, into a file
# Neither this .tf nor its guard can see host-side code, so nothing here pins it.
#
# ROTATION (#8632) is a change to `name`. Every user-set attribute of this resource is ForceNew
# in the pinned provider (DopplerHQ/doppler v1.21.2, resource_service_token.go), so a rename
# plans as one replace, and the merge must carry `[ack-destroy]`. In that one merge:
#   1. the main apply mints the new token, rewrites WORKSPACES_LUKS_BOOT_TOKEN below, then
#      deletes the old token (create_before_destroy);
#   2. its SSH step re-fires terraform_data.luks_monitor_token_install below (its only trigger is
#      this key's hash), which proves the new token can read WORKSPACES_LUKS_KEY and then rewrites
#      the DOPPLER_TOKEN= line in web-1's /etc/default/luks-monitor.
# No dispatch is involved. Never `-replace random_password.workspaces_luks`: that rotates the
# PASSPHRASE, not this token.
#
# create_before_destroy is for failure atomicity: without it a failed create lands AFTER the
# delete, leaving no live token anywhere. It creates the new token while the old one still exists,
# which is safe here because the names differ. A future same-name `-replace` needs a probe that
# Doppler accepts two service tokens with one name first (the tunnel.tf 2026-07-29 probe shape).
#
# Rotated 2026-09-24 from `workspaces-luks-boot` (created 2026-07-18) because retained web-1
# snapshot 411798619 very likely holds that token.
resource "doppler_service_token" "workspaces_luks" {
  project = "soleur"
  config  = "prd_workspaces_luks"
  name    = "workspaces-luks-boot-2026-09-24"
  access  = "read"

  lifecycle {
    create_before_destroy = true
  }
}

# #8632 — deliver the current boot token to web-1's luks-monitor EnvironmentFile, in the same
# apply that rotates it. ADR-119's 2026-09-24 addendum: after the cutover's first write, THIS
# resource owns the DOPPLER_TOKEN= line; the SOLEUR_SENTRY_DSN line on web-1 belongs to
# terraform_data.luks_monitor_install below (#8706), and the helper keeps every other line byte for
# byte. Same trigger and host_key shape as server.tf's private_nic_guard_install.
#
# The ONLY trigger is the token hash. No file() hash: a comment edit to the helper must not
# re-provision web-1 (the file provisioner uploads the current helper on every fire anyway).
#
# The helper proves the token READS the key; it never starts luks-monitor.service, so mount,
# escrow or readyz faults that have nothing to do with the token cannot redden a rotation merge.
# The second remote-exec only prints the timer's state into the apply log (no secret in it, so
# Terraform does not suppress its output; #8632 review found the host timer quiet).
resource "terraform_data" "luks_monitor_token_install" {
  triggers_replace = nonsensitive(sha256(doppler_service_token.workspaces_luks.key))

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key
    agent       = var.ci_ssh_private_key == null
    host_key    = local.web_1_ssh_host_key
    # #8706 — Terraform uploads each inline script before running it; the default /tmp path is
    # world-readable, and the FIRST remote-exec carries the token. A connection-only edit does
    # not touch triggers_replace, so this line does not re-fire the installer.
    script_path = "/root/tf-luks-token-%RAND%.sh"
  }

  provisioner "file" {
    source      = "${path.module}/luks-monitor-token-refresh.sh"
    destination = "/usr/local/bin/luks-monitor-token-refresh.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "set -e",
      # Terraform blanks an uploaded script only after it exits 0; on a refusal the full script
      # (token included) would stay on disk. The shell keeps running from its open descriptor.
      "rm -f -- \"$0\"",
      # printf is a shell builtin, so the key is never an argument to any process; the helper
      # reads exactly one line from stdin.
      "printf '%s\\n' '${doppler_service_token.workspaces_luks.key}' | bash /usr/local/bin/luks-monitor-token-refresh.sh",
    ]
  }
  provisioner "remote-exec" {
    inline = [
      "systemctl list-timers luks-monitor.timer --no-pager || true",
      "systemctl show -p UnitFileState,ActiveState,LastTriggerUSec luks-monitor.timer --no-pager || true",
      "systemctl show -p Result,ExecMainStatus,ExecMainExitTimestamp luks-monitor.service --no-pager || true",
    ]
  }
}

# #8706 — deliver and arm web-1's daily LUKS at-rest probe. The cutover's install tail was the
# only installer, and no real cutover ever reached it (ADR-119 2026-09-27 addendum), so the timer,
# its service and /usr/local/bin/luks-monitor never existed on web-1. This resource owns them now,
# plus the SOLEUR_SENTRY_DSN= line in /etc/default/luks-monitor (the token installer above keeps
# the DOPPLER_TOKEN= line; each writer keeps the other's line byte for byte).
#
# Web-1 only, like its sibling, which is why it lives here and not in server.tf: a fresh web host
# must NOT get these units (ADR-119 §(d)).
#
# The file hashes ARE the trigger, deliberately (unlike the token installer): an edit to the probe
# must re-deliver the probe. The cost: any edit to the shared workspaces-luks-emit.sh re-installs
# on web-1 and starts one probe run. The DSN hash re-writes the line on a DSN rotation.
#
# The one probe start is `--no-block`: the apply never waits on or fails with the probe, so mount,
# escrow or readyz faults still cannot redden a merge (ADR-119 2026-09-24). Delivery faults do: the
# is-enabled / is-active asserts. The runtime proof that the timer fires is
# logtail_exploration_alert.luks_monitor_host_timer_dark (betterstack-logs-alerts.tf).
#
# #9045 — the read-only forensic print, run as the installer's FIRST step (so a live cutover freeze,
# which refuses the arm step with exit 17, cannot suppress it). It reads what systemd manager memory
# still holds about the dead-man units (answers H1/H2 without a journal read), plus the boot-path
# facts the fstab issue needs. It is PUBLIC output: no var. reference (Terraform would suppress the
# whole step), and every line is guarded (`|| echo none` / `|| true`) so a missing value can neither
# fail the step nor taint the resource. Deliberately NOT here, pinned by luks-monitor-install.test.sh:
# journalctl (a transient unit's journal echoes its command line), the ExecStart text itself (only
# fired_cmd=yes|no and a sha256 of its argv[] portion; the full property embeds start_time/pid),
# systemctl cat/status or a bare `systemctl show`, /etc/fstab beyond the one exact-field entry (its
# options restricted to [A-Za-z0-9,=._-] and credential-free, else <redacted-options>), /etc/crypttab
# beyond a count, `apt-config dump` (it prints proxy credentials), and /etc/default/luks-monitor
# beyond the existing counts. The list is hashed into triggers_replace, so ANY edit to it re-fires
# the installer on web-1 (idempotent redelivery plus one probe kick; ADR-119 2026-09-28 addendum).
locals {
  luks_monitor_forensic_print = [
    "echo 'luks-monitor forensic (#9045): read-only print, runs before the exit-17 freeze refusal'",
    "for p in LoadState ActiveState SubState Result LastTriggerUSec ExecMainStartTimestamp ExecMainExitTimestamp ExecMainStatus InvocationID; do echo \"luks-monitor forensic workspaces-luks-deadman.timer $p=$(systemctl show -p \"$p\" --value workspaces-luks-deadman.timer 2>/dev/null || echo none)\"; done || true",
    "for p in LoadState ActiveState SubState Result LastTriggerUSec ExecMainStartTimestamp ExecMainExitTimestamp ExecMainStatus InvocationID; do echo \"luks-monitor forensic workspaces-luks-deadman.service $p=$(systemctl show -p \"$p\" --value workspaces-luks-deadman.service 2>/dev/null || echo none)\"; done || true",
    "if [ \"$(systemctl show -p LoadState --value workspaces-luks-deadman.service 2>/dev/null || echo none)\" = loaded ]; then echo \"luks-monitor forensic workspaces-luks-deadman.service fired_cmd=$(systemctl show -p ExecStart --value workspaces-luks-deadman.service 2>/dev/null | grep -q 'result=fired' && echo yes || echo no) argv_sha256=$(systemctl show -p ExecStart --value workspaces-luks-deadman.service 2>/dev/null | sed -n 's/^.*argv[[][]]=//; s/ ; ignore_errors=.*$//p' | sha256sum | cut -c1-64 || echo none)\"; else echo 'luks-monitor forensic workspaces-luks-deadman.service exec=not-loaded'; fi || true",
    "echo \"luks-monitor forensic uptime-s=$(uptime -s 2>/dev/null || echo none)\"",
    "echo \"luks-monitor forensic reboot-required=$([ -e /var/run/reboot-required ] && echo yes || echo no)\"",
    "echo \"luks-monitor forensic fstab /mnt/data=$(awk '$1 !~ /^#/ && $2 == \"/mnt/data\" { n++; o = $4; if (o !~ /^[A-Za-z0-9,=._-]+$/ || o ~ /pass|cred|secret|token|key=/) o = \"<redacted-options>\"; printf \"%s %s %s %s %s %s; \", $1, $2, $3, o, $5, $6 } END { if (!n) print \"none\" }' /etc/fstab 2>/dev/null || echo none)\"",
    "echo \"luks-monitor forensic crypttab-workspaces-lines=$(grep -c '^workspaces' /etc/crypttab 2>/dev/null || true)\"",
    "ar=$(apt-config shell AR Unattended-Upgrade::Automatic-Reboot 2>/dev/null | sed -n \"s/^AR='//; s/'$//p\" || true); case \"$ar\" in true|yes|on|with|enable|1) ar=true ;; false|no|off|without|disable|0) ar=false ;; '') ar=unset ;; *) ar=unrecognised ;; esac; echo \"luks-monitor forensic automatic-reboot=$ar\" || true",
  ]
}

resource "terraform_data" "luks_monitor_install" {
  # Serializes the two writers of /etc/default/luks-monitor, and orders after journald_persistent
  # (the Vector config that allowlists the luks-monitor tag) when both fire in one apply
  # (git_data_probe_install's probe-first ordering). depends_on orders; it never re-fires.
  depends_on = [terraform_data.luks_monitor_token_install, terraform_data.journald_persistent]

  triggers_replace = sha256(join(",", [
    file("${path.module}/luks-monitor.sh"),
    file("${path.module}/workspaces-luks-emit.sh"),
    file("${path.module}/luks-monitor.service"),
    file("${path.module}/luks-monitor.timer"),
    nonsensitive(sha256(var.sentry_dsn)),
    join("\n", local.luks_monitor_forensic_print),
  ]))

  lifecycle {
    # The inngest-host.tf expression, not server.tf's looser shape check: the value lands in a
    # single-quoted shell printf and in a file that workspaces-luks-emit.sh SOURCES as root, so a
    # quote, $( ) or backtick must never pass. Empty is allowed here on purpose: a precondition
    # failure stops every resource in the -target-scoped SSH apply, so the host refuses it instead
    # (the writer's exit 10), which fails only this resource.
    precondition {
      condition     = nonsensitive(var.sentry_dsn == "" || can(regex("^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+$", var.sentry_dsn)))
      error_message = "var.sentry_dsn (TF_VAR_sentry_dsn from Doppler prd_terraform SENTRY_DSN) is not a well-formed Sentry DSN (https://<key>@<host>/<project>). Refusing to write it into web-1's /etc/default/luks-monitor, which is sourced as root. The value is not shown."
    }
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.web["web-1"].ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key
    agent       = var.ci_ssh_private_key == null
    host_key    = local.web_1_ssh_host_key
    # Inline scripts upload here instead of world-readable /tmp: the DSN writer carries the DSN.
    script_path = "/root/tf-luks-monitor-%RAND%.sh"
  }

  # #9045 — FIRST: the read-only forensic print (local.luks_monitor_forensic_print, above). Before
  # the exit-17 freeze refusal, and before every other step, so no earlier failure or live freeze
  # can suppress the evidence it prints.
  provisioner "remote-exec" {
    inline = local.luks_monitor_forensic_print
  }

  # Straight into place, at the cutover tail's destinations exactly (luks-monitor-install.test.sh
  # pins both sides). A failure part-way taints the resource; the next apply re-delivers all four.
  provisioner "file" {
    source      = "${path.module}/luks-monitor.sh"
    destination = "/usr/local/bin/luks-monitor"
  }
  provisioner "file" {
    source      = "${path.module}/workspaces-luks-emit.sh"
    destination = "/usr/local/bin/workspaces-luks-emit.sh"
  }
  provisioner "file" {
    source      = "${path.module}/luks-monitor.service"
    destination = "/etc/systemd/system/luks-monitor.service"
  }
  provisioner "file" {
    source      = "${path.module}/luks-monitor.timer"
    destination = "/etc/systemd/system/luks-monitor.timer"
  }

  # Make the binaries executable the moment they land (the file provisioner writes 0644, and a
  # timer run in the gap would fail 203/EXEC), then remove stale root-owned inline scripts that
  # pre-#8706 failed applies left world-readable in /tmp (Terraform blanks a script only after it
  # exits 0, so a refused token run left the token there). -mmin +60 keeps this apply's own
  # in-flight scripts. Then the env-file state BEFORE the write: type/mode/owner and line COUNTS
  # only, never a value. No var. reference, so Terraform does not suppress this output.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "chmod 0755 /usr/local/bin/luks-monitor /usr/local/bin/workspaces-luks-emit.sh",
      "find /tmp -maxdepth 1 -name 'terraform_*.sh' -user root -mmin +60 -size +0c -delete || true",
      "echo \"luks-monitor envfile before: $(stat -c '%F %a %U' /etc/default/luks-monitor 2>/dev/null || echo absent)\"",
      "echo \"luks-monitor envfile before: DOPPLER_TOKEN=$(grep -c '^DOPPLER_TOKEN=' /etc/default/luks-monitor 2>/dev/null || true) SOLEUR_SENTRY_DSN=$(grep -c '^SOLEUR_SENTRY_DSN=' /etc/default/luks-monitor 2>/dev/null || true)\"",
      "df -P /etc | tail -1 || true",
    ]
  }

  # The DSN line writer. Its output is suppressed (var.sentry_dsn is sensitive), so every refusal
  # has its own exit status, which Terraform still reports: 10 empty DSN, 11 symlink, 12 not a
  # regular file, 13 read error, 14 another line would change, 15 not exactly one DSN line, 16 mv.
  # It deletes its own uploaded script first (a refusal would otherwise leave the DSN on disk) and
  # uses its own temp name, so it never shares a temp file with the token helper or the cutover.
  # POSIX sh (dash on web-1). The pattern keeps the "=", so SOLEUR_SENTRY_DSN_X= survives. Behaviour
  # is pinned by running these exact bytes in luks-monitor-install.test.sh (Guard 3).
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "rm -f -- \"$0\"",
      "umask 077",
      "f=/etc/default/luks-monitor",
      "t=\"$f.dsn.tmp\"",
      "trap 'rm -f \"$t\"' EXIT",
      "d='${var.sentry_dsn}'",
      "[ -n \"$d\" ] || exit 10",
      "[ ! -L \"$f\" ] || exit 11",
      "[ ! -e \"$f\" ] || [ -f \"$f\" ] || exit 12",
      "rm -f \"$t\"",
      "[ -e \"$f\" ] || : > \"$f\"",
      "rc=0; grep -v '^SOLEUR_SENTRY_DSN=' \"$f\" > \"$t\" || rc=$?",
      "[ \"$rc\" -le 1 ] || { rm -f \"$t\"; exit 13; }",
      "printf 'SOLEUR_SENTRY_DSN=%s\\n' \"$d\" >> \"$t\"",
      "[ \"$(grep -v '^SOLEUR_SENTRY_DSN=' \"$t\" | cksum)\" = \"$(grep -v '^SOLEUR_SENTRY_DSN=' \"$f\" | cksum)\" ] || { rm -f \"$t\"; exit 14; }",
      "[ \"$(grep -c '^SOLEUR_SENTRY_DSN=' \"$t\")\" = 1 ] || { rm -f \"$t\"; exit 15; }",
      "chown root:root \"$t\"",
      "mv \"$t\" \"$f\" || exit 16",
      "chmod 600 \"$f\"",
    ]
  }

  # Env-file state AFTER the write (expect DOPPLER_TOKEN=1 SOLEUR_SENTRY_DSN=1, mode 600, owner root).
  provisioner "remote-exec" {
    inline = [
      "echo \"luks-monitor envfile after: $(stat -c '%F %a %U' /etc/default/luks-monitor 2>/dev/null || echo absent)\"",
      "echo \"luks-monitor envfile after: DOPPLER_TOKEN=$(grep -c '^DOPPLER_TOKEN=' /etc/default/luks-monitor 2>/dev/null || true) SOLEUR_SENTRY_DSN=$(grep -c '^SOLEUR_SENTRY_DSN=' /etc/default/luks-monitor 2>/dev/null || true)\"",
    ]
  }

  # Refuse during a live cutover freeze, then arm, assert, and kick one run. The cutover and this
  # apply use different concurrency groups, and the freeze stops luks-monitor on purpose, so
  # re-arming or starting it mid-swap is refused with exit 17 (the resource taints and the next
  # apply re-fires it). A dead-man timer that already FIRED reads SubState=elapsed, not waiting, so
  # a stale July timer cannot hold this refusal forever (#9045). The kick comes LAST: a same-day
  # host-unit row instead of waiting for midnight, and --no-block so the apply never waits on it.
  provisioner "remote-exec" {
    inline = [
      "set -e",
      "[ \"$(systemctl show -p SubState --value workspaces-luks-deadman.timer 2>/dev/null)\" != waiting ] || { echo 'luks-monitor install: a workspaces-luks cutover freeze is live (dead-man armed); refusing to arm (exit 17)'; exit 17; }",
      "systemctl daemon-reload",
      "systemctl enable --now luks-monitor.timer",
      "systemctl is-enabled luks-monitor.timer",
      "systemctl is-active luks-monitor.timer",
      "systemctl start --no-block luks-monitor.service",
    ]
  }

  # State into the apply log. NextElapseUSecRealtime prints host-local time with its zone, which is
  # the measurement that the 00:00-00:30 window is UTC. The service line catches a 203/EXEC from
  # the kick in this same log. The fstab lines record what a mount of /mnt/data would mount. The
  # dead-man units are shown on every fire (#9045). Last, the emptied inline-script stubs this
  # resource left under /root are removed.
  provisioner "remote-exec" {
    inline = [
      "systemctl list-timers luks-monitor.timer --no-pager || true",
      "systemctl show -p LoadState,UnitFileState,ActiveState,NextElapseUSecRealtime,LastTriggerUSec luks-monitor.timer --no-pager || true",
      "systemctl show -p Id,ActiveState,SubState,Result,ExecMainStatus luks-monitor.service --no-pager || true",
      "echo \"luks-monitor fstab /mnt/data: $(findmnt --fstab -no SOURCE /mnt/data 2>/dev/null || echo none)\"",
      "systemctl show -p What,FragmentPath mnt-data.mount --no-pager || true",
      "systemctl show -p Id,ActiveState,SubState,Result workspaces-luks-deadman.timer workspaces-luks-deadman.service --no-pager || true",
      "find /root -maxdepth 1 -name 'tf-luks-*.sh' -delete || true",
    ]
  }
}

# #6649 — publish the boot token to a repo-level GitHub Actions secret so the cutover/verify
# workflows can deliver it host-side (the ONLY credential that reads prd_workspaces_luks; web-1's
# baked DOPPLER_TOKEN is prd-root-scoped and cannot). Mirrors github_actions_secret.doppler_token_inngest_arm
# (inngest-arm-write-token.tf) exactly: a repo secret, no lifecycle.ignore_changes — a `-replace`
# rotation of the token propagates the new key here in the same apply.
#
# This reclassifies the token from operator-applied-host-token to CI-PUBLISHED token, so
# apply-web-platform-infra.yml's DEFAULT allow-list explicitly targets BOTH this resource AND
# doppler_service_token.workspaces_luks, and terraform-target-parity.test.ts REMOVES the token from
# OPERATOR_APPLIED_TOKEN_EXCLUSIONS (the #5566 "a token feeding a github_actions_secret MUST be
# targeted, never excluded" rule). It rides the DEFAULT apply, NOT the scoped
# apply_target=workspaces-luks-cutover job (whose gate asserts EXACTLY the five volume/attachment/
# passphrase/secret/token creates and would abort on a sixth resource).
resource "github_actions_secret" "workspaces_luks_boot_token" {
  repository      = "soleur"
  secret_name     = "WORKSPACES_LUKS_BOOT_TOKEN"
  plaintext_value = doppler_service_token.workspaces_luks.key
}

# --- The encrypted volume -----------------------------------------------------
# DELIBERATELY NO `format` ATTRIBUTE. This is the single most important line in the
# file — and it is a line that is NOT here.
#
# git-data-luks.tf sets `format = "ext4"` and its own comment admits the format is
# pointless (the guest's luksFormat overwrites the header region anyway). Copying it
# here would be actively harmful: `format = "ext4"` makes the fresh volume carry
# TYPE=ext4, BYTE-INDISTINGUISHABLE from the live plaintext volume. That destroys the
# only sound luksFormat guard — "format only a device with NO filesystem signature".
#
# With no `format`, the device is raw and the discriminator exists:
#
#   sig=$(blkid -o value -s TYPE "$DEV" 2>/dev/null || true)
#   case "$sig" in
#     "")          luksFormat ;;   # raw — the ONLY formattable state
#     crypto_LUKS) : ;;            # idempotent no-op
#     *) echo "FATAL: $DEV carries TYPE=$sig — refusing to format a populated device"; exit 1 ;;
#   esac
#
# "Safe by construction" is asserted; this is safe by ENGINEERING. The cutover script
# selects the device by volume ID from terraform output — NEVER by glob scan. The
# precedent scans for the device that IS LUKS; the inverse predicate matches the LIVE
# PLAINTEXT VOLUME. Asserted by workspaces-luks.test.sh A4 (mutation: appending a
# `format` line ⇒ RED — this is the issue's "a plaintext volume must go RED").
#
# SINGLETON, not `for_each = var.web_hosts` (C18). Reasons #1-#2 still hold; reason #3 was
# INVALIDATED 2026-07-24 by ADR-143 (#6459) and is rewritten below:
#   1. A for_each'd attachment lands outside `web2_allow` in
#      destroy-guard-filter-web-platform.jq:96-100 and would PERMANENTLY BRICK the
#      web-2-recreate path.
#   2. `moved` wants a singleton source.
#   3. (ADR-143 #6459 — SUPERSEDES the old "web-2 slated for destruction #6538" rationale, now
#      FALSE.) web-2 is RE-ADDED as a PERMANENT out-of-band standby (var.web_hosts, ADR-143 D2),
#      so "encrypting a volume scheduled for deletion is waste" no longer applies. web-2's for_each
#      volume is KNOWINGLY plaintext-but-EMPTY pre-flip: it holds NO user data (web-2 serves nothing
#      — weight 0, no ingress, connector gated to web-1; the sole copy is web-1's data on THIS
#      additive LUKS singleton). The guest-side fresh-boot LUKS path that would encrypt web-2's
#      volume is DEFERRED to the Phase-4 disposability-proof PR (ADR-143 D3; tracking #6931), where
#      it is exercised on a POPULATED volume (the de-pet web-1 rebuild) and the two-mechanism
#      topology split (this additive singleton vs a fresh-boot for_each volume) is reconciled.
#
# THE DEFER IS FAIL-CLOSED, NOT FAIL-OPEN: no user data can reach web-2's plaintext volume before the
# flip, because a flip that would route users to web-2 is blocked by lb-weight-gate.sh's WORKSPACES_LUKS
# precondition (ADR-143 D3 coupling #2) — the gate reddens unless a soaked `WORKSPACES_LUKS_CUTOVER_AT`
# marker is present. IMPORTANT — the marker is a SHAPE claim, not a proof of encryption: the gate is
# shape-only (it never inspects web-2's block device), so the marker's integrity rests on the #6931
# fresh-boot LUKS path being the writer. #6931 MUST derive `WORKSPACES_LUKS_CUTOVER_AT` from a real
# on-host `blkid -o value -s TYPE == crypto_LUKS` probe (co-located with the gate's separate runtime-
# bind probe), NOT a hand-written timestamp — else a stray marker write could green-light a plaintext
# web-2 flip. So web-2's volume stays plaintext ONLY while it is empty and unreachable.
#
# NOTE for the Phase-4 implementer (ADR-143 D3): the fresh-boot LUKS path MUST use the
# `blkid -o value -s TYPE` discriminator (raw ""→luksFormat; crypto_LUKS→no-op; anything else→FATAL),
# NEVER `cryptsetup isLuks` (cloud-init-git-data.yml:169) — that pattern is the documented
# data-destroyer on a populated device (lines 144-167 above), safe on git-data only because its host
# is single-purpose fresh; the web-host cloud-init is SHARED across web-1 (populated) and web-2.
#
# web-2's volume is therefore KNOWINGLY left plaintext-but-empty pre-flip — a recorded, gate-enforced
# deviation from #6588's "every var.web_hosts member" AC, tracked by #6931. See ADR-119 + ADR-143.
#
# Size and location track web-1's live volume exactly: `var.volume_size` is the same
# input `hcloud_volume.workspaces` uses, so the target can never be born smaller than
# the source, and the location must match the server for attachment to be legal.
resource "hcloud_volume" "workspaces_luks" {
  name     = "soleur-web-platform-data-luks"
  size     = var.volume_size
  location = var.web_hosts["web-1"].location

  labels = {
    app = "soleur-web-platform"
  }
}

# Attached ALONGSIDE the live plaintext volume — the additive design's two-copy state.
# The old volume keeps serving /mnt/data throughout Phases 3-4; this one receives the
# rsync. That two-copy state IS the verified-restorable backup (CPO C3), and it beats
# a Hetzner snapshot: it is a live, mountable device the cutover rehearses, not a blob
# nobody has ever restored — and it manufactures no indefinitely-retained plaintext
# copy, which is what made the snapshot wrong (CTO/COO).
#
# HISTORICAL (corrected 2026-07-27, #6969): this note used to say the
# `scsi-0HC_Volume_*` glob becomes AMBIGUOUS with a second volume attached, and named
# pinning the mount by volume ID as a pending prerequisite. That pin LANDED in #6604 —
# cloud-init.yml mounts `/dev/disk/by-id/scsi-0HC_Volume_${workspaces_volume_id}`, and
# soleur-host-bootstrap-observability.test.sh (AC6b) REDs if the bare glob returns. The
# stale wording was quoted verbatim into five places by #6969 and presented there as the
# decisive ground for refusing a web-1 replace; it is corrected at source here so the
# next reader does not re-inherit it.
#
# The live hazard is the OPPOSITE of ambiguity — it is determinism pointed at the wrong
# volume. /mnt/data pins by-id to hcloud_volume.workspaces[key], the PLAINTEXT volume,
# which the 2026-07-23 cutover SUPERSEDED (live data is on this LUKS volume; see the
# encryption-posture ledger). Nothing on a fresh boot opens the mapper — crypttab is
# written with keyfile `none` (soleur-host-bootstrap.sh) and the guest-side unlock path
# is deferred to #6931. So a rebuilt web-1 mounts the superseded plaintext backstop and
# serves stale worktrees while this volume sits attached and unopened.
resource "hcloud_volume_attachment" "workspaces_luks" {
  volume_id = hcloud_volume.workspaces_luks.id
  server_id = hcloud_server.web["web-1"].id
}

# GitHub Environment with a required-reviewer protection rule — the SOLE human
# authorization on the irreversible /workspaces LUKS freeze (C19 / AC20b; DP-11 F8).
# The cutover job in .github/workflows/workspaces-luks-cutover.yml declares
# `environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (#6649), so the
# REAL freeze arm (`dry_run=false`) is held in "Waiting" for reviewer approval BEFORE any
# step executes — that approval IS the human ack — while a reversible `dry_run=true` rehearsal
# resolves to an empty (ungated) environment and runs unattended (autonomy). The expression is
# fail-closed: the same `!inputs.dry_run` operand gates the freeze, so any freeze-reachable run
# is gated. A zero-reviewer environment auto-approves, so reviewers.users MUST stay non-empty for
# the freeze arm. reviewers.users takes numeric GitHub user IDs — 54279 = @deruelle (the
# operator/founder). Mirrors github_repository_environment.inngest_cutover (inngest-arm-write-token.tf).
#
# Provisioned by the DEFAULT allow-list apply (apply-web-platform-infra.yml push /
# apply_target=manual-rerun), NOT the scoped apply_target=workspaces-luks-cutover job:
# that job's sourced workspaces_luks_cutover_gate asserts the plan is EXACTLY the five
# volume/attachment/passphrase/secret/token creates, so a sixth create there aborts it.
resource "github_repository_environment" "workspaces_luks_cutover" {
  repository  = "soleur"
  environment = "workspaces-luks-cutover"

  reviewers {
    users = [54279]
  }

  # (#8209, ADR-241 D2) ADDED. Measured 2026-09-22 via `gh api repos/.../environments`:
  # this environment's `deployment_branch_policy` was NULL, so a run on ANY branch that
  # cleared the reviewer click could deploy to it. A reviewer gate is a gate on the
  # HUMAN, not on the CODE: the approver sees a run name, not the diff of the branch
  # that will execute with the environment's secrets. Once this environment carries a
  # Tier-B secret, that is the whole boundary, so both halves below are required.
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

# The named list the block above declares — without it the list is EMPTY and GitHub
# refuses every branch, including `main`. See the same pairing in
# web-host-birth-environment.tf and infra-privileged-environment.tf.
resource "github_repository_environment_deployment_policy" "workspaces_luks_cutover_main" {
  repository     = "soleur"
  environment    = github_repository_environment.workspaces_luks_cutover.environment
  branch_pattern = "main"
}
