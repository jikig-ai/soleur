#!/usr/bin/env bash
# web-host-escrow-preflight.sh -- the escrow readiness check as a fail-closed workflow step (#9377, decision B1).
#
# The ONE reusable unit every job that can create or replace hcloud_server.web[...] runs before it changes anything
# (`run: bash scripts/web-host-escrow-preflight.sh`, DOPPLER_TOKEN in the step's env). A future rebirth workflow copies
# one line, not a credential plumbing recipe. plugins/soleur/test/web-host-escrow-preflight-census.test.ts pins that
# every host-creating job carries it; scripts/web-host-escrow-preflight.test.sh pins this file's behaviour.
#
# The checker's --live mode needs a token that can list BOTH Doppler configs (a workplace-scope token; a step's own
# prd_terraform token is config-scoped and exits 3). That provider token is TF_VAR_doppler_token_tf (exported, masked,
# by the Tier-B loader) or, in the legacy arm, the prd_terraform secret DOPPLER_TOKEN_TF. Order, and why:
#   1. refuse xtrace FIRST: a trace echoes a credential the moment it is bound (#7797), and the fallback read binds one.
#   2. the environment token wins; otherwise read exactly ONE named secret with the step's token. Never `doppler run`
#      (the checker would inherit every prd_terraform secret) and never an ambient login.
#   3. shape-check the fallback value BEFORE echoing anything, then ::add-mask:: it. A prd_terraform value that could be
#      planted cannot then carry a newline or a workflow directive into the log.
#   4. an empty or unreadable token fails here, BEFORE the checker.
#   5. hand the token to the checker through its environment only (never argv, a file or GITHUB_ENV) and fail closed with
#      the checker's own exit code (1 contract violated, 2 usage, 3 unreadable; none is ever read as success).
#   6. the checker runs in ESCROW_ADVISORY=count mode: the repo is public and this step runs on every birth, so the
#      prd-root secret NAMES it would list as advisories are reduced to a count in the job log (the local --live run
#      keeps the names).
#   7. on a red run the cause must be readable WITHOUT the step log: the checker's FAIL/CAUSE/NOTE/unreadable lines
#      (names and fixed sentences only, one line each, token shapes already redacted by the checker) are re-emitted as
#      ::error:: annotations. The legacy-arm read keeps a scrubbed 300-byte tail of its stderr (every dp.<kind>.<body>
#      shape and the literal value redacted, newlines flattened) so an auth failure is distinguishable from a missing
#      secret; a value is never printed.
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to trace: this step handles a Doppler provider token (see #7797)\n' >&2; exit 78 ;;
esac

tok="${TF_VAR_doppler_token_tf:-}"
if [[ -z "$tok" ]]; then
  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
    echo "::error::escrow preflight: neither TF_VAR_doppler_token_tf nor DOPPLER_TOKEN is set; no Doppler credential to read the web-class config with. Birth aborted before any change."
    exit 2
  fi
  errf="$(mktemp "${TMPDIR:-/var/tmp}/escrow-preflight-err.XXXXXXXX")" || { echo "::error::escrow preflight: mktemp failed. Birth aborted before any change."; exit 1; }
  trap 'rm -f "${errf:?}"' EXIT
  rc=0
  tok="$(doppler secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain 2>"$errf")" || rc=$?
  if [[ "$rc" -ne 0 || -z "$tok" ]]; then
    # The stderr of a failed read is CLI-controlled text: flatten it to one line, redact every Doppler token shape and the
    # literal value (a CLI that echoed what it was handed), then cut it. Never the stdout, which may hold the value.
    why="$(tr '\r\n' '  ' <"$errf" | sed -E 's/dp\.[A-Za-z]+\.[A-Za-z0-9._-]+/dp.REDACTED/g')"
    [[ -z "$tok" ]] || why="${why//"$tok"/REDACTED}"
    echo "::error::escrow preflight: could not read DOPPLER_TOKEN_TF from prd_terraform (rc=${rc}, or empty). An unreadable token is not a passed check. Birth aborted before any change. Doppler said: ${why:0:300}"
    exit 1
  fi
  if [[ ! "$tok" =~ ^dp\.pt\.[A-Za-z0-9]+$ ]]; then
    echo "::error::escrow preflight: the DOPPLER_TOKEN_TF value in prd_terraform is not a Doppler personal token shape (dp.pt.*); refusing to use it. Birth aborted before any change."
    exit 1
  fi
  printf '::add-mask::%s\n' "$tok"
fi

rc=0
out="$(DOPPLER_TOKEN="$tok" ESCROW_ADVISORY=count bash "$(dirname "${BASH_SOURCE[0]}")/check-web-host-escrow-config.sh" --live 2>&1)" || rc=$?
[[ -z "$out" ]] || printf '%s\n' "$out"
if [[ "$rc" -ne 0 ]]; then
  # Re-emit the cause lines as annotations (capped: GitHub shows ten per step), one line each.
  while IFS= read -r line; do
    line="${line//[^[:print:]]/ }"
    printf '::error::%s\n' "${line:0:600}"
  done < <(printf '%s\n' "$out" | grep -E '^escrow-split-contract:(FAIL|CAUSE|NOTE|unreadable)' | head -n 6)
  echo "::error::web-host escrow preflight failed (exit ${rc}): the escrow-split-contract annotations above name the cause. Birth aborted before any change."
  exit "$rc"
fi
