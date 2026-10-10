#!/usr/bin/env bash
# assert-dev-doppler-scope.sh -- fail closed unless the soleur/dev_scheduled
# Doppler config resolves to environment=dev AND carries no
# SUPABASE_ACCESS_TOKEN. THE ONE COPY of this security boundary
# (#8028 DC-1): it is the only mechanical guard that a dev-scoped CI job never
# holds the account-wide Supabase Management-API token. Consumed by
# .github/workflows/tenant-integration.yml,
# .github/workflows/scheduled-integration-suites.yml, and
# .github/workflows/dev-ledger-reconcile.yml -- extracted because a hardening
# edit to one YAML copy does not flag the others. (scheduled-realtime-probe.yml
# carries a READ-ONLY env=dev check of its own -- it performs no Supabase
# writes and is deliberately out of this contract's scope.) If you change the
# assertion, you change it for every consumer; that is the point.
#
# Every jq call is branched on its exit code: a parse error fails closed,
# never "absent" -- an unreadable absence-proof is not an absence (the
# dev-ledger-reconcile.yml form, which was the strongest of the three inline
# copies this file replaces; its jq rc-branching is preserved verbatim).
#
# Requires: doppler + jq on PATH, DOPPLER_TOKEN exported (dev-scoped service
# token). Names only are read; no secret VALUE is ever fetched.
set -euo pipefail

if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
  echo "::error::DOPPLER_TOKEN is not set; this job cannot reach dev and refuses to guess another config."
  exit 1
fi

cfg_json=$(doppler configs get dev_scheduled -p soleur --json 2>/dev/null) || cfg_json=""
jrc=0
env_name=$(jq -er '.environment | strings' <<<"$cfg_json" 2>/dev/null) || jrc=$?
if [[ "$jrc" != "0" || -z "$env_name" ]]; then
  echo "::error::doppler configs get dev_scheduled -p soleur returned no parseable environment (jq rc=$jrc). Config does not exist, token lacks read access, or the output is not JSON."
  exit 1
fi
if [[ "$env_name" != "dev" ]]; then
  # Strip CR/LF + ASCII control bytes + '%' via tr, then multi-byte UTF-8
  # separators (U+2028, U+2029, U+200B, U+FEFF, NEL) via sed -- bash `tr` is
  # byte-oriented and cannot match multi-byte sequences. Mirrors
  # scheduled-realtime-probe.yml's strip_log_injection (tr + sed two-stage);
  # '%' additionally because GitHub decodes %0A/%0D inside ::error:: payloads.
  env_safe=$(printf '%s' "$env_name" | LC_ALL=C tr -d '\000-\037\177%' \
    | sed -E 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g; s/\xc2\x85//g')
  echo "::error::dev_scheduled config resolves to environment=${env_safe} (expected: dev); refusing to write."
  exit 1
fi
echo "Doppler config dev_scheduled -> environment=dev (verified)."

# DC-1 (#8028): a dev-scoped job must never hold the account-scoped
# Supabase Management-API token. The hook soaks the token's ABSENCE as a
# ::notice::; this is the only mechanical guard that the absence still
# holds. Names only; the value is never read.
names_json=$(doppler secrets --only-names --json -p soleur -c dev_scheduled 2>/dev/null) || names_json=""
jrc=0
jq -e 'type == "object" and has("SUPABASE_ACCESS_TOKEN")' >/dev/null 2>&1 <<<"$names_json" || jrc=$?
case "$jrc" in
  0)
    echo "::error::SUPABASE_ACCESS_TOKEN is present in Doppler dev_scheduled -- a dev-scoped CI job must not hold a Management-API token (#8028 DC-1)."
    exit 1 ;;
  1)
    # false or null: only a JSON object that lacks the key is proof of absence.
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$names_json"; then
      echo "::error::doppler secrets --only-names -p soleur -c dev_scheduled did not return a JSON object; cannot verify the token's absence; failing closed."
      exit 1
    fi ;;
  *)
    echo "::error::doppler secrets --only-names -p soleur -c dev_scheduled returned unparseable output (jq rc=$jrc); cannot verify the token's absence; failing closed."
    exit 1 ;;
esac
echo "Doppler config dev_scheduled carries no SUPABASE_ACCESS_TOKEN (verified)."
