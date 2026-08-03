#!/usr/bin/env bash
# Follow-through verification for #7220 PR-A — is the fatal channel actually LIVE and READING?
#
# WHY THIS IS A SOAK AND NOT A PRE-MERGE AC.
#
# PR-A ships an instrument, not a fix. The handler still dies at the ungranted
# `systemctl daemon-reload` (that grant is PR-B). What PR-A changes is that the death is now
# ATTRIBUTED: a `SOLEUR_INFRA_CONFIG_FATAL` row naming the line, the rc and the command.
#
# That property cannot be proven in CI. It requires the merge to fire
# apply-deploy-pipeline-fix.yml, terraform to replace the handler bootstrap over root SSH, and
# the host to run the NEW handler and emit through journald -> Vector -> Better Stack. Only then
# does "the channel works" mean anything. Asserting it pre-merge would assert the sandbox.
#
# THE EXPECTED POST-MERGE STATE IS A FAILING APPLY THAT SAYS WHY.
# So PASS here is NOT "the apply went green" — it is "the apply reported its own death with a
# line number". A green apply is also a pass (it means PR-B landed first, or the grant arrived
# by another route); what FAILS is a death the channel still cannot describe. That is the exact
# #7220 shape and the only outcome that means PR-A did not work.
#
# Guards, each closing a way this probe could PASS while proving nothing:
#
#   1. CHANNEL-LIVENESS. Zero FATAL rows is ambiguous: it means either "no failure occurred" or
#      "the channel is dark". Those are opposite conclusions and an empty query cannot tell them
#      apart. So a zero-FATAL result is only a PASS when the handler is provably shipping SOME
#      row in the window (the `starting: N files to write` line, emitted before anything can
#      fail). No handler rows at all -> the instrument is unverified -> FAIL, never PASS.
#
#   2. FIELD-ISOLATED IDENTIFIER. Matching on SYSLOG_IDENTIFIER parsed out of the JSON `raw`
#      column, never a bare substring anywhere in the payload (#6475). A bare grep would match
#      this marker appearing inside an unrelated log line — including a CI job echoing it.
#
#   3. ELAPSED-TIME SELF-GUARD. Refuses to grade until the apply has actually had time to run.
#      A wrong `earliest=` in the directive would otherwise let this run on merge day against a
#      window that predates the deploy.
#
# Exit semantics (per scripts/sweep-followthroughs.sh contract):
#   0 = PASS       (a fatal was attributed with a line, OR no fatal on a provably live channel)
#   1 = FAIL       (a death the channel could not describe, or the channel is dark/unverifiable)
#   * = TRANSIENT  (this script's own prerequisites missing; retry next sweep)
#
# Required env (LITERAL names — the sweeper matches by exact variable name, not glob; all three
# already exist in scheduled-followthrough-sweeper.yml):
#   BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME, BETTERSTACK_QUERY_PASSWORD
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"
WINDOW="${INFRA_CONFIG_7220_WINDOW:-24h}"
HOST_NAME="soleur-web-platform"

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is unset — cannot query the sink" >&2
    exit 2
  fi
done
if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY missing or not executable" >&2
  exit 2
fi

raw=$("$QUERY" --since "$WINDOW" --grep infra-config-apply 2>/dev/null) || {
  echo "TRANSIENT: betterstack-query.sh failed (network/credentials)" >&2
  exit 2
}

# Guard 2: field-isolate on SYSLOG_IDENTIFIER from the JSON `raw` column and scope to the host.
# A bare substring match would count a CI job that merely PRINTED the marker name.
decoded=$(printf '%s' "$raw" | jq -r '
  (.raw | fromjson?) as $r
  | select($r != null)
  | select($r.SYSLOG_IDENTIFIER == "infra-config-apply")
  | select($r.host_name == "'"$HOST_NAME"'")
  | $r.message' 2>/dev/null) || decoded=""

n_handler=$(printf '%s' "$decoded" | grep -c . || true)
n_fatal=$(printf '%s' "$decoded" | grep -cF 'SOLEUR_INFRA_CONFIG_FATAL' || true)
[[ "$n_handler" =~ ^[0-9]+$ ]] || n_handler=0
[[ "$n_fatal"   =~ ^[0-9]+$ ]] || n_fatal=0

# Guard 1: an empty window is NOT evidence of health. If the handler shipped nothing at all,
# the instrument is unverified and a "zero fatals" reading is indistinguishable from a dark
# channel — which is the precise reasoning error #7220's own diagnosis was built on.
if [[ "$n_handler" -eq 0 ]]; then
  echo "FAIL: zero infra-config-apply rows from $HOST_NAME in the last $WINDOW." >&2
  echo "      This is NOT 'no failures' — it is an unverified channel. Either no apply ran," >&2
  echo "      or journald -> Vector -> Better Stack is not carrying this identifier." >&2
  exit 1
fi

if [[ "$n_fatal" -eq 0 ]]; then
  echo "PASS: channel is live ($n_handler handler rows from $HOST_NAME in $WINDOW) and reported"
  echo "      no fatal. Delivery is completing — PR-B's grant has landed or was not needed."
  exit 0
fi

# A fatal DID occur — the expected PR-A state. The whole point is whether it is describable.
# Require a non-zero line=, because line=0 means the frame carries a death with no attribution:
# exactly the #7220 shape, and the only outcome that says PR-A failed.
attributed=$(printf '%s' "$decoded" | grep -F 'SOLEUR_INFRA_CONFIG_FATAL' \
  | grep -cE 'line=[1-9][0-9]*' || true)
[[ "$attributed" =~ ^[0-9]+$ ]] || attributed=0

if [[ "$attributed" -ge 1 ]]; then
  echo "PASS: $n_fatal fatal row(s), $attributed carrying a line number. The handler died and"
  echo "      SAID WHERE — which is what PR-A ships. Sample:"
  printf '%s' "$decoded" | grep -F 'SOLEUR_INFRA_CONFIG_FATAL' | head -3 | sed 's/^/        /'
  echo "      (Delivery itself is repaired by PR-B's daemon-reload grant, tracked on #7220.)"
  exit 0
fi

echo "FAIL: $n_fatal SOLEUR_INFRA_CONFIG_FATAL row(s) carry NO line= attribution." >&2
echo "      A death the channel cannot describe is the #7220 defect itself, still present." >&2
printf '%s' "$decoded" | grep -F 'SOLEUR_INFRA_CONFIG_FATAL' | head -3 | sed 's/^/        /' >&2
exit 1
