#!/usr/bin/env bash
# #7220 AC21 — post-merge soak for the ACTIVATION repair (PR-B).
#
# SIBLING, NOT A DUPLICATE, of infra-config-fatal-channel-7220.sh. That probe asks "is the
# INSTRUMENT live and reporting?" (PR-A). This one asks the question PR-B exists to answer:
# "did activation actually happen?" A host can satisfy the first and fail this one — that is
# precisely the #7220 state, where the channel described its own death perfectly and no unit
# was ever reconciled.
#
# WHAT MAKES THE POSITIVE CONTROL VALID. `SOLEUR_INFRA_CONFIG_RESTART` for vector.service is
# emitted by the reconciliation loop, which sits AFTER the daemon-reload. The pre-#7220 handler
# died at that reload with `Interactive authentication required`, so it could never reach the
# loop and can NEVER emit this marker. A signal both the old and new artifact emit is not a
# control — the first version of the sibling probe PASSed on 40 `writing:`/`wrote:` rows while
# the host was demonstrably dying, because those rows are emitted by both. This marker is not.
#
# WHY AMBIGUITY IS NEVER A PASS. `sweep-followthroughs.sh` CLOSES the issue on exit 0. Zero
# restart rows is ambiguous — no apply in the window, or an apply that died before the loop —
# and closing #7220 on that ambiguity is the same auto-close failure the sibling probe shipped
# with. Ambiguity is TRANSIENT here, never PASS.
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       1 = FAIL       * = TRANSIENT (retry next sweep)
#
# Required env (LITERAL names — the sweeper matches by exact variable name, not glob; all of
# these already exist in scheduled-followthrough-sweeper.yml):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
#   WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
WINDOW="24h"
HOST_NAME="soleur-web-platform"
STATUS_URL="${INFRA_CONFIG_STATUS_URL:-https://deploy.soleur.ai/hooks/infra-config-status}"
# Minimum seconds between the apply and grading. The apply is async behind a 202 and Vector
# batches at 10 events, so grading immediately reads a half-written window.
MIN_ELAPSED_SECS="${INFRA_CONFIG_7220_MIN_ELAPSED:-3600}"

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset — cannot query the log backend." >&2
    exit 2
  fi
done
if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY is not executable." >&2
  exit 2
fi

# --- frame arm: read the host's own state, and enforce the elapsed-time guard ----------------
# The header is `X-Signature-256` (hooks.json.tmpl pins that exact name for this hook); the
# more common X-Hub-Signature-256 is NOT accepted and yields a permanent TRANSIENT.
frame=""
frame_ok=0
if [[ -n "${WEBHOOK_DEPLOY_SECRET:-}" && -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then
  _sig=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" 2>/dev/null | sed 's/.*= //') || _sig=""
  if [[ -n "$_sig" ]]; then
    frame=$(curl -s --max-time 15 \
      -H "X-Signature-256: sha256=${_sig}" \
      -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
      -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" \
      "$STATUS_URL" 2>/dev/null) || frame=""
    if printf '%s' "$frame" | jq -e . >/dev/null 2>&1; then frame_ok=1; fi
  fi
fi

if [[ "$frame_ok" -eq 1 ]]; then
  _end=$(printf '%s' "$frame" | jq -r '.end_ts // empty' 2>/dev/null || true)
  if [[ "$_end" =~ ^[0-9]+$ ]]; then
    _now=$(date -u +%s)
    _elapsed=$(( _now - _end ))
    if [[ "$_elapsed" -lt "$MIN_ELAPSED_SECS" ]]; then
      echo "TRANSIENT: last apply ended ${_elapsed}s ago (< ${MIN_ELAPSED_SECS}s). Vector batches at" >&2
      echo "           10 events, so grading now reads a half-written window." >&2
      exit 2
    fi
  fi
fi

# --- journald arm ----------------------------------------------------------------------------
# --limit is EXPLICIT and sized: one apply emits ~40 handler rows and the default cap takes the
# NEWEST, so on a multi-apply day an older apply's rows fall out of the result.
raw=$("$QUERY" --since "$WINDOW" --limit 1000 --grep infra-config-apply 2>/dev/null) || {
  echo "TRANSIENT: betterstack-query.sh failed (network/credentials)" >&2
  exit 2
}

# Field-isolate on SYSLOG_IDENTIFIER parsed out of the JSON `raw` column, never a bare substring
# anywhere in the payload (#6475) — a bare grep would match a CI job that merely PRINTED the name.
decoded=$(printf '%s' "$raw" | jq -r '
  (.raw | fromjson?) as $r
  | select($r != null)
  | select($r.SYSLOG_IDENTIFIER == "infra-config-apply")
  | select($r.host_name == "'"$HOST_NAME"'")
  | $r.message' 2>/dev/null) || decoded=""

n_fatal=$(printf '%s' "$decoded" | grep -cF 'SOLEUR_INFRA_CONFIG_FATAL' || true)
[[ "$n_fatal" =~ ^[0-9]+$ ]] || n_fatal=0

restart_rows=$(printf '%s' "$decoded" | grep -F 'SOLEUR_INFRA_CONFIG_RESTART' | grep -F 'vector.service' || true)
n_restart=$(printf '%s' "$restart_rows" | grep -c . || true)
[[ "$n_restart" =~ ^[0-9]+$ ]] || n_restart=0

# A death anywhere in the window is a FAIL regardless of what else landed: PR-B's whole claim is
# that the handler now runs to completion. Checked BEFORE the restart arm so a run that both
# reconciled and later died cannot be graded green on the reconciliation alone.
if [[ "$n_fatal" -gt 0 ]]; then
  echo "FAIL: $n_fatal SOLEUR_INFRA_CONFIG_FATAL row(s) in the last $WINDOW — the handler is still" >&2
  echo "      dying. PR-B's grant was supposed to let it run past activation." >&2
  printf '%s' "$decoded" | grep -F 'SOLEUR_INFRA_CONFIG_FATAL' | head -3 | sed 's/^/        /' >&2
  exit 1
fi

if [[ "$n_restart" -ge 1 ]]; then
  echo "PASS: $n_restart SOLEUR_INFRA_CONFIG_RESTART row(s) for vector.service, and zero fatal rows."
  echo "      The reconciliation loop runs AFTER the daemon-reload, so reaching it at all proves"
  echo "      the reload was granted and succeeded — a marker no pre-#7220 handler can emit."
  printf '%s' "$restart_rows" | head -3 | sed 's/^/        /'
  exit 0
fi

# --- zero restart rows: AMBIGUOUS. Never a PASS. ---------------------------------------------
# Distinguish "no apply happened" from "an apply happened and reconciled nothing", because only
# the second is a defect. The frame's own counters are the discriminator.
if [[ "$frame_ok" -ne 1 ]]; then
  echo "TRANSIENT: zero restart rows, and $STATUS_URL did not return parseable JSON, so 'no apply" >&2
  echo "           in the window' and 'an apply that never reconciled' cannot be told apart." >&2
  echo "           Refusing to PASS on that ambiguity — the sweeper closes the issue on PASS." >&2
  exit 2
fi

_restarts_len=$(printf '%s' "$frame" | jq -r '(.restarts // []) | length' 2>/dev/null || echo 0)
[[ "$_restarts_len" =~ ^[0-9]+$ ]] || _restarts_len=0
if [[ "$_restarts_len" -ge 1 ]]; then
  echo "TRANSIENT: zero restart rows in the log window, but the frame reports ${_restarts_len}" >&2
  echo "           reconciliation verdict(s) — the apply predates this window, or Vector has not" >&2
  echo "           shipped it yet. Not evidence of a defect; retry next sweep." >&2
  exit 2
fi

echo "FAIL: zero SOLEUR_INFRA_CONFIG_RESTART rows for vector.service AND the frame carries an" >&2
echo "      empty restarts[] — an apply completed and reconciled NOTHING. Delivery without" >&2
echo "      activation is exactly the #7220 defect, still present after PR-B." >&2
exit 1
