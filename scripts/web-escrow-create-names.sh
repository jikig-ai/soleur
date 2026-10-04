#!/usr/bin/env bash
# web-escrow-create-names.sh <out-file> -- list the NAMES in the Doppler config prd_workspaces_luks_web (#9377).
#
# The single chokepoint of the live names precondition in .github/workflows/apply-web-escrow-create.yml (the
# `names` and `reread` steps call it and nothing else reads Doppler names there). It never reads a value:
# the only Doppler verb is `doppler secrets --only-names`.
#
# TOKEN. `doppler secrets` reads DOPPLER_TOKEN, and the ambient DOPPLER_TOKEN of the job is the Tier-A token that
# resolves prd_terraform only; it cannot read the web-class config. The Terraform provider token reaches this script
# as TF_VAR_doppler_token_tf (through `doppler run --name-transformer tf-var`) and is handed to that ONE doppler call
# as DOPPLER_TOKEN. An unset or empty provider token is exit 2: this script never falls back to the ambient token.
#
# OUTPUT. The names go to <out-file> only (the repo is public and the listing carries every inherited `prd`
# names); stdout and stderr stay empty on success. A failed, empty or unrecognised read is exit 3: "could not read"
# is never "absent". The tokeniser is the one scripts/check-web-host-escrow-config.sh read_names uses.
#
# EXIT CODES: 0 names written | 2 usage or no provider token | 3 listing unreadable | 4 out-file not writable | 78 refused under xtrace.
set -uo pipefail
case "$-" in
  *x*) echo "[FATAL] refusing to run under xtrace (a provider token is in scope)" >&2; exit 78 ;;
esac

OUT_FILE="${1:-}"
[[ -n "$OUT_FILE" ]] || { echo "usage: web-escrow-create-names.sh <out-file>" >&2; exit 2; }
if [[ -z "${TF_VAR_doppler_token_tf:-}" ]]; then
  echo "web-escrow-create-names: TF_VAR_doppler_token_tf is unset or empty; refusing to fall back to the ambient DOPPLER_TOKEN (Tier A, cannot read the web-class config)" >&2
  exit 2
fi
command -v doppler >/dev/null 2>&1 || { echo "web-escrow-create-names: doppler CLI not found on PATH" >&2; exit 2; }

CFG=prd_workspaces_luks_web
umask 077
ERRF="$(mktemp "${TMPDIR:-/var/tmp}/escrow-names-err.XXXXXXXX")" || exit 2
trap 'rm -f "${ERRF:?}"' EXIT

out="$(DOPPLER_TOKEN="$TF_VAR_doppler_token_tf" doppler secrets --only-names -p soleur -c "$CFG" --no-check-version 2>"$ERRF")"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  # Redact any Doppler token shape (dp.<kind>.<body>) BEFORE truncating: the stderr is CLI-controlled text.
  echo "web-escrow-create-names: unreadable: config ${CFG} (rc=${rc}): $(LC_ALL=C tr -c '\040-\176' ' ' <"$ERRF" | sed -E 's/dp\.[A-Za-z]+\.[A-Za-z0-9._-]+/dp.REDACTED/g' | head -c 300)" >&2
  exit 3
fi
# Tokenise the table: every run of [A-Za-z0-9_] on its own line. Borders and rules fall away.
toks="$(printf '%s\n' "$out" | tr -c 'A-Za-z0-9_\n' '\n' | grep -E '^[A-Za-z0-9_]+$' || true)"
if ! grep -qx 'NAME' <<<"$toks"; then
  echo "web-escrow-create-names: unreadable: config ${CFG}: output shape unrecognised (no NAME header), refusing to read it as an empty listing" >&2
  exit 3
fi
names="$(grep -vx 'NAME' <<<"$toks" || true)"
if [[ -z "$names" ]]; then
  echo "web-escrow-create-names: unreadable: config ${CFG}: the listing is empty, which a failed read and a truly empty config both produce; not treated as absence" >&2
  exit 3
fi
printf '%s\n' "$names" > "${OUT_FILE:?}" || { echo "web-escrow-create-names: cannot write the out-file" >&2; exit 4; }
