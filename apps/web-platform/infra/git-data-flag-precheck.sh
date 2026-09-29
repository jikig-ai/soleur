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
# MODE-AWARE READ (#8211 PR2). `FLAG_MODE` (default proof) changes what flag==true means:
#   proof    -> flag==true refuses verdict=flag_already_true (the store must not be live)
#   flip     -> flag==true is RESUME ARM B, not an error: prints flag=true resume=arm_b, exit 0
#               (a prior flip died after the write; the workflow routes to redeploy+assert)
#   rollback -> flag==true is the EXPECTED entry: prints flag=true; flag!=true exits 0 with
#               verdict-free flag=off + mode=rollback nothing_to_rollback marker
#   unfreeze -> reads like proof (flag value irrelevant to the sentinel decision)
#
# WRITE PATH (#8211 PR2 / #8573 seam). When FLAG_WRITE_VALUE is set to `true` or `false`, the
# step writes GIT_DATA_STORE_ENABLED through the dedicated write credential
# DOPPLER_TOKEN_GIT_DATA_FLAG (read/write on `prd`, environment-bound — never
# DOPPLER_TOKEN_WRITE, which is prd_terraform-scoped) and NOTHING ELSE in this file's flow
# runs: write mode returns after the read-back, before the pin/TOFU probes. Absence of the
# credential refuses verdict=flag_write_credential_absent (exit 5) BEFORE any remote call.
#   write form  : printf '%s' "$value" | doppler secrets set GIT_DATA_STORE_ENABLED …
#                 >/dev/null — stdin carries the value (never argv), stdout is discarded
#                 (doppler prints the whole config on set)
#   read-back   : the SAME write token re-reads the flag with --no-exit-on-missing-secret and
#                 must return exactly the written value, else verdict=flag_write_readback_failed
#   success     : flag_write=ok value=<written>
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

# <stderr-file> -> one fixed word. Matched on doppler's own error text; the text is never printed.
reason_of() {
  if grep -qiF 'Invalid Auth token' "$1"; then echo auth_invalid
  elif grep -qiE 'does not have access|forbidden|\b403\b' "$1"; then echo forbidden
  elif grep -qiF 'Could not find requested config' "$1"; then echo config_not_found
  elif grep -qiE 'dial tcp|no such host|connection refused|i/o timeout|timeout|unable to connect|tls handshake|network is unreachable' "$1"; then echo network
  else echo unknown
  fi
}

FLAG_MODE="${FLAG_MODE:-proof}"
case "$FLAG_MODE" in
  proof|flip|rollback|unfreeze) : ;;
  *) echo "::error title=git-data-flag-precheck::verdict=flag_mode_invalid mode=${FLAG_MODE}"; exit 2 ;;
esac

# ---- Write path (#8573): returns before the read probes --------------------------
if [ -n "${FLAG_WRITE_VALUE:-}" ]; then
  case "$FLAG_WRITE_VALUE" in
    true|false) : ;;
    *) echo "::error title=git-data-flag-precheck::verdict=flag_write_value_invalid value=${FLAG_WRITE_VALUE}"; exit 2 ;;
  esac
  if [ -z "${DOPPLER_TOKEN_GIT_DATA_FLAG:-}" ]; then
    echo "::error title=git-data-flag-precheck::verdict=flag_write_credential_absent — DOPPLER_TOKEN_GIT_DATA_FLAG unset; the #8573 write seam is not provisioned. Never substitute DOPPLER_TOKEN_WRITE (prd_terraform-scoped)."
    echo "[git-data-flag-precheck] verdict=flag_write_credential_absent"
    exit 5
  fi
  ERRF="$(mktemp)" || refuse "flag_write_failed reason=unknown rc=95"
  trap 'rm -f "$ERRF"' EXIT
  # stdin carries the value (never argv); stdout discarded (doppler echoes the config).
  if ! printf '%s' "$FLAG_WRITE_VALUE" | DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" \
        doppler secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd >/dev/null 2>"$ERRF"; then
    echo "::error title=git-data-flag-precheck::verdict=flag_write_failed reason=$(reason_of "$ERRF")"
    echo "[git-data-flag-precheck] verdict=flag_write_failed"
    exit 5
  fi
  # Fail-closed read-back with the same credential — the write is not proven until read.
  rb="$(DOPPLER_TOKEN="$DOPPLER_TOKEN_GIT_DATA_FLAG" doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd 2>"$ERRF")" || {
    echo "::error title=git-data-flag-precheck::verdict=flag_write_readback_failed reason=$(reason_of "$ERRF")"
    echo "[git-data-flag-precheck] verdict=flag_write_readback_failed"
    exit 5
  }
  if [ "$rb" != "$FLAG_WRITE_VALUE" ]; then
    echo "::error title=git-data-flag-precheck::verdict=flag_write_readback_failed reason=value_mismatch"
    echo "[git-data-flag-precheck] verdict=flag_write_readback_failed reason=value_mismatch"
    exit 5
  fi
  echo "flag_write=ok value=${FLAG_WRITE_VALUE}"
  exit 0
fi

if [ -z "${DOPPLER_TOKEN:-}" ]; then
  refuse flag_token_absent
fi

ERRF="$(mktemp)" || refuse "flag_read_failed reason=unknown rc=95"
trap 'rm -f "$ERRF"' EXIT

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

# Mode-aware flag read (#8211 PR2): flag==true is a refusal only in proof; on flip it is
# resume arm B (a prior flip died after the write — the workflow re-runs redeploy+assert);
# on rollback it is the expected entry.
if [ "$flag" = true ]; then
  case "$FLAG_MODE" in
    proof|unfreeze) refuse flag_already_true ;;
    flip)
      echo "flag=true resume=arm_b"
      # fall through to the pin/TOFU probes — a resumed flip still needs the pin file
      ;;
    rollback)
      echo "flag=true mode=rollback"
      ;;
  esac
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

case "$FLAG_MODE:$flag" in
  *:true) : ;;  # the mode-aware branch above already printed flag=true
  rollback:*)
    # rollback on a flag that is not true: nothing to take off. Not a refusal — the desired
    # post-state (flag off) already holds; the workflow exits 0 on this marker.
    echo "flag=off mode=rollback verdict=nothing_to_rollback" ;;
  *:) echo "flag=unset" ;;   # flag empty
  *) echo "flag=off" ;;
esac
exit 0
