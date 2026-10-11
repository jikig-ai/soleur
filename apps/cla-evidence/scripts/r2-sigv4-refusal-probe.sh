#!/usr/bin/env bash
# r2-sigv4-refusal-probe.sh — offline, credential-free probe of the R2 SigV4 refusal signal.
#
# Sources _r2-sigv4-curl.sh and judges a synthesized MALFORMED value (an id with a quote in it),
# printing the helper's stderr on stdout, so an operator or the preflight discoverability check
# can see the value-free `::error::` annotation and the `SOLEUR_CREDENTIAL_REFUSED script=... reason=...`
# marker without a request, a credential or a suite run. Exits 0 when the refusal fired, 1 when it did not.
set -euo pipefail

# shellcheck source=_r2-sigv4-curl.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_r2-sigv4-curl.sh"

probe_id='synthetic"malformed'
probe_secret='synthetic-well-formed.value'
if out=$(r2_sigv4_judge r2-sigv4-refusal-probe "$probe_id" "$probe_secret" 2>&1); then
  echo "probe FAILED: a malformed value was not refused"
  exit 1
fi
printf '%s\n' "$out"
case "$out" in
  *'SOLEUR_CREDENTIAL_REFUSED script='*'reason=token_shape'*) ;;
  *) echo "probe FAILED: the refusal carried no marker"; exit 1 ;;
esac
