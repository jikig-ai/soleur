#!/usr/bin/env bash
# Follow-through probe for #6297 — "is the Anthropic daily cost report actually
# producing a healthy run?"
#
# #6297's close criterion is NOT "the false-page fix merged" — that only stops
# the noise. The issue stays open until an admin key exists and the cron
# produces a real report. So this probe verifies the END STATE (a healthy
# marker row), not secret presence. That is also the only thing expressible
# here: the sweeper's `secrets=` allowlist carries no ANTHROPIC_* and no
# DOPPLER_TOKEN. Verifying the end state is strictly stronger anyway — a
# minted-but-broken key does not close the issue.
#
# Exit semantics (per the sweep-followthroughs.sh contract):
#   0 = PASS       a producer row with status=ok in the window → key works, close
#   1 = FAIL       a genuine REGRESSION: the window holds an ok row but the most
#                  recent row is key-missing (key revoked / rotated away / IaC
#                  reverted). NOT used for "not minted yet".
#   2 = TRANSIENT  still key-missing with no prior ok, zero producer rows,
#                  missing query script, or any query/auth failure.
#
# Reads its secrets via the directive's `secrets=` clause. The sweeper runs
# under `env -i`, so anything not declared there is absent by construction —
# and the script is stateless between sweeps, so the "consecutive zero-row"
# counter is derived from GitHub's own comment history, not an in-process var.
set -uo pipefail

ISSUE=6297
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
QUERY="$REPO_ROOT/scripts/betterstack-query.sh"

# NEVER `: "${VAR:?msg}"` — under a non-interactive shell that expansion aborts
# with status 1, which this contract reads as FAIL, so an unprovisioned secret
# would accrete a daily false-FAIL comment (followthrough-convention.md).
if [[ ! -x "$QUERY" ]]; then
  echo "TRANSIENT: $QUERY missing or not executable"
  exit 2
fi
for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [[ -z "${!v:-}" ]]; then
    echo "TRANSIENT: $v is not set in the probe environment"
    exit 2
  fi
done

# 48h window: Better Stack retention on this source is 3 days
# (betterstack-log-query.md), so anything > 72h reads empty regardless of
# producer health. 48h covers two daily 06:17 UTC fires with margin.
OUT=$(bash "$QUERY" --since 48h --grep '"SOLEUR_CLAUDE_COST_DAILY":true' --limit 200 2>&1)
RC=$?
if (( RC != 0 )); then
  # Do NOT echo $OUT. It captured stderr, and betterstack-query.sh uses
  # `curl --fail-with-body`, so a ClickHouse auth failure prints a body that
  # echoes the username ("no user with such name: <user>") and curl's own -sS
  # errors echo the host. The sweeper posts this stdout verbatim as a PUBLIC
  # comment on #6297, so the exit code is all that may leave this branch.
  echo "TRANSIENT: betterstack-query.sh exited $RC (output withheld — may contain credentials)"
  exit 2
fi

# ‼️ ECHO ISOLATION (P0). `--grep` compiles to an unanchored `raw LIKE '%…%'`
# over the single Better Stack source that every host multiplexes into, and
# GitHub webhook payloads (issue and PR bodies) reach that source — so any
# prose that merely QUOTES the marker name could satisfy a substring probe.
# This PR body, the issue body, and the sweeper's own comments all quote it.
# (Scoping on `source_kind` is NOT relied on here: the structural check below
# is strictly stronger and holds regardless of which Vector source the echo
# arrives on, so no claim is made about where echoes land.)
#
# So match STRUCTURALLY, not by substring: decode the `raw` column, parse it as
# JSON, and require the discriminators to be TOP-LEVEL KEYS. In a webhook echo
# those same characters appear as nested *string content* of a body/payload
# field, never as top-level keys of the log line — so an echo cannot satisfy
# this no matter what it quotes. `component` is the pino base field stamped by
# the dedicated marker instance (claude-cost-marker.ts).
#
# ‼️ SINGLE PASS, DELIBERATELY. An earlier revision piped two `jq -R` stages
# (decode `raw`, then select). That was exploitable: `jq -r` materializes an
# embedded `\n` as a REAL newline, so the second `-R` stage re-tokenizes on
# physical lines and evaluates a line from INSIDE a multi-line `raw` as though
# it were a top-level log line. A stack trace or journald entry embedding
# attacker-supplied issue/PR text then satisfies the guard and auto-closes
# #6297 with the key still unminted — verified end-to-end. Chaining
# `fromjson? | .raw | fromjson?` inside ONE filter keeps the decoded value a
# single jq value: the trailing garbage makes `fromjson` fail, and `?` drops
# the row closed. Do not split this back into two stages.
# Emit "<dt>\t<status>" and sort on dt HERE rather than trusting the query's
# output order. betterstack-query.sh does emit an outer `ORDER BY dt ASC`
# today, but that is a cross-script coupling held by a comment with no
# enforcement on either side — and if it ever flips, `tail -1` silently reads
# the OLDEST row, so an active key revocation (ok newest → dark) would invert
# into PASS and auto-close #6297. The rows already carry dt; use it.
PRODUCER=$(printf '%s\n' "$OUT" \
  | jq -R -r 'fromjson? | . as $r | ($r.raw // empty | fromjson? | select(.SOLEUR_CLAUDE_COST_DAILY == true and .component == "claude-cost") | .status // "unknown") as $s | "\($r.dt)\t\($s)"' 2>/dev/null \
  | LC_ALL=C sort \
  || true)

ROWS=$(printf '%s' "$PRODUCER" | grep -c . || true)

if (( ROWS == 0 )); then
  # Positive-liveness rule: "zero bad events" is NOT a PASS without proof the
  # producer ran. Never exit 0 here.
  echo "TRANSIENT: zero producer rows in the last 48h (ZERO_PRODUCER_ROWS)."
  echo "  Either the cron has not fired since deploy, or the shipping path dropped the row."

  # Cross-check the OTHER transport before concluding. The warn-level Sentry
  # mirror travels a different path (shared logger → Sentry over HTTPS) than
  # the marker (Vector → Better Stack). If Sentry shows activity while Better
  # Stack shows nothing, the producer is alive and the SHIPPING path is broken
  # — a real fault the Sentry cron monitor cannot see (its check-in succeeded,
  # so it stays GREEN in exactly this mode).
  if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
    echo "  Sentry cross-check skipped: SENTRY_AUTH_TOKEN not set."
  else
    SENTRY_HOST="${SENTRY_API_HOST:-jikigai-eu.sentry.io}"
    SENTRY_ORG="${SENTRY_ORG:-jikigai-eu}"
    # --fail is load-bearing: without it curl exits 0 on 4xx and jq's
    # `(.data[0]["count()"] // 0)` maps an {"detail":"Invalid token"} body to
    # "0" — so an auth failure would be reported as a substantive zero events.
    SC=$(curl -sS --fail --max-time 25 -G \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      --data-urlencode 'field=count()' \
      --data-urlencode 'query=op:anthropic-admin-key-missing' \
      --data-urlencode 'statsPeriod=48h' \
      "https://${SENTRY_HOST}/api/0/organizations/${SENTRY_ORG}/events/" 2>/dev/null \
      | jq -r '(.data[0]["count()"] // 0) | tostring' 2>/dev/null || echo "")
    if [[ -z "$SC" ]]; then
      echo "  Sentry cross-check inconclusive (query failed)."
    elif [[ "$SC" == "0" ]]; then
      # Do NOT conclude "the producer is not running". This tag is emitted ONLY
      # on the dark branch, so a healthy producer whose rows are not shipping
      # ALSO reads 0 here — which is precisely failure mode #5, the reason this
      # cross-check exists. A zero is not evidence of absence.
      echo "  Sentry shows 0 key-missing events in 48h. NOT decisive: this tag is"
      echo "  emitted only on the dark branch, so this is equally consistent with"
      echo "  (a) the cron not running, or (b) a healthy cron whose rows are not"
      echo "  reaching Better Stack. Check the scheduled-anthropic-cost-report"
      echo "  monitor's check-in history, which is populated on BOTH branches."
    else
      echo "  DIVERGENCE: Sentry shows ${SC} event(s) in 48h but Better Stack has none."
      echo "  → the cron IS running; the Vector→Better Stack shipping path is dropping rows."
    fi
  fi

  # Bound the TRANSIENT. A probe that shrugs identically forever is the same
  # decayed-dark-state defect this issue exists to remove. The counter comes
  # from prior sweeper comments because the probe is stateless under `env -i`.
  if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "  Stall counter unavailable: GH_TOKEN not set."
  else
    # `|| echo 0` must NOT be the failure path: a dead counter would then look
    # identical to "first sweep" and print nothing forever — the same decayed
    # silent state this issue exists to remove. Sentinel the failure instead.
    PRIOR=$(gh issue view "$ISSUE" --json comments \
      --jq '[.comments[] | select(.body | contains("ZERO_PRODUCER_ROWS"))] | length' 2>/dev/null || echo "ERR")
    if [[ "$PRIOR" == "ERR" || ! "$PRIOR" =~ ^[0-9]+$ ]]; then
      echo "  Stall counter query FAILED (gh could not read #$ISSUE) — the stall"
      echo "  bound is not being enforced this run."
    elif (( PRIOR >= 7 )); then
      echo "  STALLED: ${PRIOR} consecutive sweeps have reported zero producer rows."
      echo "  This is no longer 'not minted yet' — the observability path itself needs attention."
    fi
  fi
  exit 2
fi

LAST=$(printf '%s\n' "$PRODUCER" | tail -1 | cut -f2)   # sorted by dt above → newest
HAS_OK=$(printf '%s\n' "$PRODUCER" | cut -f2 | grep -c '^ok$' || true)

echo "observed ${ROWS} producer row(s) in 48h; most recent status=${LAST}; ok rows=${HAS_OK}"

if (( HAS_OK > 0 )) && [[ "$LAST" == "key-missing" ]]; then
  echo "FAIL: the report worked and then stopped — the admin key was revoked,"
  echo "      rotated away, or the Doppler/IaC value was reverted. This is a"
  echo "      regression, not an un-minted key."
  exit 1
fi

if (( HAS_OK > 0 )); then
  echo "PASS: the Anthropic daily cost report produced a healthy run."
  exit 0
fi

echo "TRANSIENT: still key-missing — the admin key has not been provisioned yet."
echo "  This state is EXPECTED to persist indefinitely and is deliberately NOT"
echo "  stall-bounded: the Admin API is unavailable to individual accounts, and"
echo "  this org is one, so the key cannot be minted until the operator decides"
echo "  whether to convert to a team organization. Repeating this line is the"
echo "  correct behaviour, not a decayed probe. See the #6297 body."
exit 2
