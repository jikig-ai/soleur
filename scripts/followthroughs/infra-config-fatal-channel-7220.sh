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
# the host to run the NEW handler and emit through journald -> Vector -> Better Stack.
#
# THE FIRST VERSION OF THIS PROBE WAS WRONG, AND WRONG IN THE DIRECTION THAT AUTO-CLOSES.
#
# It treated "the handler is shipping rows" as proof the instrument was live. But
# `starting:` / `writing:` / `wrote:` / `complete:` are emitted by the PRE-#7220 handler too, so
# that control cannot distinguish "the new instrument is live and healthy" from "the new
# instrument was never delivered" — which is the exact failure mode #7220 is about, since the
# config-delivery channel is itself the thing that breaks. Run against production while the host
# was demonstrably dying at `daemon-reload`, it returned PASS on 40 such rows. And
# `sweep-followthroughs.sh` CLOSES the issue on exit 0. It would have closed #7220 while #7220
# was still happening. That is this probe's own stated reasoning error, one level up.
#
# The rule that follows: a row type BOTH handlers emit can never be a positive control for the
# new one. Only two things can:
#   (a) a `SOLEUR_INFRA_CONFIG_FATAL` row — no pre-#7220 handler can emit that string at all; or
#   (b) the `fatal_rc` KEY in the state frame — the new handler emits it unconditionally on the
#       SUCCESS path, so its absence proves an old handler even when nothing has failed.
#
# So the decision tree never passes on ambiguity:
#
#   >=1 FATAL row carrying line=N  -> PASS. Unambiguous: the new handler is live AND reporting.
#                                    (This is the EXPECTED PR-A state — the apply still fails.)
#   >=1 FATAL row, none with line  -> FAIL. A death the channel cannot describe is #7220 itself.
#   zero FATAL rows                -> AMBIGUOUS. Ask the frame. `fatal_rc` present => new handler,
#                                    healthy (PR-B landed or the grant arrived) => PASS.
#                                    Absent => the instrument was never delivered => FAIL.
#                                    Frame unreachable => TRANSIENT. Never PASS.
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
    echo "TRANSIENT: $v is unset — cannot query the sink" >&2
    exit 2
  fi
done
if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY missing or not executable" >&2
  exit 2
fi

# --- the state frame: used for BOTH the elapsed guard and the new-handler positive control ---
# The endpoint is HMAC-signed AND behind CF Access — the same triple the apply workflow's verify
# step uses. The header is `X-Signature-256` (hooks.json.tmpl pins that exact name for this
# hook); the sibling deploy-status hook uses `X-Hub-Signature-256`, and copying that name here
# returns 403 "Hook rules were not satisfied" — measured, not assumed. A bare curl gets a Cloudflare error page, which parses as "unreachable" and pins
# this probe permanently TRANSIENT; a probe that can never converge is only marginally better
# than one that always passes, because the operator learns to ignore both.
# Best-effort here; it becomes decisive only on the ambiguous branch, where an unreachable frame
# is reported TRANSIENT rather than passed.
frame=""
if [[ -n "${WEBHOOK_DEPLOY_SECRET:-}" && -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then
  _sig="$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" 2>/dev/null | sed 's/.*= //')"
  frame="$(curl -sS --max-time 20 \
      -H "X-Signature-256: sha256=${_sig}" \
      -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}" \
      -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}" \
      "$STATUS_URL" 2>/dev/null || printf '')"
fi
frame_ok=0
if printf '%s' "$frame" | jq -e . >/dev/null 2>&1; then frame_ok=1; fi

# GUARD 1 — ELAPSED TIME. Implemented, not merely documented: an earlier revision of this file
# described this guard in its header and did not contain it, which is precisely the comment-rot
# class the PR it verifies exists to fix. `start_ts` is the apply's own clock, so a wrong
# `earliest=` in the sweeper directive cannot make this grade early.
if [[ "$frame_ok" -eq 1 ]]; then
  start_ts="$(printf '%s' "$frame" | jq -r '.start_ts // 0' 2>/dev/null || printf '0')"
  [[ "$start_ts" =~ ^[0-9]+$ ]] || start_ts=0
  if [[ "$start_ts" -gt 0 ]]; then
    elapsed=$(( $(date +%s) - start_ts ))
    if [[ "$elapsed" -lt "$MIN_ELAPSED_SECS" ]]; then
      echo "TRANSIENT: last apply was ${elapsed}s ago (< ${MIN_ELAPSED_SECS}s) — too early to grade" >&2
      exit 2
    fi
  fi
fi

# --- journald arm ---------------------------------------------------------------------------
# --limit is EXPLICIT and sized: one apply emits ~40 handler rows and the default cap of 100
# takes the NEWEST rows — so on a multi-apply day an older apply's FATAL rows fall out of the
# result while its writing:/wrote: rows survive, a second independent route to a false clean.
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

fatal_rows=$(printf '%s' "$decoded" | grep -F 'SOLEUR_INFRA_CONFIG_FATAL' || true)
n_fatal=$(printf '%s' "$fatal_rows" | grep -c . || true)
[[ "$n_fatal" =~ ^[0-9]+$ ]] || n_fatal=0

if [[ "$n_fatal" -gt 0 ]]; then
  n_attributed=$(printf '%s' "$fatal_rows" | grep -cE 'line=[1-9][0-9]*' || true)
  [[ "$n_attributed" =~ ^[0-9]+$ ]] || n_attributed=0
  if [[ "$n_attributed" -ge 1 ]]; then
    echo "PASS: $n_fatal fatal row(s), $n_attributed carrying a line number. The handler died and"
    echo "      SAID WHERE — which is exactly what PR-A ships, and no pre-#7220 handler can emit"
    echo "      this marker at all. Sample:"
    printf '%s' "$fatal_rows" | head -3 | sed 's/^/        /'
    echo "      (Delivery itself is repaired by PR-B's daemon-reload grant, tracked on #7220.)"
    exit 0
  fi
  echo "FAIL: $n_fatal SOLEUR_INFRA_CONFIG_FATAL row(s) carry NO line= attribution." >&2
  echo "      A death the channel cannot describe is the #7220 defect itself, still present." >&2
  printf '%s' "$fatal_rows" | head -3 | sed 's/^/        /' >&2
  exit 1
fi

# --- zero fatal rows: AMBIGUOUS. Resolve against the frame, or report TRANSIENT. --------------
if [[ "$frame_ok" -ne 1 ]]; then
  echo "TRANSIENT: zero fatal rows, and /hooks/infra-config-status did not return parseable JSON," >&2
  echo "           so 'healthy new handler' and 'instrument never delivered' cannot be told apart." >&2
  echo "           Refusing to PASS on that ambiguity — the sweeper closes the issue on PASS." >&2
  exit 2
fi

if printf '%s' "$frame" | jq -e 'has("fatal_rc")' >/dev/null 2>&1; then
  echo "PASS: zero fatal rows AND the state frame carries the fatal_rc key, which only the"
  echo "      post-#7220 handler emits. The instrument is deployed and the apply is not dying."
  exit 0
fi

echo "FAIL: zero fatal rows and the state frame has NO fatal_rc key." >&2
echo "      The pre-#7220 handler is still on the host — the instrument was never delivered, so" >&2
echo "      the silence is an unverified channel, not an all-clear. This is the exact reading" >&2
echo "      error that made the first version of this probe PASS against a host that was dying" >&2
echo "      at daemon-reload." >&2
exit 1
