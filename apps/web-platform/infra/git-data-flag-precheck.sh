#!/usr/bin/env bash
#
# git-data flag precheck — fail-closed read of GIT_DATA_STORE_ENABLED (#8189 D-3, blocker 1).
#
# Runs as its OWN step of .github/workflows/git-data-cutover.yml, before the SSH bridge and
# before the git-data root key is fetched. It is the only step bound to DOPPLER_TOKEN_PRD (as
# DOPPLER_TOKEN), so the `prd` read token never reaches a process that handles host bytes.
#
# WHY IT EXISTS. The deleted `read_flag` ran `doppler secrets get ... || echo ""` under a token
# scoped to prd_terraform: the scope error became "", and "" read as "flag unset". A read that
# cannot tell "absent" from "could not read" has to stop the run instead.
#
# MEASURED DOPPLER CLI SEMANTICS (v3.75.3, 2026-09-15):
#   doppler secrets get <absent> --plain --no-exit-on-missing-secret -p soleur -c <cfg>
#     -> exit 0, empty stdout
#   the same call WITHOUT --no-exit-on-missing-secret
#     -> exit 1 ("Could not find requested secret")
#   a nonexistent (or unauthorized) config, even WITH the flag
#     -> exit 1
# So with the flag, exit 0 + empty stdout means "absent", and every non-zero exit is a read
# failure (wrong scope, revoked token, network) — never "unset".
#
# SCOPE. A service token reads the config it is bound to. So after a successful flag read the
# SAME token must also read the reserved secrets Doppler injects into every config
# (DOPPLER_PROJECT, DOPPLER_CONFIG — docs.doppler.com/docs/secrets › reserved secrets) as exactly
# `soleur` / `prd`. Without that, a token bound to another config reads the flag as absent and the
# run proceeds as "unset" — the exact defect the deleted read_flag had.
#
# VERDICTS (the only output; the flag value, the reserved values and doppler's stderr are never
# printed — stderr goes to a temp file and is reduced to one fixed reason word):
#   DOPPLER_TOKEN empty      -> verdict=flag_token_absent                       exit 5 (no doppler call)
#   a read exits non-zero    -> verdict=flag_read_failed reason=<word> rc=<n>   exit 5
#        <word>: auth_invalid | forbidden | config_not_found | network | unknown
#   reserved values differ   -> verdict=flag_read_failed reason=scope_mismatch  exit 5
#   exactly `true`           -> verdict=flag_already_true                       exit 5
#   empty                    -> flag=unset                                       exit 0
#   any other value          -> flag=off                                         exit 0
# `true` is compared exactly (no case folding, no trimming): the app enables the store only on
# process.env.GIT_DATA_STORE_ENABLED === "true" (apps/web-platform/server/workspace-resolver.ts).
#
# GIT-DATA HOST-KEY PIN (#7226, plan D3). The same step, with the same `prd` token, reads
# GIT_DATA_SSH_HOST_KEY (published by Terraform when git-data is born or replaced) with the same
# --no-exit-on-missing-secret semantics, validates its shape, and writes it to
# $RUNNER_TEMP/git-data.pin for the workflow's "Write git-data ssh_config" step. The raw value is
# never printed: only its SHA256 fingerprint, computed after validation.
#   the read exits non-zero  -> verdict=git_data_host_key_unavailable reason=<word> rc=<n> exit 5
#        <word>: the same classification as the flag read (auth_invalid | forbidden |
#        config_not_found | network | unknown), through the same read_secret / reason_of
#   exit 0 + empty           -> verdict=git_data_host_key_unavailable reason=absent       exit 5
#   not one ED25519 key line -> verdict=git_data_host_key_unavailable reason=invalid      exit 5
#   RUNNER_TEMP unusable     -> verdict=pin_write_failed                                  exit 5
#   valid                    -> git_data_pin=present fp=SHA256:<fingerprint>
# Before the pin read it prints one informational line about the app's unpinned fallback arm:
#   TOFU_ARM present|absent|unknown — whether the file GIT_AUTH_TS_PATH names (default: the
#   checkout's apps/web-platform/server/git-auth.ts) still carries the trust-on-first-use ssh
#   option itself (the accept-new value of the host-key-checking option, matched case-insensitively). The
#   probe keys on the BEHAVIOUR, not on a constant's name: renaming the constant must not flip it
#   to absent. The needle is built by concatenation so this file is not itself a hit for
#   tests/scripts/test-no-tofu-ssh.sh. `present` also raises a ::warning: that arm must be
#   deleted (#5914) before GIT_DATA_STORE_ENABLED is ever set.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Guards the one write below whose operand comes
# from the environment ($RUNNER_TEMP).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

refuse() { # <verdict-detail>
  echo "[git-data-flag-precheck] verdict=$1"
  echo "::error title=git-data-flag-precheck::verdict=$1"
  exit 5
}

if [ -z "${DOPPLER_TOKEN:-}" ]; then
  refuse flag_token_absent
fi

ERRF="$(mktemp)" || refuse "flag_read_failed reason=unknown rc=95"
trap 'rm -f "$ERRF"' EXIT

# <stderr-file> -> one fixed word. Matched on doppler's own error text; the text is never printed.
reason_of() {
  if grep -qiF 'Invalid Auth token' "$1"; then echo auth_invalid
  elif grep -qiE 'does not have access|forbidden|\b403\b' "$1"; then echo forbidden
  elif grep -qiF 'Could not find requested config' "$1"; then echo config_not_found
  elif grep -qiE 'dial tcp|no such host|connection refused|i/o timeout|timeout|unable to connect|tls handshake|network is unreachable' "$1"; then echo network
  else echo unknown
  fi
}

# read_secret <NAME> <failure-verdict> [extra-flag] -> sets VAL; on a non-zero exit refuses with
# "<failure-verdict> reason=<word> rc=<n>", so every read in this file classifies its failure the
# same way.
VAL=""
read_secret() {
  local rc=0
  : > "$ERRF"
  VAL="$(doppler secrets get "$1" --plain ${3:+"$3"} -p soleur -c prd 2>"$ERRF")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    refuse "$2 reason=$(reason_of "$ERRF") rc=${rc}"
  fi
}

read_secret GIT_DATA_STORE_ENABLED flag_read_failed --no-exit-on-missing-secret
flag="$VAL"
read_secret DOPPLER_PROJECT flag_read_failed
project="$VAL"
read_secret DOPPLER_CONFIG flag_read_failed
config="$VAL"
if [ "$project" != soleur ] || [ "$config" != prd ]; then
  refuse "flag_read_failed reason=scope_mismatch"
fi

if [ "$flag" = true ]; then
  refuse flag_already_true
fi

# --- TOFU_ARM (informational) ---
GIT_AUTH_TS="${GIT_AUTH_TS_PATH:-$(dirname "$0")/../server/git-auth.ts}"
if [ ! -r "$GIT_AUTH_TS" ] || [ ! -f "$GIT_AUTH_TS" ]; then
  echo "TOFU_ARM unknown"
elif grep -qiF "StrictHostKeyChecking=accept-""new" "$GIT_AUTH_TS"; then
  echo "TOFU_ARM present"
  echo "::warning title=git-data-flag-precheck::TOFU_ARM present - the app still carries the unpinned git-data fallback (#5914); it must be deleted before GIT_DATA_STORE_ENABLED is ever set"
else
  echo "TOFU_ARM absent"
fi

# --- git-data host-key pin ---
# twin: .github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh (ED25519 arm);
# apps/web-platform/server/git-data-replication.ts (resolveGitDataHostKeyPin);
# apps/web-platform/infra/modules/git-data-userdata/variables.tf (host_ssh_ed25519_public_key)
PIN_RE='^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]{43}$'
read_secret GIT_DATA_SSH_HOST_KEY git_data_host_key_unavailable --no-exit-on-missing-secret
pin="$VAL"
if [ -z "$pin" ]; then
  refuse "git_data_host_key_unavailable reason=absent"
fi
# $PIN_RE unquoted: a quoted right-hand side is a literal string match, not a regex.
if ! [[ $pin =~ $PIN_RE ]]; then
  refuse "git_data_host_key_unavailable reason=invalid"
fi
PIN_OUT="${RUNNER_TEMP:-}/git-data.pin"
if [ -z "${RUNNER_TEMP:-}" ] || ! [[ $PIN_OUT =~ ^/[A-Za-z0-9/_.-]+$ ]]; then
  refuse pin_write_failed
fi
# The regex above already refuses a relative or dot-dot path; the canonical guard is the
# statement plugins/soleur/test/fixture-relative-assert.test.sh can SEE on the write's operand.
assert_fixture_dir "$PIN_OUT"
rm -f "$PIN_OUT" 2>/dev/null || true
if ! printf '%s\n' "$pin" > "$PIN_OUT"; then
  refuse pin_write_failed
fi
fp="$(ssh-keygen -lf "$PIN_OUT" 2>/dev/null | awk '{print $2}')" || fp=""
case "$fp" in
  SHA256:*) : ;;
  *) rm -f "$PIN_OUT"; refuse "git_data_host_key_unavailable reason=invalid" ;;
esac
chmod 0444 "$PIN_OUT" || refuse pin_write_failed
echo "git_data_pin=present fp=${fp}"

if [ -z "$flag" ]; then
  echo "flag=unset"
else
  echo "flag=off"
fi
exit 0
