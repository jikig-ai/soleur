#!/usr/bin/env bash
# betterstack-assert-absence.sh — assert a marker is ABSENT from a host's telemetry, and
# refuse to say so unless the channel is provably alive (#7103 R3).
#
# THE PROBLEM THIS EXISTS FOR.
#
# "The query returned zero rows" and "the query could not answer" are the same stdout: empty.
# So is "this host stopped shipping logs entirely". An absence assertion that reads row-count
# alone therefore reports its strongest result — nothing bad happened — in precisely the three
# situations where it knows least. #7095 is the case: telemetry was read as clean while the
# credential that vector runs under had been revoked.
#
# FOUR OUTCOMES, EVALUATED IN THIS ORDER:
#
#   outcome       condition                                                        exit
#   unknown       the query did not answer: any non-zero transport exit, or         3
#                 output that does not parse as JSONEachRow
#   unshipping    the positive control returned 0 rows — the channel is dark        2
#   present       the absence pattern matched at least one row                      1
#   clean         absence == 0 AND control >= 1                                     0
#
# `clean` is the ONLY exit 0, and it is unreachable without a positive control read back
# through the sink. `unshipping` and `unknown` are never reported as `clean`.
#
# The `unknown` arm is not defensive decoration. betterstack-query.sh exits 3 when credentials
# are not injected and errors the whole query if its archive arm fails; in both cases stdout is
# empty, which a row-count parse reads as "absence satisfied". That is the same shape this
# helper exists to enforce against, applied to the absence arm but not to its own transport.
#
# WHY A SEPARATE SCRIPT rather than a flag on betterstack-query.sh: that file is a pure
# transport. Its exit vocabulary is already spoken for (3 = credentials absent, 64 = bad flag or
# underivable archive table, otherwise curl's codes) and its header promises verbatim SQL
# passthrough with one output contract. Overloading it would make every existing caller's error
# handling ambiguous.
#
# HONEST LIMIT, recorded rather than papered over: `unshipping` cannot discriminate a dead
# vector agent from a dead probe unit. Both stop the canary. It correctly reports that the
# channel cannot be trusted, which is the decision the caller needs; it does not diagnose why.
#
# Usage:
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-assert-absence.sh \
#     --host soleur-web-1 --absence 'IMAGE_PULL_FAIL' [--absence '...'] \
#     [--control SOLEUR_PROBE_CANARY] [--control-require '...'] [--control-require-field 'name=value'] [--since 6h]
#
# Exit codes are the outcome table above. Every run prints one machine-readable verdict line:
#   SOLEUR_ABSENCE_ASSERT outcome=<o> host=<h> absence_rows=<n> control_rows=<n> since=<w>
set -euo pipefail

# LOCALE-PINNED, and this is load-bearing rather than hygiene. Bash's [[ =~ ]] uses the locale's
# collation for [0-9], so under en_US.UTF-8 the FULLWIDTH digits U+FF10-U+FF19 match it. Measured:
#
#   LANG=en_US.UTF-8  [[ "０６h" =~ ^([0-9]+)([hdm])$ ]]  -> MATCH
#   LC_ALL=C          [[ "０６h" =~ ^([0-9]+)([hdm])$ ]]  -> no match
#
# So `--since '０６h'` passed the shape gate below, reached $(( n * 3600 )), and died with an
# arithmetic syntax error INSIDE a command substitution — which `set -e` turns into a script
# death with exit 1. Exit 1 is `present` in this script's own outcome table, and no
# SOLEUR_ABSENCE_ASSERT verdict line is printed at all, falsifying the header's "every run prints
# one machine-readable verdict line". A typo'd window therefore told the operator the credential
# channel had regressed. Same reasoning as ship/scripts/auto-close-scan.sh's locale pin.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY="${BETTERSTACK_QUERY_SCRIPT:-$SCRIPT_DIR/betterstack-query.sh}"

HOST=""
CONTROL_MARKER="SOLEUR_PROBE_CANARY"
SINCE="6h"
ABSENCE=()

usage() {
  cat >&2 <<'EOF'
usage: betterstack-assert-absence.sh --host <host_name> --absence <substring> [--absence <substring>...]
                                     [--absence-require <substring>] [--control <substring>] [--control-require <substring>] [--control-require-field <name>=<value>] [--since <Nh|Nd>]

  --host     REQUIRED. Exact host_name to scope BOTH the absence and control reads to.
  --absence  REQUIRED, repeatable. A row matching ANY of these makes the outcome `present`.
  --absence-require  Optional, repeatable. A substring a matching row must ALSO carry to
             count as `present` — AND'd onto every --absence term. Use it when the needle
             can appear inside unrelated log bodies: 'Failed to start inngest-luks' is
             issue text too (measured: webhook-payload rows under ident=doppler attributed
             to host_name=soleur-inngest-prd, and rehearsal hosts ship under the prod
             host_name) — so that needle needs both a systemd-row require (e.g.
             '"SYSLOG_IDENTIFIER":"systemd"') and a machine-field require (e.g.
             '"host":"soleur-inngest"') to discriminate the systemd journal path on the
             right machine.
  --control  Positive-control marker (default SOLEUR_PROBE_CANARY).
  --control-require  Optional, repeatable. A substring a control row must ALSO
             carry — AND'd onto the --control marker. Marker-substring alone is
             forgeable: webhook-payload rows quote repo text verbatim under
             ident=doppler (measured: issue #9939's own title produced 10 false
             matches). A substring require narrows that class but cannot close
             it — the require string is itself repo text a payload row can quote.
  --control-require-field  Optional, repeatable, <name>=<value>. The strong form:
             AND'd onto the --control marker as
             JSONExtractString(raw,'<name>') = '<value>' — it binds the row's OWN
             journald field, so a doppler-tagged row is 'doppler' no matter what
             its payload quotes. The systemd journald path recipe (#9963):
               --control 'SOLEUR_SYSTEMD_JOURNALD_CONTROL' \
               --control-require-field 'SYSLOG_IDENTIFIER=systemd'
             A doppler-tagged row quoting the marker AND this recipe cannot
             satisfy it. <name> must match [A-Za-z_][A-Za-z0-9_]*; <value> may
             contain '='.
  --since    Window, minimum 1h (see the rate-limit note below). Default 6h.
EOF
  exit 64
}

ABSENCE_REQUIRE=()
CONTROL_REQUIRE=()
CONTROL_REQUIRE_FIELD=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)    HOST="${2:-}"; shift 2 ;;
    --absence) ABSENCE+=("${2:-}"); shift 2 ;;
    --absence-require) ABSENCE_REQUIRE+=("${2:-}"); shift 2 ;;
    --control) CONTROL_MARKER="${2:-}"; shift 2 ;;
    --control-require) CONTROL_REQUIRE+=("${2:-}"); shift 2 ;;
    --control-require-field) CONTROL_REQUIRE_FIELD+=("${2:-}"); shift 2 ;;
    --since)   SINCE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "betterstack-assert-absence: unknown flag: $1" >&2; usage ;;
  esac
done

[[ -n "$HOST" ]]           || { echo "betterstack-assert-absence: --host is required. Without it another host's canary can certify this one — see the host-scoping note below." >&2; exit 64; }
[[ "${#ABSENCE[@]}" -ge 1 ]] || { echo "betterstack-assert-absence: at least one --absence pattern is required." >&2; exit 64; }
[[ -x "$QUERY" ]]          || { echo "betterstack-assert-absence: transport not executable: $QUERY" >&2; exit 3; }

# --- Window discipline (#7103 R3 4.4) ---
# The canary is rate-limited to 1800s, so a window shorter than 1h can legitimately contain
# ZERO canaries on a perfectly healthy host — which this helper would report as `unshipping`.
# A false `unshipping` is worse than no check: it teaches the operator to ignore the signal.
# Rejected by name rather than evaluated.
# SHAPE-VALIDATE BEFORE ARITHMETIC. An arithmetic *expansion* error is fatal at expansion time
# in a non-interactive shell, so a trailing `|| echo -1` — even inside the command substitution —
# never runs: the subshell dies mid-expansion, `set -e` kills the caller, and the script exits 1
# with NO message. In this script's own outcome table 1 means `present`, so a malformed --since
# would have reported "the events are still there" for what is actually a usage error, and the
# follow-through probe would have told the operator the credential channel had regressed.
# Measured: `--since '1;evil h'` exited 1 with empty output.
#
# So the regex is the gate and `$(( ))` only ever sees digits.
since_secs() {
  local v="$1" n u
  [[ "$v" =~ ^([0-9]+)([hdm])$ ]] || { echo -1; return 0; }
  n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]}"
  case "$u" in
    h) echo $(( n * 3600 )) ;;
    d) echo $(( n * 86400 )) ;;
    m) echo $(( n * 60 )) ;;
  esac
}
SINCE_SECS=$(since_secs "$SINCE")
# Belt-and-braces: nothing below may interpolate a non-integer into the SQL's INTERVAL.
if ! [[ "$SINCE_SECS" =~ ^-?[0-9]+$ ]]; then
  echo "betterstack-assert-absence: --since '$SINCE' did not resolve to an integer number of seconds." >&2
  exit 64
fi
if [[ "$SINCE_SECS" -lt 3600 ]]; then
  echo "betterstack-assert-absence: --since '$SINCE' is below the 1h minimum. The positive control is rate-limited to 1800s, so a shorter window can hold zero canaries on a healthy host and would report a false 'unshipping'." >&2
  exit 64
fi

# SQL string literal escaping: single quotes doubled, backslashes escaped. These values reach a
# ClickHouse query, and a marker containing a quote would otherwise change the query's shape.
sql_lit() { printf "%s" "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/''/g"; }

HOST_LIT="$(sql_lit "$HOST")"

# Build the OR-group for the absence patterns. Repeated patterns are OR-combined BY DESIGN here
# (any one of them appearing is a hit) — unlike betterstack-query.sh's --grep, where the same
# OR semantics silently defeat host scoping, which is why the host predicate below is an
# explicit AND against a dedicated column instead of another substring term.
absence_or=""
for pat in "${ABSENCE[@]}"; do
  term="raw LIKE '%$(sql_lit "$pat")%'"
  for req in "${ABSENCE_REQUIRE[@]+"${ABSENCE_REQUIRE[@]}"}"; do
    term="(${term} AND raw LIKE '%$(sql_lit "$req")%')"
  done
  [[ -n "$absence_or" ]] && absence_or+=" OR "
  absence_or+="$term"
done

# The control predicate composes the same way: the marker AND'd with every
# --control-require substring and every --control-require-field extraction. A
# marker-substring control is forgeable — webhook-payload rows quote repo text
# verbatim under other idents (measured: 10 false matches on #9939's title under
# ident=doppler), and a SUBSTRING require shares that weakness: the require text
# is itself repo text a payload row can quote (the recipe above names both the
# marker and the field fragment). --control-require-field is the closed form:
# JSONExtractString reads the row's own field, so a doppler row is 'doppler'
# regardless of what its message quotes (#9963, ADR-192 I-2 + ADR-286).
control_term="raw LIKE '%$(sql_lit "$CONTROL_MARKER")%'"
for req in "${CONTROL_REQUIRE[@]+"${CONTROL_REQUIRE[@]}"}"; do
  control_term="(${control_term} AND raw LIKE '%$(sql_lit "$req")%')"
done
for req in "${CONTROL_REQUIRE_FIELD[@]+"${CONTROL_REQUIRE_FIELD[@]}"}"; do
  field_name="${req%%=*}"
  field_value="${req#*=}"
  if [[ "$req" != *=* || ! "$field_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf 'betterstack-assert-absence: --control-require-field expects <name>=<value> with a JSON-path identifier name (got %s)\n' "$req" >&2
    exit 64
  fi
  control_term="(${control_term} AND JSONExtractString(raw,'$(sql_lit "$field_name")') = '$(sql_lit "$field_value")')"
done

# --- The read, in raw SQL (#7103 R3 4.2) ---
#
# HOST SCOPING. betterstack-query.sh has no --host flag, and its repeated --grep terms compile
# to `raw LIKE '%a%' OR raw LIKE '%b%'`. Every host multiplexes into ONE Logs source with
# host_name as the sole discriminator, and the probe carrying the canary is provisioned
# for_each over the web hosts — so a --grep-based control would let ANOTHER host's canary
# certify this one. That is a false `clean` on exactly the host under test. Hence raw SQL with
# an explicit host_name equality.
#
# The predicate sits in the OUTER WHERE, which binds the union — so it constrains BOTH the hot
# and the archive arms. The archive arm is required, not belt-and-braces: remote() alone is the
# ~40-minute hot window, so a hot-only read answers `--since 6h` with 40 minutes of rows and
# calls the rest absence.
run_count() {
  local predicate="$1" sql out
  sql="
    SELECT count() AS n
    FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
          UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
    WHERE dt > now() - INTERVAL ${SINCE_SECS} SECOND
      AND JSONExtractString(raw,'host_name') = '${HOST_LIT}'
      AND (${predicate})
    FORMAT JSONEachRow"
  out="$(bash "$QUERY" "$sql" 2>&1)" || { printf 'TRANSPORT_FAIL\n%s\n' "$out" >&2; return 1; }
  # JSONEachRow: exactly one object with a numeric `n`. Anything else — an empty body, an HTML
  # error page, a ClickHouse exception echoed to stdout — is UNKNOWN, never zero.
  local n
  # `head -1` here was a PARTIAL-ANSWER-AS-ABSENCE bug, which is the exact class this script
  # exists to close. A body of `{"n":"0"}` followed by a ClickHouse exception yielded rc=0 and
  # outcome=clean: the first match won and everything after it — including the error saying the
  # query did not complete — was discarded. Reproduced against the pristine script before fixing.
  #
  # Require EXACTLY ONE count field, and refuse a response that carries an error alongside it.
  # More than one match is equally disqualifying: it means the body is not the shape this parser
  # was written for, and picking one of them is guessing.
  local matches n_matches
  matches="$(printf '%s' "$out" | grep -oE '"n":"?[0-9]+"?' || true)"
  n_matches="$(printf '%s' "$matches" | grep -c . || true)"
  if [[ "$n_matches" != "1" ]]; then
    printf 'UNPARSEABLE (expected exactly one "n" field, found %s)\n%s\n' "$n_matches" "$out" >&2
    return 1
  fi
  if grep -qiE 'exception|DB::Err|Code: [0-9]+|syntax error' <<<"$out"; then
    printf 'UNPARSEABLE (the response carries an error alongside the count — a partial answer is not an answer)\n%s\n' "$out" >&2
    return 1
  fi
  n="$(printf '%s' "$matches" | grep -oE '[0-9]+' | head -1 || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || { printf 'UNPARSEABLE\n%s\n' "$out" >&2; return 1; }
  printf '%s' "$n"
}

verdict() {
  # $1 outcome, $2 absence_rows, $3 control_rows, $4 exit
  echo "SOLEUR_ABSENCE_ASSERT outcome=$1 host=$HOST absence_rows=$2 control_rows=$3 since=$SINCE"
  exit "$4"
}

# CONTROL FIRST. Its failure modes (unknown, unshipping) both dominate any absence result: an
# absence of zero means nothing until the channel is known to be carrying rows at all.
control_rows="$(run_count "$control_term")" || {
  echo "betterstack-assert-absence: the positive-control read did not answer. Reporting unknown rather than treating an unanswered query as an absence." >&2
  verdict unknown - - 3
}
if [[ "$control_rows" -eq 0 ]]; then
  echo "betterstack-assert-absence: positive control '$CONTROL_MARKER' returned ZERO rows for host '$HOST' over $SINCE. The channel is not shipping, so an absence result would be meaningless. (This cannot distinguish a dead vector agent from a dead probe unit — both stop the canary.)" >&2
  verdict unshipping - "$control_rows" 2
fi

absence_rows="$(run_count "$absence_or")" || {
  echo "betterstack-assert-absence: the absence read did not answer." >&2
  verdict unknown - "$control_rows" 3
}
if [[ "$absence_rows" -gt 0 ]]; then
  verdict present "$absence_rows" "$control_rows" 1
fi

verdict clean "$absence_rows" "$control_rows" 0
