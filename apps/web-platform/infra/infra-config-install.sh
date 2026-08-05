#!/usr/bin/env bash
# infra-config-install.sh — pinned root-run escalation helper for the
# /hooks/infra-config webhook handler (#4827, Ref #4804).
#
# WHY THIS EXISTS: infra-config-apply.sh runs as User=deploy (webhook.service).
# Its managed files live in root:root 0755 destination directories
# (/usr/local/bin, /etc/systemd/system, /etc/webhook). The deploy user cannot
# mktemp inside those dirs — EACCES — so the handler could never land a single
# file (the #4827 bug: every push wrote 0 files). systemd ReadWritePaths elevates
# the mount namespace to read-write but does NOT override DAC ownership.
#
# THE FIX: the handler base64-decodes each payload, then invokes THIS helper via a
# wildcard-free sudoers grant
# (Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install). sudo
# permits the bare command with ANY arguments — so the SECURITY BOUNDARY is here,
# not in sudoers: the helper hardcodes the allowlisted destinations (the DEST_SPEC
# table below is the authority; infra-config-install.test.sh pins it in lockstep
# with infra-config-apply.sh's FILE_MAP) and refuses anything else. Because the helper runs as root it has no EACCES problem in the
# dest dirs: it mktemps in the destination directory itself and does a
# same-filesystem atomic rename.
#
# PAYLOAD IS READ FROM STDIN, NOT A FILE PATH (#4827 security review, P1 fix).
# An earlier design passed a staged file path as $1; because the staging dir
# (/var/lock) is deploy-writable, a deploy user invoking `sudo infra-config-install`
# directly could swap that path to a symlink → /etc/shadow (etc.) in the window
# between the helper's owner/symlink check and its `cp`, and root would copy a
# root-only file into a world-readable 0755 dest (confidentiality break / privesc).
# Reading the payload from STDIN removes the on-disk attacker-controlled source
# entirely: the redirect (`< file`) is opened by the DEPLOY user before sudo
# elevates, so a deploy user can only ever feed bytes they could already read —
# `sudo infra-config-install <dest> <mode> <owner> < /etc/shadow` fails at open as
# deploy. There is no path to swap, so no TOCTOU.
#
# CONTRACT (exit codes consumed by infra-config-apply.sh's per-file accounting):
#   0 = installed
#   1 = install failure (mktemp/write/chmod/chown/mv)
#   2 = usage error (wrong arg count)
#   3 = rejected (dest not in allowlist, or mode/owner mismatch) → install_rejected
#
# PRIVILEGE-ESCALATION HARDENING (#4827 security review):
#  - The sudoers grant `deploy ALL=(root) NOPASSWD: /usr/local/bin/infra-config-install`
#    lets the deploy user invoke this helper DIRECTLY with arbitrary args — not
#    only through the handler. So mode + owner are NOT trusted from the caller:
#    they are derived from an authoritative per-dest table below, and the helper
#    REJECTS any call whose supplied mode/owner disagrees. This blocks a deploy
#    user from passing mode=4755 to setuid a root-owned binary or owner=deploy to
#    seize one.
#  - /etc/sudoers.d/* is deliberately NOT in this table. The grant-definition file
#    is the one file whose content-write is an unbounded escalation (a deploy user
#    could install `NOPASSWD: ALL`); visudo only checks syntax, not policy, so the
#    helper cannot safely validate it. It is managed root-only (the SSH
#    handler-bootstrap bridge + cloud-init write_files), never via this helper.
set -euo pipefail

readonly LOG_TAG="infra-config-install"

# Authoritative dest → "mode owner" table. MUST stay in lockstep with FILE_MAP in
# infra-config-apply.sh (minus the sudoers entry, which is root-managed). A dest
# absent here is rejected (rc=3). mode/owner come from HERE, not the caller.
declare -rA DEST_SPEC=(
  ["/usr/local/bin/ci-deploy.sh"]="755 root:root"
  ["/usr/local/bin/ci-deploy-wrapper.sh"]="755 root:root"
  ["/etc/systemd/system/webhook.service"]="644 root:root"
  ["/usr/local/bin/cat-deploy-state.sh"]="755 root:root"
  ["/usr/local/bin/canary-bundle-claim-check.sh"]="755 root:root"
  ["/etc/webhook/hooks.json"]="640 root:deploy"
  ["/usr/local/bin/cat-infra-config-state.sh"]="755 root:root"
  ["/usr/local/bin/inngest-enumerate-reminders.sh"]="755 root:root"
  ["/usr/local/bin/inngest-rearm-reminders.sh"]="755 root:root"
  ["/usr/local/bin/inngest-wiped-volume-verify.sh"]="755 root:root"
  ["/usr/local/bin/cat-inngest-verify-state.sh"]="755 root:root"
  ["/usr/local/bin/inngest-inventory.sh"]="755 root:root"
  ["/usr/local/bin/git-lock-chardevice-sweep.sh"]="755 root:root"
  ["/usr/local/bin/inngest-registry-probe.sh"]="755 root:root"
  ["/usr/local/bin/inngest-doublefire-probe.sh"]="755 root:root"
  # #7095 — see the FILE_MAP note in infra-config-apply.sh for why this is 640 root:deploy
  # and not the 600 deploy:deploy of the existing /etc/default/webhook-deploy.
  ["/etc/default/soleur-doppler-token"]="640 root:deploy"
  # #7095 — drop-in dests. 644 root:root (systemd reads these as root; no group needs them).
  # These are the dests the guarded mkdir -p below exists for: a *.service.d/ directory does
  # not exist on the host until first written, and mktemp writes INTO it.
  ["/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf"]="644 root:root"
  ["/etc/systemd/system/inngest-heartbeat.service.d/10-inngest-heartbeat-doppler-token.conf"]="644 root:root"
  ["/etc/systemd/system/inngest-server.service.d/10-inngest-server-doppler-token.conf"]="644 root:root"
)

# #7220 AC-B1 — CONTENT PIN for full-unit *.service dests. THE SECURITY PRECONDITION OF THE
# daemon-reload GRANT.
#
# webhook.service matches neither content gate below: not the /etc/default/* env-file grammar,
# not the *.service.d/*.conf drop-in grammar. That was survivable only while nothing made
# systemd ADOPT a rewritten unit — the reload grant is precisely what removes that property.
#
# WHY A DIGEST AND NOT A DIRECTIVE GRAMMAR. The drop-in gate forbids directives (User=,
# ExecStart=, AmbientCapabilities=). That tool cannot work on a full unit, whose entire purpose
# is to carry ExecStart= — a permitted-directive grammar would have to admit the escalation
# primitive itself. Every *.service payload here is a STATIC repo file with zero interpolations,
# so exact bytes are known ahead of time; equality is strictly tighter than any grammar and is
# immune to the parsing asymmetries (line continuations, duplicate keys, case) a line-shaped
# gate must reason about.
#
# Note the sudoers side buys NOTHING on the scope axis for this grant: `systemctl daemon-reload`
# takes no unit argument, so exact-argv pinning cannot narrow WHICH units get adopted. This
# table is the only control that bounds what a reload can pick up ON THIS DELIVERY PATH.
#
# THAT QUALIFIER IS LOAD-BEARING (#7220 review). This is an INTEGRITY control, not a privilege
# boundary: `deploy` is already root-equivalent on this host through the docker group and through
# two ungated chains, one of which is a /usr/local/bin dest in the very DEST_SPEC above. The
# canonical statement of what `deploy` already is — with the three paths and the plan that
# accepted them — lives once, in deploy-inngest-bootstrap.sudoers under
# "WHAT THE `deploy` USER ALREADY IS". Read it before reasoning about what any gate here defends.
# What the pin genuinely buys is that a config-delivery bug cannot silently become a
# unit-definition change on a host with no SSH runbook.
#
# LOCKSTEP: the digest and the unit live in two files. A stale pin does not fail loudly — it
# silently refuses every delivery of the CORRECT unit, bricking the only channel to a host with
# no SSH runbook. `test_service_pin_matches_repo_unit` derives the expected value from the
# committed unit and is what makes the split safe; update both together or that test reds.
declare -rA SERVICE_SHA256=(
  ["/etc/systemd/system/webhook.service"]="01bd79b2eab379620576131acf34c433dbee51a614020fa796370df7028dd2cc"
)

# TEST_DESTDIR redirects writes to a sandbox and skips chown (no root needed),
# exactly as infra-config-apply.sh does. Empty in prod.
DESTDIR="${TEST_DESTDIR:-}"

usage() {
  echo "usage: infra-config-install <canonical-dest> <mode> <owner> < payload" >&2
  exit 2
}

[[ "$#" -eq 3 ]] || usage
dest_canonical="$1"
caller_mode="$2"
caller_owner="$3"

reject() {
  local reason="$1"
  logger -t "$LOG_TAG" "REJECTED: dest=$dest_canonical reason=$reason" 2>/dev/null || true
  echo "ERROR: install rejected ($reason) for $dest_canonical" >&2
  exit 3
}

# --- Allowlist + authoritative mode/owner (canonical dest, before sandbox prefix) ---
spec="${DEST_SPEC[$dest_canonical]:-}"
[[ -n "$spec" ]] || reject "dest_not_allowlisted"
read -r mode owner <<< "$spec"

# Reject any caller whose requested mode/owner disagrees with the authoritative
# table — a deploy user trying to escalate (setuid/chown) is refused, and a
# handler/FILE_MAP drift is surfaced loudly rather than silently overridden.
[[ "$caller_mode" == "$mode" ]] || reject "mode_mismatch:caller=$caller_mode:expected=$mode"
[[ "$caller_owner" == "$owner" ]] || reject "owner_mismatch:caller=$caller_owner:expected=$owner"

# --- Resolve the real write target (sandbox prefix in test mode) ---
dest="${DESTDIR}${dest_canonical}"
dest_dir="$(dirname "$dest")"

# Refuse to write through a symlinked destination (would clobber an unrelated path).
[[ -L "$dest" ]] && reject "dest_symlink"

# --- Atomic install: mktemp IN the dest dir (root can write it), then rename ---
# Same-filesystem rename → atomic. The payload comes from STDIN (see header) so
# there is no caller-controlled source path to symlink-swap.
install_fail() {
  local reason="$1"
  logger -t "$LOG_TAG" "FAILED: dest=$dest_canonical reason=$reason" 2>/dev/null || true
  echo "ERROR: install failed ($reason) for $dest_canonical" >&2
  exit 1
}

# #7095 — create the destination DIRECTORY if absent. mktemp below writes INTO $dest_dir, so a
# dest whose parent does not yet exist fails at mktemp with a bare "mktemp" reason that reads
# like a disk problem. This is safe precisely BECAUSE it sits after the DEST_SPEC allowlist
# check above: $dest_canonical is a reviewed constant from the table, never caller-controlled,
# so this cannot be steered at an arbitrary path. It is required for systemd drop-in dests of
# the form /etc/systemd/system/<unit>.d/, which do not exist on a host until first written.
mkdir -p "$dest_dir" 2>/dev/null || install_fail "mkdir_dest_dir"

tmp="$(mktemp "${dest_dir}/tmp.infra-config-install.XXXXXX" 2>/dev/null)" || install_fail "mktemp"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" || install_fail "write"

# #7095 — SHAPE GATE for env-file dests. REFUSE-TO-INSTALL BEATS INSTALL-AND-BRICK.
#
# An /etc/default/* payload is consumed as a systemd EnvironmentFile by units including the
# webhook that delivers this very file. systemd refuses to start a unit whose EnvironmentFile
# has a malformed line, so a bad render here takes down the remediation channel on a host with
# no operator SSH runbook and no orderable replacement (#7095 Sharp Edge 1b). Validating one
# line at the door is cheap; recovering a bricked webhook is not.
#
# Accepts KEY=VALUE, blank lines, and # comments — the exact grammar systemd parses. Note this
# is the LAST of three layers and the only one that runs on the host: the authoritative gate is
# the `terraform plan` validation on var.doppler_token, which never lets a bad value leave CI.
if [[ "$dest_canonical" == /etc/default/* ]]; then
  # grep -c reads ALL input (no early close), so this cannot SIGPIPE the producer the way
  # `| grep -q` would under `set -o pipefail`. Count lines that are NOT blank, NOT a comment,
  # and NOT a well-formed assignment; anything > 0 is a malformed env file.
  bad_lines="$(grep -cvE '^[[:space:]]*($|#|[A-Za-z_][A-Za-z0-9_]*=)' "$tmp" || true)"
  [[ "$bad_lines" == "0" ]] || reject "envfile_shape:bad_lines=$bad_lines"
fi

# #7103 R2 — SHAPE GATE for systemd drop-in dests. THE SECURITY PRECONDITION OF THE
# RESTART GRANT.
#
# Until now the gate above was the ONLY content validation in this helper, and it is scoped to
# /etc/default/*. The three *.service.d/*.conf dests got none. That was survivable only because
# nothing on this host root-restarted those units, so an unvalidated drop-in sat inert on disk.
# The DROPIN_TRY_RESTART grant added alongside this removes exactly that property.
#
# systemd merges drop-ins AFTER the unit body, so a drop-in is not a weaker write than the unit:
# it can set User=root on vector.service (which runs User=deploy), clear-and-replace ExecStart=
# via the empty-assignment idiom, or add AmbientCapabilities=. webhook.service does not set
# NoNewPrivileges, so nothing downstream re-narrows what a drop-in widens — this gate is the only
# CONTENT CHECK on that path, on the one host with no orderable replacement.
#
# "Content check", not "boundary" (#7220 review): calling it a boundary overstates it, because
# `deploy` is already root-equivalent by three other routes. See "WHAT THE `deploy` USER ALREADY
# IS" in deploy-inngest-bootstrap.sudoers. The lateral-not-escalation argument below is still
# exactly right and is the reason this grammar is acceptable — it just is not the reason the host
# is safe from `deploy`, because it is not.
#
# The permitted grammar is deliberately the NARROWEST that admits the payload we actually ship:
# blank, comment, a bare [Service] header, Environment= and EnvironmentFile=. A directive
# outside it is rejected by name rather than silently dropped. Note this is a per-PHYSICAL-line
# check while systemd parses LOGICAL lines (a trailing backslash continues), and that asymmetry
# is safe in the only direction that matters: a continuation can merge permitted lines into one
# directive, never synthesise a directive whose first physical line this loop did not inspect.
#
# WHAT THIS GATE DOES NOT DEFEND AGAINST, stated plainly so nobody has to re-derive it:
# `Environment=` is permitted, and it can set process-influencing variables — `LD_PRELOAD` being
# the obvious one. Verified adversarially: that payload IS accepted.
#
# It is acceptable HERE, and the reason is specific rather than general. Both units the
# DROPIN_TRY_RESTART grant covers run `User=deploy Group=deploy` (checked, not assumed:
# inngest-bootstrap.sh's heartbeat heredoc and soleur-host-bootstrap.sh's vector heredoc), and
# the handler writing these drop-ins ALREADY runs as deploy. So an env-var injection buys the
# deploy user influence over a process the deploy user already owns — lateral, not escalation.
# `User=` is on the forbidden list precisely so that stays true: without it a drop-in could
# re-point either unit at root and the argument above would collapse.
#
# If a future unit running as root is ever added to RESTART_MAP, this gate is no longer
# sufficient and `Environment=` must be narrowed to an explicit key allowlist.
#
# `grep -c` reads ALL input (no early close), so this cannot SIGPIPE the producer the way
# `| grep -q` would under `set -o pipefail` — same reason as the env-file gate above.
if [[ "$dest_canonical" == /etc/systemd/system/*.service.d/*.conf ]]; then
  dropin_bad_lines="$(grep -cvE '^[[:space:]]*($|#|;|\[Service\][[:space:]]*$|Environment=|EnvironmentFile=)' "$tmp" || true)"
  [[ "$dropin_bad_lines" == "0" ]] || reject "dropin_shape:bad_lines=$dropin_bad_lines"
fi

# #7220 AC-B1 — enforce the content pin declared in SERVICE_SHA256 above.
#
# Ordering is load-bearing: this runs AFTER the DEST_SPEC allowlist (so `dest_canonical` is
# already a known dest, not caller-steered) and BEFORE chmod/chown/mv (so a rejected payload
# never reaches the destination — refuse-to-install, not install-then-fail).
#
# The pattern deliberately does not match drop-ins: `*.service` requires the path to END in
# `.service`, so `<unit>.service.d/<x>.conf` falls to the gate above rather than here.
#
# FAIL-CLOSED on an unpinned *.service dest. If a future dest is added to DEST_SPEC without a
# companion digest, this rejects rather than waving it through — the alternative would make
# forgetting the pin the silent default, which is the failure mode this AC exists to close.
# INVERTED PREDICATE (#7220 review). Keying this on `*.service` left a hole: a future DEST_SPEC
# entry ending .timer/.path/.socket/.target/.mount matches NEITHER this gate nor the drop-in gate
# above, so it would install with ZERO content validation and `daemon-reload` would adopt it —
# and a .path or .timer activates its Unit= target with no start grant at all. Anything under
# /etc/systemd/system that is not a drop-in must carry a digest.
if [[ "$dest_canonical" == /etc/systemd/system/* && "$dest_canonical" != /etc/systemd/system/*.service.d/*.conf ]]; then
  service_pinned="${SERVICE_SHA256[$dest_canonical]:-}"
  [[ -n "$service_pinned" ]] || reject "service_pin:no_pin_for_dest"
  # sha256sum, never diff/cmp: these payloads are read back into journald on failure, and a
  # comparison that can echo its input is how a credential leaks (same reasoning as the
  # mtime-preservation block below).
  service_sha="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')" || service_sha=""
  [[ -n "$service_sha" ]] || install_fail "service_pin_digest"
  [[ "$service_sha" == "$service_pinned" ]] || reject "service_pin:sha_mismatch"
fi

# #7103 R2 3.4 — preserve mtime on a content-identical install.
#
# This MUST live here and not only in the caller. In prod the caller stages into a
# deploy-writable dir and this helper writes its own fresh temp in the destination directory,
# so any mtime the caller preserved on ITS temp is discarded before the rename ever happens.
# The reconciliation predicate keys on mtime, so without this a content-identical re-delivery
# would look newer than the running process on EVERY apply and restart units that are not
# stale — forever, and most visibly on vector, whose restart blinks the very log stream the
# post-apply assertions are read through.
#
# sha256sum, never diff/cmp -l/od: one of these dests is the Doppler credential, and a
# comparison that can echo its input prints the prd token into journald.
if [[ -f "$dest" && ! -L "$dest" ]]; then
  new_sha="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')" || new_sha=""
  old_sha="$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')" || old_sha=""
  if [[ -n "$new_sha" && "$new_sha" == "$old_sha" ]]; then
    touch -r "$dest" "$tmp" 2>/dev/null || true
  fi
fi

chmod "$mode" "$tmp" || install_fail "chmod"
# chown only works as root; skip in sandbox/test mode (mirrors the handler).
if [[ -z "$DESTDIR" ]]; then
  chown "$owner" "$tmp" || install_fail "chown"
fi
mv -f "$tmp" "$dest" || install_fail "mv"

logger -t "$LOG_TAG" "installed: $dest_canonical mode=$mode owner=$owner" 2>/dev/null || true
exit 0
