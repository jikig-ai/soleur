#!/usr/bin/env bash
# #8632 — replace web-1's prd_workspaces_luks boot token in the luks-monitor EnvironmentFile.
#
# Runs ON web-1 as root. Delivered and invoked by terraform_data.luks_monitor_token_install
# (workspaces-luks.tf), which fires whenever the token's hash changes, i.e. in the same apply that
# rotates doppler_service_token.workspaces_luks. ADR-119's 2026-09-24 addendum records that this
# resource owns the DOPPLER_TOKEN= line after the cutover's first write. The token arrives on STDIN
# (one line), never as an argument to any program, and is never printed.
#
# Order matters and is the point of this file:
#   1. PROVE the new token can read WORKSPACES_LUKS_KEY, using the same pinned form luks-monitor.sh
#      uses. A token that cannot read the key never replaces one that can.
#   2. Rewrite ONLY the DOPPLER_TOKEN= line, atomically, keeping every other line byte for byte.
#      An absent file is created first (never before step 1).
#   3. Re-check the file; on any mismatch, restore the previous file (or its absence).
#
# It never starts luks-monitor.service. The daily probe's health (mount, escrow, readyz) is a
# separate question, answered by workspaces-luks-verify.yml, and must not decide whether a token
# rotation lands. It never touches the volume, the mapper or the passphrase, and never reboots.
#
# The replace statement is copied from workspaces-cutover.sh, which made the file's first write;
# workspaces-luks-host-token-refresh.test.sh asserts the two stay identical.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# A literal, not an env override: this runs as root, and an env-directed write target is a path an
# attacker who controls the environment could aim anywhere. The gate rewrites this line in a scratch copy.
ENVF="/etc/default/luks-monitor"
# The tag vector.toml's host_scripts_journald source ships to Better Stack (same as luks-monitor.sh).
LOG_TAG="luks-monitor"

say() {
  # logger first: if the SSH channel drops, printf can take SIGPIPE, and the reason must already be
  # on its way off-box by then.
  logger -t "$LOG_TAG" -- "SOLEUR_LUKS_HOST_TOKEN_REFRESH $*" 2>/dev/null || true
  printf '[luks-token-refresh] %s\n' "$*"
}
fail() { say "result=fail reason=$1"; exit "${2:-1}"; }

# --- 0. Exactly one line of input -----------------------------------------------------------
DOPPLER_TOKEN=""
IFS= read -r DOPPLER_TOKEN
DOPPLER_TOKEN="${DOPPLER_TOKEN%$'\r'}"
[ -n "$DOPPLER_TOKEN" ] || fail token_empty 64
extra=""
if IFS= read -r extra || [ -n "$extra" ]; then
  fail token_multiline 64
fi
# A service token is `dp.st.<config>.<random>`. The allowlist matters beyond shape: root SOURCES
# this file (workspaces-luks-emit.sh), so a `$(...)` or backtick in the value would run as root.
case "$DOPPLER_TOKEN" in
  *[!A-Za-z0-9._-]*) fail token_shape_invalid 64 ;;
  dp.st.?*) : ;;
  *) fail token_shape_invalid 64 ;;
esac

# --- 1. Preconditions -----------------------------------------------------------------------
# Root writes here, so a symlink (dangling or not) is refused rather than written through.
[ -L "$ENVF" ] && fail envfile_symlink
# An ABSENT file is created in step 3, after the proof, the way workspaces-cutover.sh does
# (`touch` + `chmod 600`). #8632's first apply found web-1 without one: cloud-init bakes the DSN
# line only at a host's birth, and the cutover's write had not survived. Refusing left the host with
# no token at all while the old one was being revoked (#8706 tracks the missing DSN line).
created=0
before=""
if [ -e "$ENVF" ]; then
  [ -f "$ENVF" ] || fail envfile_not_regular
  rc=0
  before="$(grep -v '^DOPPLER_TOKEN=' "$ENVF")" || rc=$?
  # grep exits 1 when every line is a token line (nothing left), 2 on a read error.
  [ "$rc" -le 1 ] || fail envfile_unreadable
fi

# --- 2. Prove the new token before it replaces the old one ----------------------------------
# The pinned form from luks-monitor.sh. The token rides the environment, not argv; HOME=/root and
# no DOPPLER_CONFIG_DIR match the unit (#6536). The value read is discarded immediately.
unset DOPPLER_CONFIG_DIR
key=""
rc=0
key="$(HOME=/root DOPPLER_ENABLE_VERSION_CHECK=false DOPPLER_TOKEN="$DOPPLER_TOKEN" \
  doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks 2>/dev/null)" || rc=$?
if [ "$rc" -ne 0 ] || [ -z "$key" ]; then
  key=""
  fail token_read_failed
fi
key=""

# --- 3. Rewrite the token line --------------------------------------------------------------
if [ ! -e "$ENVF" ]; then
  # Empty until the rewrite below replaces it with a tmp born 0600 (and chmod 600 after the mv).
  ( umask 077; : > "$ENVF" ) || fail envfile_create_failed
  created=1
fi
# The previous content is kept in memory, not in a backup file, so no second on-disk copy of the
# old token ever exists. The trailing `x` preserves a final newline through $(...).
orig="$(cat "$ENVF"; printf x)" || fail envfile_unreadable
orig="${orig%x}"
# A stale .tmp (or a symlink planted there) must not be written through.
rm -f "${ENVF}.tmp"

wrc=0
( umask 077; { grep -v '^DOPPLER_TOKEN=' "$ENVF" 2>/dev/null || true; printf 'DOPPLER_TOKEN=%s\n' "$DOPPLER_TOKEN"; } > "${ENVF}.tmp" ) \
  && mv "${ENVF}.tmp" "$ENVF" && chmod 600 "$ENVF" || wrc=$?
if [ "$wrc" -ne 0 ]; then
  rm -f "${ENVF}.tmp"
  fail envfile_write_failed
fi

restore() {
  rm -f "${ENVF}.tmp"
  if [ "$created" = 1 ]; then
    # This run created the file, so the previous state is ABSENT, not empty.
    rm -f "$ENVF"
  else
    ( umask 077; printf '%s' "$orig" > "${ENVF}.tmp" ) && mv "${ENVF}.tmp" "$ENVF" && chmod 600 "$ENVF"
  fi
  fail "$1"
}
after="$(grep -v '^DOPPLER_TOKEN=' "$ENVF")"
[ "$before" = "$after" ] || restore envfile_other_lines_changed
[ "$(grep -c '^DOPPLER_TOKEN=' "$ENVF")" = 1 ] || restore envfile_token_line_count
# Compared in the shell, so the token never becomes an argument to grep.
[ "$(sed -n 's/^DOPPLER_TOKEN=//p' "$ENVF")" = "$DOPPLER_TOKEN" ] || restore envfile_token_mismatch

if [ "$created" = 1 ]; then
  say "result=ok created_envfile=1"
else
  say "result=ok"
fi
