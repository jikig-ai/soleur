#!/usr/bin/env bash
# Follow-through probe for #6698 — "is the cert-reissue routine actually
# diagnosable now?"
#
# #6698's close criterion is NOT "the code merged" — it is "a fire produces
# readable step markers". The whole point of the work is that the routine was
# observationally dark on its success path, so closing on merge would close on
# a promise. This probe asserts the markers reach Better Stack.
#
# Exit semantics (per the sweep-followthroughs.sh contract):
#   0 = PASS       markers for >=3 distinct phases observed → the routine is diagnosable
#   1 = FAIL       the query ran but found no markers → still dark, keep open
#   * = TRANSIENT  Better Stack unreachable / creds absent → retry next sweep
#
# Reads BETTERSTACK_* via the directive's `secrets=` clause. The sweeper runs
# under `env -i`, so anything not declared there is absent by construction.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"

if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY missing or not executable"
  exit 2
fi

# Field-isolate on the STRUCTURED discriminator, not the bare token. `--grep`
# compiles to an unanchored `raw LIKE '%…%'` over a source every host
# multiplexes into, and inngest ships GitHub-webhook payloads (issue and PR
# bodies — including this very PR, which quotes the token) to the same source.
# Scoping on the producer as well keeps a webhook-shipped quotation of the
# literal from reading as a real emit.
OUT=$(bash "$QUERY" --since 14d --grep '"SOLEUR_CERT_REISSUE":true' 2>&1)
RC=$?

if (( RC != 0 )); then
  echo "TRANSIENT: betterstack-query.sh exited $RC"
  printf '%s\n' "$OUT" | tail -5
  exit 2
fi

# ‼️ DECODE the `raw` column before matching. betterstack-query.sh emits
# JSONEachRow, so `raw` is a JSON STRING VALUE and every quote inside it is
# backslash-escaped on stdout (`\"source_kind\":\"app_container\"`). Grepping
# the unescaped form matches ZERO rows always — a probe that can never PASS,
# which is the inverse-vacuity of a probe that can never FAIL and just as
# useless. `-R` + `fromjson?` tolerates any non-JSON preamble the query prints.
DECODED=$(printf '%s\n' "$OUT" | jq -R -r 'fromjson? | .raw // empty' 2>/dev/null || true)

# Only count rows from the app container. Webhook-shipped rows carry
# source_kind=journald, never app_container, so this drops any row that merely
# QUOTES the discriminator (this PR body does).
APP_ROWS=$(printf '%s\n' "$DECODED" | grep -c '"source_kind":"app_container"' || true)
if (( APP_ROWS == 0 )); then
  echo "FAIL: zero app_container rows carrying \"SOLEUR_CERT_REISSUE\":true in the last 14d."
  echo "      The routine has either not been fired since deploy, or is still dark."
  echo "      Fire a probe: POST /api/internal/trigger-cron {\"event\":\"cron/gh-pages-cert-reissue.manual-trigger\"}"
  exit 1
fi

# Diagnosability means MULTIPLE phases are visible, not just one row. A single
# phase would reproduce the original defect (the routine already emitted one
# 'initializing fn' line and was still undiagnosable).
PHASES=$(printf '%s\n' "$DECODED" \
  | grep -o '"phase":"[a-z-]*"' \
  | sort -u \
  | wc -l | tr -d '[:space:]')

echo "observed ${APP_ROWS} app_container marker row(s) across ${PHASES} distinct phase(s)"

if (( PHASES < 3 )); then
  echo "FAIL: only ${PHASES} distinct phase(s) visible — the routine is not yet diagnosable."
  echo "      Expected at least: preflight, pre-flip-dns, flip-dns-only, dns-propagation, restore, terminal."
  exit 1
fi

echo "PASS: cert-reissue step markers are reaching Better Stack across ${PHASES} phases."
exit 0
