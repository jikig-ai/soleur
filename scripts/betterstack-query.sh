#!/usr/bin/env bash
# Query Better Stack Telemetry logs/metrics via the ClickHouse HTTP SQL API.
#
# OUTPUT SHAPE: each row's `raw` column is DOUBLE-ENCODED JSON (a JSON string containing a JSON
# document). A grep for a field name or a message substring against the raw line silently returns
# nothing — the quotes are backslash-escaped. Decode first:
#   … | jq -r '.raw | fromjson | "\(.SYSLOG_IDENTIFIER) \(.message)"'
# Field-isolate on SYSLOG_IDENTIFIER from the decoded object rather than substring-matching the
# line (#6475), or a CI job that merely PRINTED a marker name counts as an occurrence.
#
# Better Stack stores ingested logs in a ClickHouse warehouse queryable over
# HTTP with plain SQL. This is the ONLY way to read HISTORICAL logs
# programmatically — the `BETTERSTACK_LOGS_TOKEN` is INGEST-ONLY (write), and
# the `BETTERSTACK_API_TOKEN` (Telemetry mgmt API) covers source/connection
# metadata but NOT log content. Reading log rows needs a dedicated ClickHouse
# HTTP *connection* (a username/password pair distinct from both tokens).
#
# Provisioning (already done once via the Telemetry API, NOT the dashboard):
#   POST https://logs.betterstack.com/api/v1/connections
#     {"client_type":"clickhouse","team_ids":[<TEAM_ID>]}
#   → 201 returns {host, port, username, password, data_region}. Stored in
#   Doppler soleur/prd_terraform as BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}.
#   To re-mint: see knowledge-base/engineering/operations/runbooks/betterstack-log-query.md.
#
# Table identifier for the remote() function is `t<TEAM_ID>_<table_name>_logs`
# (team id, NOT source id — the docs' `t123456_...` placeholder is the team).
# Our source `soleur-inngest-vector-prd` (id 2457081, team 520508, table
# soleur_inngest_vector_prd_3) → remote(t520508_soleur_inngest_vector_prd_3_logs).
#
# Usage:
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "<SQL>"
#   doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep cron-roadmap-review
#
# Two modes:
#   1. Raw SQL (first positional arg is a SELECT …): runs it verbatim. Use the
#      $BS_TABLE env (exported by this script) for the remote() arg, e.g.
#      "SELECT dt, raw FROM remote($BS_TABLE) WHERE … LIMIT 50 FORMAT JSONEachRow"
#   2. Convenience flags (no SQL arg): --since <Nh|Nm|ISO>, --until <ISO>,
#      --grep <substr> (repeatable, OR-combined), --limit <N>, --raw-only
#      (exclude host metrics + journald noise), --no-archive (hot window only —
#      see below), --table / --table-s3 (override either table).
#
# HOT WINDOW vs ARCHIVE: mode 2 queries remote(<..._logs>) UNION ALL
# s3Cluster(primary, <..._s3>), because remote() alone is ONLY the hot window (~40
# minutes on 2026-07-15). Anything asking for a real soak span MUST include the archive
# arm or it gets a silently short answer. --no-archive opts out (hot-only, faster);
# do not reach for it to work around an archive error — the short answer is the bug.
# Raw SQL (mode 1) is verbatim: write the UNION yourself, using the $BS_TABLE and
# $BS_TABLE_S3 tokens (both are substituted).
#
# Output: JSONEachRow (one JSON object per line) on stdout. Errors to stderr.
set -uo pipefail

# (#7797) Refuse to run under shell tracing while a live credential is set: `set -x`
# would trace the token into whatever collects this script's output. `case "$-" in *x*)`
# tests whether tracing is ON rather than enumerating the eight ways to turn it on, two
# of which carry no `-x` token at all.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac
# The sibling probe (scripts/betterstack-ingest-probe.sh) does this immediately after its own
# prologue and this script did not. It does not affect the apex match below, but the
# `*[[:cntrl:]]*` arm's character-class membership is LOCALE-DEFINED, so the shape check's
# refusal set was a function of the caller's locale. Pin it.
export LC_ALL=C

# (#7873) Same argument as scripts/zot-inventory.sh's prologue, applied to the
# credential the plan calls its headline: `--disable` closes ~/.curlrc and
# `--noproxy '*'` closes the proxy vars, but neither touches the env that
# subverts TLS ITSELF. SSLKEYLOGFILE writes the session keys and the CA vars
# substitute the trust store, so the actor who can set BETTERSTACK_QUERY_HOST can
# read this Basic-auth credential off the wire with every other guard intact.
# It was an asymmetry that this line lived only in zot-inventory.sh while the
# higher-value credential went without.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

# Credential guard. These are Doppler-managed secrets that must be INJECTED into
# the env — this script does not read Doppler itself. A bare-shell run (no
# `doppler run` wrapper) trips this. The message is deliberately explicit that the
# fix is the invocation, NOT a missing capability: an agent that reads "unset" as
# "this session lacks Better Stack access" and gives up is the exact misdiagnosis
# this hint exists to prevent: a transient probe failure is not proof of no access.
if [[ -z "${BETTERSTACK_QUERY_HOST:-}" || -z "${BETTERSTACK_QUERY_USERNAME:-}" || -z "${BETTERSTACK_QUERY_PASSWORD:-}" ]]; then
  cat >&2 <<'EOF'
betterstack-query.sh: BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} not set.

You are NOT missing Better Stack access — these creds live in Doppler and this
script needs them INJECTED. Re-run wrapped in `doppler run`:

  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh <args>

e.g.  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep <marker>

Do NOT conclude "no access / can't verify" from this message — the correct next
step is the doppler-wrapped re-run above. (Creds provisioning: see
knowledge-base/engineering/operations/runbooks/betterstack-log-query.md)
EOF
  # EXIT 3 HERE MEANS "NOTHING WAS QUERIED" -- and a sibling helper uses 3 for the opposite.
  #
  # scripts/supabase-logs-query.sh exits 3 for INCONCLUSIVE/UNINSTRUMENTED: it DID query, and
  # the coverage verdict is that the answer cannot be trusted. Here, 3 means the query never
  # ran at all because creds were not injected.
  #
  # The dangerous direction is an agent that learns 3 == INCONCLUSIVE from that helper and
  # then reads this one's 3 as "we looked, and coverage was inconclusive" -- laundering a
  # never-executed query into a coverage verdict, which is precisely what ADR-197 exists to
  # prevent. Both helpers are now cited in the same incident/SKILL.md Phase 0 sentence, so
  # the collision is one screen apart in the document an agent reads mid-incident.
  #
  # Read the MESSAGE above, not the number: it names the re-invocation. Do not treat this
  # exit as evidence about log coverage.
  exit 3
fi

# Table identifier — overridable for other sources via BS_TABLE.
export BS_TABLE="${BS_TABLE:-t520508_soleur_inngest_vector_prd_3_logs}"

# ARCHIVE table. `remote(..._logs)` is ONLY the hot window — on 2026-07-15 it held ~40
# MINUTES. Rows older than that live in the s3 archive and are invisible to remote(), so a
# hot-only query silently answers `--since 24h` with 40 minutes of rows: not an error, just
# a short answer. That is what kept #6288 open since 2026-07-10 — its soak gate needs
# ZOT_MIN_SOAK_SPAN_SEC=7200 (2h) of span and could never reach PASS through the keyhole,
# reporting "TRANSIENT: soak not yet filled" forever. Both halves are UNION ALL-combined per
# the runbook (betterstack-log-query.md §Query mechanics). Verified disjoint on 2026-07-15:
# 891 rows / 891 distinct / 0 dupes over 7d, archive ending 19:13:46 and hot starting
# 19:15:02 — so UNION ALL does not double-count (load-bearing: soak gates COUNT events).
#
# An explicit BS_TABLE_S3 (env OR --table-s3) always wins; S3_EXPLICIT records that so the
# post-flag re-derivation below cannot clobber it. Seeding the sentinel from the ENV here —
# not only from the flag — is load-bearing: otherwise `BS_TABLE_S3=other_s3` is accepted,
# silently ignored, and the caller gets rows from the DEFAULT archive with no error, because
# the derived name exists and the query succeeds. That is this script's own headline bug
# (asks for X, gets Y, exit 0) reintroduced one level down.
# (#7873, #7898 §6) BETTERSTACK_QUERY_HOST is interpolated into `https://${HOST}?...` and
# run_sql attaches Basic auth with `curl -u`, which sends the credential PREEMPTIVELY on the
# first request with no challenge. The value IS the destination of a live secret, so it is
# validated in two steps before run_sql is ever reachable.
#
# STEP 1 — the SHAPE arm (cheap, first refusal). It rejects the userinfo/path/scheme family:
# `real.host@evil.example` resolves to evil.example, and `evil.example/x?` puts the query on
# an attacker path. On its own it is NOT a destination validation — a substituted BARE host
# (`attacker.example`) passes every one of its arms, which is precisely the gap #7898 §6
# reported. It is kept because it is cheaper and because its refusal message is more useful
# for the malformed-value case.
#
# STEP 2 — the ALLOWLIST arm, and this is the pin. Extract the authority, then match the
# ISOLATED host against `*.betterstackdata.com`.
#
# WHY AUTHORITY EXTRACTION RATHER THAN A GLOB OVER THE WHOLE VALUE: #7855, measured on the
# sibling credential. `case "$URL" in *betterstackdata.com*)` accepted
# `https://evil.com/?x=.betterstackdata.com/`, because a shell glob's `*` crosses `/` and `?`
# — the leading wildcard swallowed the entire authority and the vendor name only had to appear
# SOMEWHERE later in the string. Every wildcard below is confined to a string that cannot
# contain a path, a query or a fragment.
#
# This follows scripts/betterstack-ingest-probe.sh's STRUCTURE, with four deliberate
# differences from its text — each one a value that works today and that a line-for-line copy
# would refuse:
#   - NO SCHEME STRIP. The probe opens with `_bs_rest="${URL#https://}"` and refuses if
#     nothing was removed, because ITS input is a URL. This input is a BARE host. That arm
#     copied verbatim refuses every legitimate value; made optional it is dead code, because
#     the shape arm above already rejects `/`. We begin at the path strip.
#   - CASE-FOLD FIRST. DNS is case-insensitive; a bash `case` glob is not, and LC_ALL does not
#     change that. `EU-CENTRAL-1A-CONNECT.BETTERSTACKDATA.COM` is a working value today, and an
#     unfolded pin would refuse it — breaking every consumer at once.
#   - STRIP ONE TRAILING DOT. `eu-central-1a-connect.betterstackdata.com.` is a valid absolute
#     FQDN, passes every shape arm, and resolves correctly. An unstripped pin refuses it.
#   - THE LEADING DOT IN THE PATTERN IS LOAD-BEARING. Without it `notbetterstackdata.com` — a
#     registrable lookalike — satisfies a bare suffix match.
#
# READ THE RESIDUAL PLAINLY, because an allowlist is easy to mis-read as a boundary.
# `*.betterstackdata.com` accepts EVERY BETTER STACK TENANT, not our endpoint: the vendor mints
# per-team ClickHouse connection hosts under that apex, so anyone who can sign up gets a
# hostname this pattern takes. The pin narrows the adversary set from *anyone* to *any Better
# Stack customer*; it does not close it (ADR-052 — a hostname pin is not automatically a
# boundary). Both known live values end `-connect.betterstackdata.com`, so a tighter
# `*-connect.betterstackdata.com`, or a two-value equality, is available. The wider apex is
# chosen deliberately: query connections are region-scoped and re-mintable, and a two-value pin
# would break every consumer the day one is re-minted in another region.
#
# HOW A TEST EXERCISES THE EGRESS PATH: SHIM `curl`. run_sql is the sole egress site and the
# sole curl in this file, so shadowing curl as a shell function (or shipping a shim on PATH)
# intercepts the boundary itself and proves no request escaped — see
# tests/scripts/test-betterstack-query-archive.sh and
# tests/scripts/test-git-data-rung2-evidence-capture.sh, which do exactly that with a
# vendor-shaped synthetic host. There is deliberately NO env-declared host-override seam: a
# seam an actor can set is the seam this pin exists to close.
case "$BETTERSTACK_QUERY_HOST" in
  *[[:cntrl:]]*|*@*|*/*|*\?*|*\#*|*:*:*|"")
    printf 'betterstack-query.sh: refusing to send credentials to a malformed BETTERSTACK_QUERY_HOST (expected a bare host[:port], got %s characters of something else)\n' \
      "${#BETTERSTACK_QUERY_HOST}" >&2
    exit 2
    ;;
esac

_bs_auth="${BETTERSTACK_QUERY_HOST%%/*}"   # path
_bs_auth="${_bs_auth%%\?*}"                # query on an authority-only value
_bs_auth="${_bs_auth%%#*}"                 # fragment
_bs_auth="${_bs_auth##*@}"                 # userinfo: the real host is what follows the LAST @
_bs_host="${_bs_auth%%:*}"                 # explicit port
_bs_host="${_bs_host%.}"                   # ONE trailing dot: `host.` is a valid absolute FQDN
_bs_host="${_bs_host,,}"                   # DNS is case-insensitive; a `case` glob is not
# (The first four are no-ops against a value the shape arm above already accepted. They are
# kept because the pin must not depend on that arm's arms staying exactly as they are — the
# allowlist has to be sound on its own input.)
case "$_bs_host" in
  *.betterstackdata.com) : ;;
  *)
    printf "betterstack-query.sh: refusing to send credentials to '%s' — BETTERSTACK_QUERY_HOST must be a Better Stack query endpoint matching *.betterstackdata.com (#7898). This allowlist is not a seam: a synthetic destination for a test is provided by shimming curl, not by overriding the host.\n" \
      "$_bs_host" >&2
    exit 2
    ;;
esac

# (#7898 §6, step 1.1b) THE HOST IS NOT THE ONLY DESTINATION-SHAPED INPUT IN THE REQUEST.
# BS_TABLE and BS_TABLE_S3 are env-settable AND flag-settable (`--table` / `--table-s3`), and
# they interpolate UNQUOTED into ClickHouse's `remote(...)` and `s3Cluster(primary, ...)` table
# functions — whose leading argument positions are an ADDRESS expression and a URL. The flag
# loop that reads them runs BELOW this point, so before this validation nothing checked them at
# any point, and the same actor the host pin defends against sets them in the same breath. The
# credential does not travel via remote(), and the vendor's server-side handling of these
# functions is not verified here — so this is not asserted as an exploit. It is closed because
# "the destination is pinned" is this change's headline claim and an unvalidated
# destination-shaped argument in every mode-2 request would leave that claim broader than what
# ships. Identifiers only; refuse rather than quote, because the correct value is always a bare
# ClickHouse table identifier (`t<team>_<name>_logs` / `_s3`).
require_table_identifier() {  # $1 = variable name (for the message), $2 = value
  case "$2" in
    *[!A-Za-z0-9_]*|"")
      printf "betterstack-query.sh: refusing %s='%s' — table identifiers must match ^[A-Za-z0-9_]+\$. These interpolate into remote() and s3Cluster(), whose leading arguments are an address and a URL, so a non-identifier value re-points the query the way an unpinned host re-points the credential (#7898).\n" \
        "$1" "$2" >&2
      exit 2
      ;;
  esac
}

# ClickHouse string literals honour C-STYLE BACKSLASH escapes in addition to ''
# doubling, so doubling alone does NOT close the literal (#7898 review). A value
# ending in a backslash escapes the quote that doubling just added:
#
#   --until "x\' OR 1=1 -- "   ->   dt <= 'x\'' OR 1=1 -- '
#
# ClickHouse reads 'x\'' as the literal x' and the rest is live SQL, which reaches
# url()/s3()/remote() and therefore egress. Escape the BACKSLASH FIRST, then the
# quote -- order is load-bearing: doubling first would then have its own backslashes
# escaped and the value would be corrupted.
sql_quote() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\'/\'\'}"
  printf '%s' "$v"
}

S3_EXPLICIT=0
[[ -n "${BS_TABLE_S3:-}" ]] && S3_EXPLICIT=1
export BS_TABLE_S3="${BS_TABLE_S3:-${BS_TABLE%_logs}_s3}"

# Env-seeded values, validated before mode 1 — which runs its query and exits without ever
# reaching the flag loop.
require_table_identifier BS_TABLE "$BS_TABLE"
require_table_identifier BS_TABLE_S3 "$BS_TABLE_S3"

run_sql() {
  # $1 = SQL. Credentials via Basic auth; never echoed.
  curl --disable --noproxy '*' -sS --fail-with-body --max-time 60 \
    -u "${BETTERSTACK_QUERY_USERNAME}:${BETTERSTACK_QUERY_PASSWORD}" \
    -H 'Content-type: plain/text' \
    -X POST "https://${BETTERSTACK_QUERY_HOST}?output_format_pretty_row_numbers=0" \
    -d "$1"
}

# --- Mode 1: raw SQL ---
# Callers may write the literal token `$BS_TABLE` in their SQL; we substitute it
# here so the table identifier survives `doppler run -- ... "$BS_TABLE"` quoting
# (the env var would otherwise stay unexpanded inside the single-quoted arg).
if [[ $# -ge 1 && "$1" =~ ^[[:space:]]*(SELECT|WITH|SHOW)[[:space:]] ]]; then
  # $BS_TABLE_S3 MUST be substituted before $BS_TABLE: the latter is a prefix of the
  # former, so the reverse order would rewrite `$BS_TABLE_S3` into `<hot_table>_S3` —
  # a table that does not exist — and the caller would see a confusing UNKNOWN_TABLE
  # instead of their archive rows.
  sql="${1//\$BS_TABLE_S3/$BS_TABLE_S3}"
  run_sql "${sql//\$BS_TABLE/$BS_TABLE}"
  exit $?
fi

# --- Mode 2: convenience flags ---
SINCE="1h"; UNTIL=""; LIMIT=100; RAW_ONLY=0; NO_ARCHIVE=0
GREPS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --grep)  GREPS+=("$2"); shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --raw-only) RAW_ONLY=1; shift ;;
    --no-archive) NO_ARCHIVE=1; shift ;;
    --table) BS_TABLE="$2"; export BS_TABLE; shift 2 ;;
    --table-s3) BS_TABLE_S3="$2"; S3_EXPLICIT=1; export BS_TABLE_S3; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

# Re-derive the archive name AFTER flag parsing so `--table` and `--table-s3` are
# order-independent: an explicit --table-s3 (or BS_TABLE_S3 env) always wins, whichever
# side it was passed on.
if (( ! S3_EXPLICIT )); then
  # Only the `_logs` suffix has a known `_s3` counterpart. The runbook documents `_metrics`
  # and `_spans` tables too; guessing `<name>_metrics_s3` for those would invent a table the
  # caller never named — silently querying the wrong source if it happens to exist. Demand
  # an explicit archive name instead of guessing.
  if [[ "$BS_TABLE" != *_logs ]]; then
    if (( NO_ARCHIVE )); then
      BS_TABLE_S3=""   # unused on this path; nothing to derive.
    else
      cat >&2 <<EOF
betterstack-query.sh: cannot derive an archive table from BS_TABLE='${BS_TABLE}'.

Only <name>_logs has a known <name>_s3 counterpart. For any other table, name the archive
explicitly or opt out of it:

  --table-s3 <archive_table>   (or BS_TABLE_S3=<archive_table>)
  --no-archive                 (hot window only — returns ~40 minutes; see the header)
EOF
      exit 64
    fi
  else
    BS_TABLE_S3="${BS_TABLE%_logs}_s3"
  fi
fi
export BS_TABLE_S3

# Re-validate: --table / --table-s3 are parsed BELOW the host check, and the archive name is
# re-derived above, so the env-time validation does not cover either.
require_table_identifier BS_TABLE "$BS_TABLE"
# The one legitimate empty value: --no-archive on a non-_logs table has no archive to name.
[[ -n "$BS_TABLE_S3" ]] && require_table_identifier BS_TABLE_S3 "$BS_TABLE_S3"

# --limit interpolates raw into `LIMIT ${LIMIT}`. 64 (usage error), not 2: this is a
# caller-typo shape, not a redirected destination.
if [[ ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  printf 'betterstack-query.sh: --limit must be a non-negative integer, got %s\n' "$LIMIT" >&2
  exit 64
fi

# Build the WHERE clause. `dt` is the ClickHouse event-time column.
# --since accepts Nh / Nm / Nd (relative) or a literal 'YYYY-MM-DD HH:MM:SS'.
if [[ "$SINCE" =~ ^([0-9]+)([hmd])$ ]]; then
  unit="${BASH_REMATCH[2]}"
  case "$unit" in h) ivl="HOUR";; m) ivl="MINUTE";; d) ivl="DAY";; esac
  WHERE="dt >= now() - INTERVAL ${BASH_REMATCH[1]} ${ivl}"
else
  # --grep was the only input that got quote-escaping; --since and --until land in the same
  # single-quoted SQL literal position and got none. Same escape, same reason.
  WHERE="dt >= '$(sql_quote "$SINCE")'"
fi
[[ -n "$UNTIL" ]] && WHERE="${WHERE} AND dt <= '$(sql_quote "$UNTIL")'"

if (( RAW_ONLY )); then
  # Exclude Vector host-metrics and journald supervisor noise — leaves app logs.
  WHERE="${WHERE} AND raw NOT LIKE '%\"namespace\":\"host\"%' AND raw NOT LIKE '%SYSLOG_IDENTIFIER%'"
fi

if (( ${#GREPS[@]} > 0 )); then
  ORS=""
  for g in "${GREPS[@]}"; do
    # Escape single quotes in the grep term for SQL.
    esc="$(sql_quote "$g")"
    ORS="${ORS}${ORS:+ OR }raw LIKE '%${esc}%'"
  done
  WHERE="${WHERE} AND (${ORS})"
fi

# Hot window + s3 archive, UNION ALL-combined (runbook §Query mechanics). ORDER BY and
# LIMIT apply to the COMBINED set — pushing them inside either arm would truncate each
# half independently and interleave wrongly.
#
# LIMIT takes the NEWEST rows (inner ORDER BY dt DESC), then the outer ORDER BY dt ASC
# restores chronological output. Both halves are load-bearing:
#   - DESC inner: before the archive arm existed the window was structurally <=40 min, so
#     LIMIT effectively never bound and ASC+LIMIT was harmless. Against a real 24h window it
#     bites — the runbook's own `--since 48h --grep SOLEUR_CLAUDE_COST --limit 20` would
#     answer "show me recent costs" with the OLDEST 20 markers, i.e. ~48h stale. "Most
#     recent N" is what every caller of a log tail means.
#   - ASC outer: callers (and humans) read oldest->newest; flipping output order would be a
#     silent behavior change for anything parsing the stream positionally.
#
# FAIL LOUD, never silently hot-only: returning a short answer to `--since 24h` is the
# exact failure this fix exists to remove, and it is invisible at the call site (a caller
# counting events sees "not yet filled", not "your window was truncated"). If the archive
# arm errors, the whole query errors and the caller must opt out deliberately with
# --no-archive rather than be handed partial data it will read as complete.
if (( NO_ARCHIVE )); then
  run_sql "SELECT dt, raw FROM (
  SELECT dt, raw FROM remote(${BS_TABLE}) WHERE ${WHERE} ORDER BY dt DESC LIMIT ${LIMIT}
) ORDER BY dt ASC FORMAT JSONEachRow"
else
  run_sql "SELECT dt, raw FROM (
  SELECT dt, raw FROM (
    SELECT dt, raw FROM remote(${BS_TABLE}) WHERE ${WHERE}
    UNION ALL
    SELECT dt, raw FROM s3Cluster(primary, ${BS_TABLE_S3}) WHERE _row_type = 1 AND (${WHERE})
  ) ORDER BY dt DESC LIMIT ${LIMIT}
) ORDER BY dt ASC FORMAT JSONEachRow"
fi
