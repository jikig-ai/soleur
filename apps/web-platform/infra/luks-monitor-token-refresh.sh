#!/usr/bin/env bash
# #8632 — replace web-1's prd_workspaces_luks boot token in the luks-monitor EnvironmentFile, then
# prove the daily probe runs with it.
#
# Runs ON web-1 as root. Shipped and invoked by the `refresh-host-token` job in
# .github/workflows/workspaces-luks-verify.yml (dispatch-only, gated by the workspaces-luks-cutover
# environment), over the cutover SSH channel that ADR-119 §(e) grants for delivering standing
# observability config to web-1. The token arrives on STDIN, never argv, and is never printed.
#
# Why this exists: the one-time cutover (workspaces-cutover.sh) was the only writer of
# /etc/default/luks-monitor, and it now refuses to run. A Terraform rotation of
# doppler_service_token.workspaces_luks revokes the old token and republishes
# WORKSPACES_LUKS_BOOT_TOKEN, so without this path the host keeps a dead token and the daily
# luks-monitor.timer emits doppler_unreachable every day.
#
# The replace statement below is copied from workspaces-cutover.sh, and
# workspaces-luks-host-token-refresh.test.sh asserts the two stay identical.
#
# What it does NOT do: it never touches the volume, the mapper or the passphrase, and it never
# reboots. Revoking the old token cannot lock the volume: crypttab uses keyfile `none`, so nothing
# unlocks with this token at boot (#8632).
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# A literal, not an env override: this runs as root, and an env-directed write target is a path an
# attacker who controls the environment could aim anywhere. The gate rewrites this line in a scratch copy.
ENVF="/etc/default/luks-monitor"
UNIT="luks-monitor.service"

say() {
  printf '[luks-token-refresh] %s\n' "$*"
  # The luks-monitor tag is the one vector.toml ships to Better Stack (see luks-monitor.service).
  logger -t luks-monitor -- "SOLEUR_LUKS_HOST_TOKEN_REFRESH $*" 2>/dev/null || true
}
fail() { say "result=fail reason=$1"; exit "${2:-1}"; }

rc=0
DOPPLER_TOKEN="$(head -c 4096 | tr -d '\r\n')" || rc=$?
[ "$rc" -eq 0 ] || fail token_read_failed
[ -n "$DOPPLER_TOKEN" ] || fail token_empty 64
# A service token, one word. A personal (dp.pt.) or CLI token here would be a wrong-credential
# delivery, and whitespace would split the EnvironmentFile assignment.
case "$DOPPLER_TOKEN" in
  *[[:space:]]*) fail token_shape_invalid 64 ;;
  dp.st.?*) : ;;
  *) fail token_shape_invalid 64 ;;
esac

systemctl cat "$UNIT" >/dev/null 2>&1 || fail unit_absent
# The cutover created this file with the baked DSN. Refuse to invent it: an absent file means the
# host is not in the state this path was written for.
[ -f "$ENVF" ] || fail envfile_absent

before="$(grep -v '^DOPPLER_TOKEN=' "$ENVF" 2>/dev/null || true)"

wrc=0
( umask 077; { grep -v '^DOPPLER_TOKEN=' "$ENVF" 2>/dev/null || true; printf 'DOPPLER_TOKEN=%s\n' "$DOPPLER_TOKEN"; } > "${ENVF}.tmp" ) \
  && mv "${ENVF}.tmp" "$ENVF" && chmod 600 "$ENVF" || wrc=$?
if [ "$wrc" -ne 0 ]; then
  rm -f "${ENVF}.tmp"
  fail envfile_write_failed
fi

after="$(grep -v '^DOPPLER_TOKEN=' "$ENVF" 2>/dev/null || true)"
[ "$before" = "$after" ] || fail envfile_other_lines_changed
[ "$(grep -c '^DOPPLER_TOKEN=' "$ENVF")" = 1 ] || fail envfile_token_line_count
grep -qxF "DOPPLER_TOKEN=${DOPPLER_TOKEN}" "$ENVF" || fail envfile_token_mismatch

# THE PROOF. luks-monitor is a oneshot, so `start` blocks until the probe finishes and returns its
# status. The probe reads WORKSPACES_LUKS_KEY with this token and re-tests the passphrase, so a
# green start is the evidence the new token works. Bounded: a hung probe must not hold the SSH open
# to the job timeout.
src=0
timeout 300 systemctl start "$UNIT" || src=$?
if [ "$src" -ne 0 ]; then
  journalctl -u "$UNIT" -n 40 --no-pager 2>/dev/null | grep -E '\[luks-monitor\] (FAIL|PASS|WARN)' | tail -5 || true
  fail unit_start_failed
fi
result="$(systemctl show -p Result --value "$UNIT" 2>/dev/null || true)"
[ "$result" = success ] || fail unit_result_not_success

sha16="$(printf '%s' "$DOPPLER_TOKEN" | sha256sum | cut -c1-16)"
logger -t luks-monitor -- "SOLEUR_LUKS_HOST_TOKEN_REFRESH result=ok" 2>/dev/null || true
printf '[luks-token-refresh] result=ok token_sha256_16=%s\n' "$sha16"
