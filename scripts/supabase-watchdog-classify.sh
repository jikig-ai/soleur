#!/usr/bin/env bash
# supabase-watchdog-classify.sh — the single verdict chokepoint for the bounded
# Supabase Postgres-hang auto-restart watchdog (#9168). SOURCED by
# .github/workflows/scheduled-supabase-watchdog.yml (via the CLI modes below)
# AND by scripts/supabase-watchdog-classify.test.sh. PURE: no network, no
# credentials, no writes — given the Management-API health reads and the
# corroborator token it emits exactly one verdict token.
#
# WHY (the two observed incidents): on 2026-09-15 and 2026-09-28 the prd
# Postgres hung with the SAME Management-API shape — db, auth and rest all
# UNHEALTHY while the pooler stayed ACTIVE_HEALTHY (runbook
# app-database-readiness-alarm.md step 4). Recovery needed an operator-ack'd
# POST /v1/projects/{ref}/restart. This classifier exists so a restart is issued
# ONLY on that proven signature — sustained over >=3 consecutive reads AND
# corroborated by an independent surface (app /health's `supabase` field) —
# because the Management API is a single failure surface and a prod write needs
# two agreeing signals (Guard 1, plan mutation matrix).
#
# VERDICTS (per-read and window share the same tokens):
#   hang-signature     the EXACT set {db, auth, rest} = UNHEALTHY AND
#                      pooler = ACTIVE_HEALTHY, every other reported service
#                      ACTIVE_HEALTHY, AND (window level) the corroborator
#                      reports the DB-bad state
#   healthy            every required service present and every reported service
#                      ACTIVE_HEALTHY
#   ambiguous          anything else the API answered with: partial outage,
#                      pooler also UNHEALTHY (total-outage shape — NOT the hang),
#                      COMING_UP mid-window, missing keys, unknown status
#                      vocabulary, or a corroborator that is connected /
#                      unreachable / unrecognised. NEVER restarts.
#   probe-unavailable  the probe itself is dark: non-200 Management-API read,
#                      non-JSON/empty body, or an under-observed window (<3
#                      reads). NEVER restarts. CLI exit is NON-ZERO on this
#                      verdict — an exit-0 hang-verdict on garbage is the
#                      vacuous arm (plan mutation 6).
#
# RESTART LEDGER — the audit issue's comments are the only state: each restart
# ATTEMPT carries a sentinel `<!-- watchdog:restart epoch=<unix> -->` written AT
# the POST (never on confirmed 2xx — a timed-out POST may have landed, so the
# attempt is recorded, never retried). parse_restart_ledger extracts
# {attempts, last_epoch, corrupt}; watchdog_decision folds verdict + ledger +
# WATCHDOG_ARMED into ONE action token:
#   restart | detect-only | cooldown | give-up | fail-closed | no-action
#
# CLI (what the workflow invokes):
#   --self-test                                  prints hang-signature, exit 0
#                                                (observability discoverability_test;
#                                                exercises the real path on embedded
#                                                fixtures — <5s, no network)
#   --corroborator TOKEN --read CODE BODY ...    >=3 --read pairs; prints the
#                                                window verdict; exit 2 on
#                                                probe-unavailable, 64 on usage
#   --ledger                                     reads issue-comment text on stdin,
#                                                prints "attempts=N last_epoch=N|none corrupt=0|1"
#   --decide --verdict V --armed 0|1 --corrupt 0|1 --claimed 0|1 \
#           --attempts N --last-epoch E|none --now E [--cooldown-sec S] [--max-attempts N]
#                                                prints the action token, exit 0
#
# TRANSPORT: this script does none, deliberately — the bearer-on-stdin /
# pinned-host / --disable --noproxy contract lives in the workflow's curls
# (scripts/supabase-logs-query.sh precedent). Keeping the classifier pure is
# what makes the verdict deterministically testable.

# --- per-read ---------------------------------------------------------------
# $1 = HTTP status ("000" on transport failure), $2 = response body.
classify_health_read() {
  local code="$1" body="$2"
  if [[ "$code" != "200" ]]; then
    echo "probe-unavailable"; return 0
  fi
  # A 200 that is not a JSON array is a probe-shape failure, not a verdict.
  if ! printf '%s' "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "probe-unavailable"; return 0
  fi
  local pairs
  # Field vocabulary is validated INSIDE jq on the raw values — a `\n` or `=`
  # inside a crafted name/status would otherwise split into multiple emitted
  # lines that each pass a post-split check (field-injection). @@BAD@@ is a
  # deliberate non-vocabulary token: it lands in the `*)` arm → extra_bad.
  pairs="$(printf '%s' "$body" | jq -r \
    'if all(.[]; type == "object")
     then .[] | if (.name | type == "string") and (.name | test("^[a-z_]+$"))
                 and (.status | type == "string") and (.status | test("^[A-Z_]+$"))
                 then "\(.name)=\(.status)"
                 else "@@BAD@@" end
     else "@@BAD@@" end' 2>/dev/null)" || {
    echo "probe-unavailable"; return 0
  }
  local db="" auth="" rest="" pooler="" extra_bad=0
  local line n s
  # Duplicate service names in the response (last-wins otherwise) and out-of-
  # vocabulary name/status tokens are a malformed observation, not a signature
  # — defense-in-depth: either shape would let a crafted body hide an extra
  # unhealthy service behind a later ACTIVE_HEALTHY duplicate.
  local dup_bad=0
  declare -A seen=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%=*}"; s="${line#*=}"
    [[ "$n" =~ ^[a-z_]+$ && "$s" =~ ^[A-Z_]+$ ]] || { extra_bad=1; continue; }
    if [[ -n "${seen[$n]:-}" ]]; then dup_bad=1; fi
    seen[$n]=1
    case "$n" in
      db)     db="$s" ;;
      auth)   auth="$s" ;;
      rest)   rest="$s" ;;
      pooler) pooler="$s" ;;
      # Any EXTRA service that is not plainly healthy makes the observed set a
      # superset of the signature — name it ambiguous, not a subset match.
      *)      [[ "$s" == "ACTIVE_HEALTHY" ]] || extra_bad=1 ;;
    esac
  done <<< "$pairs"
  [[ "$dup_bad" -eq 1 ]] && extra_bad=1
  # An observation missing a required key is incomplete, never a signature.
  if [[ -z "$db" || -z "$auth" || -z "$rest" || -z "$pooler" ]]; then
    echo "ambiguous"; return 0
  fi
  if [[ "$db" == "UNHEALTHY" && "$auth" == "UNHEALTHY" && "$rest" == "UNHEALTHY" \
     && "$pooler" == "ACTIVE_HEALTHY" && "$extra_bad" -eq 0 ]]; then
    echo "hang-signature"; return 0
  fi
  if [[ "$extra_bad" -eq 0 \
     && "$db" == "ACTIVE_HEALTHY" && "$auth" == "ACTIVE_HEALTHY" \
     && "$rest" == "ACTIVE_HEALTHY" && "$pooler" == "ACTIVE_HEALTHY" ]]; then
    echo "healthy"; return 0
  fi
  echo "ambiguous"
}

# --- window + corroborator ---------------------------------------------------
# $1 = corroborator token (the app's /health `.supabase` field verbatim, or the
#      literal `unreachable` when that read failed/was unparseable),
# $2.. = per-read verdicts from classify_health_read (>=3 required).
classify_window() {
  local corr="$1"; shift
  # An under-observed window is a probe failure, not a shorter signature — the
  # >=3 sustained-reads requirement is part of the signature, not a nicety.
  if (( $# < 3 )); then
    echo "probe-unavailable"; return 0
  fi
  local v all_sig=1 all_healthy=1
  for v in "$@"; do
    if [[ "$v" == "probe-unavailable" ]]; then
      echo "probe-unavailable"; return 0
    fi
    [[ "$v" == "hang-signature" ]] || all_sig=0
    [[ "$v" == "healthy" ]] || all_healthy=0
  done
  if (( all_sig )); then
    # Corroboration is the second-surface requirement: only the recognised
    # DB-bad token (`error`, the /health contract's non-connected state)
    # corroborates. `connected` (single-surface disagreement), `unreachable`
    # (corroborator dark), empty or unrecognised all yield ambiguous — a restart
    # never fires on the Management API's word alone, and never blind.
    if [[ "$corr" == "error" ]]; then
      echo "hang-signature"
    else
      echo "ambiguous"
    fi
    return 0
  fi
  if (( all_healthy )); then echo "healthy"; else echo "ambiguous"; fi
}

# --- restart ledger ----------------------------------------------------------
# Reads concatenated audit-issue comment bodies on stdin; prints
# "attempts=<n> last_epoch=<n|none> corrupt=<0|1>".
# A sentinel is the strict form `<!-- watchdog:restart epoch=<9-11 digits> -->`.
# ANY comment marker carrying the `watchdog:restart` token that fails the strict
# parse marks the ledger corrupt — the workflow then fails CLOSED (no restart +
# an error check-in), because an audit trail that cannot bound a write must not
# precede one (plan mutation 10).
parse_restart_ledger() {
  local text attempts=0 corrupt=0 last_epoch="none"
  text="$(cat)"
  local marker e
  # Two greps: the SEEN pattern catches every comment-marker occurrence of the
  # token (closed or run-to-EOL), the strict =~ decides validity per marker.
  while IFS= read -r marker; do
    [[ -n "$marker" ]] || continue
    if [[ "$marker" =~ ^\<!--[[:space:]]*watchdog:restart[[:space:]]+epoch=([0-9]{9,11})[[:space:]]*--\>$ ]]; then
      attempts=$((attempts + 1))
      e="${BASH_REMATCH[1]}"
      # `10#$e` base-pins the comparison: a 0-prefixed epoch containing 8/9
      # would error inside (( )) and silently lose the last_epoch max.
      if [[ "$last_epoch" == "none" ]] || (( 10#$e > 10#$last_epoch )); then
        last_epoch="$e"
      fi
    else
      corrupt=1
    fi
  done < <(printf '%s\n' "$text" | grep -oE '<!--[^>]*watchdog:restart[^>]*(-->|$)' || true)
  printf 'attempts=%s last_epoch=%s corrupt=%s\n' "$attempts" "$last_epoch" "$corrupt"
}

# --- the restart decision -----------------------------------------------------
# watchdog_decision VERDICT ARMED CORRUPT CLAIMED ATTEMPTS LAST_EPOCH NOW
#                   [COOLDOWN_SEC=1800] [MAX_ATTEMPTS=3]
# CLAIMED = the audit issue carries the `watchdog-restart-attempted` label (the
# claim marker the workflow writes AFTER the POST, so claimed-with-no-sentinel
# strictly means a completed attempt whose sentinel was deleted).
#
# Order is load-bearing: fail-closed beats everything (an untrustworthy ledger
# or a claim without a sentinel can never bound a write); detect-only beats the
# ledger arms (an unarmed watchdog never writes, whatever the history says);
# give-up beats cooldown (exhausted attempts escalate, they do not wait out a
# cooldown); restart is last.
watchdog_decision() {
  local verdict="$1" armed="$2" corrupt="$3" claimed="$4" attempts="$5" \
        last_epoch="$6" now="$7"
  local cooldown_sec="${8:-1800}" max_attempts="${9:-3}"
  # Base-pin the epoch once: a 0-prefixed value containing 8/9 aborts (( ))
  # arithmetic under -u with no output — failing LOUD to the caller's rescue
  # path is fine, but normalizing keeps the function pure on valid input.
  [[ "$last_epoch" =~ ^[0-9]+$ ]] && last_epoch="$((10#$last_epoch))"
  if [[ "$verdict" != "hang-signature" ]]; then
    echo "no-action"; return 0
  fi
  if [[ "$corrupt" == "1" ]] || { [[ "$claimed" == "1" ]] && [[ "$attempts" == "0" ]]; }; then
    echo "fail-closed"; return 0
  fi
  if [[ "$armed" != "1" ]]; then
    echo "detect-only"; return 0
  fi
  if (( attempts >= max_attempts )); then
    echo "give-up"; return 0
  fi
  # A far-FUTURE epoch (edited/forged sentinel, or clock skew past tolerance)
  # would make `now - last_epoch` negative and yield a silent PERMANENT
  # cooldown — the bound can't be weakened by it, but the watchdog would never
  # restart again with no signal. Fail closed loudly instead.
  if [[ "$last_epoch" =~ ^[0-9]+$ ]] && (( last_epoch > now + 300 )); then
    echo "fail-closed"; return 0
  fi
  if [[ "$last_epoch" =~ ^[0-9]+$ ]] && (( now - last_epoch < cooldown_sec )); then
    echo "cooldown"; return 0
  fi
  echo "restart"
}

# --- CLI ----------------------------------------------------------------------
_selftest_sig='[{"name":"db","status":"UNHEALTHY"},{"name":"auth","status":"UNHEALTHY"},{"name":"rest","status":"UNHEALTHY"},{"name":"pooler","status":"ACTIVE_HEALTHY"}]'

_usage() {
  cat >&2 <<'USAGE'
usage: supabase-watchdog-classify.sh --self-test
       supabase-watchdog-classify.sh --corroborator TOKEN --read CODE BODY [--read CODE BODY]...
       supabase-watchdog-classify.sh --ledger            # comment text on stdin
       supabase-watchdog-classify.sh --decide --verdict V --armed 0|1 --corrupt 0|1 \
         --claimed 0|1 --attempts N --last-epoch E|none --now E [--cooldown-sec S] [--max-attempts N]
USAGE
}

main() {
  set -uo pipefail
  case "${1:-}" in
    --self-test)
      # Exercise the REAL path over embedded fixtures — the observability
      # discoverability_test contract is `prints hang-signature`, and a broken
      # classifier must not fake it: print the computed verdict and fail loudly
      # if it is not the signature.
      local v
      v="$(classify_window error \
        "$(classify_health_read 200 "$_selftest_sig")" \
        "$(classify_health_read 200 "$_selftest_sig")" \
        "$(classify_health_read 200 "$_selftest_sig")")"
      printf '%s\n' "$v"
      [[ "$v" == "hang-signature" ]]
      return
      ;;
    --ledger)
      parse_restart_ledger
      return
      ;;
    --decide)
      shift
      local verdict="" armed="" corrupt="" claimed="" attempts="" last_epoch="" now="" cooldown="" maxa=""
      while (( $# )); do
        # `shift 2` on a value-less flag fails WITHOUT shifting (the script runs
        # without -e) — bare `shift 2` here is an infinite loop, not an error.
        case "$1" in
          --verdict)       verdict="${2:-}";      shift 2 || { _usage; return 64; } ;;
          --armed)         armed="${2:-}";        shift 2 || { _usage; return 64; } ;;
          --corrupt)       corrupt="${2:-}";      shift 2 || { _usage; return 64; } ;;
          --claimed)       claimed="${2:-}";      shift 2 || { _usage; return 64; } ;;
          --attempts)      attempts="${2:-}";     shift 2 || { _usage; return 64; } ;;
          --last-epoch)    last_epoch="${2:-}";   shift 2 || { _usage; return 64; } ;;
          --now)           now="${2:-}";          shift 2 || { _usage; return 64; } ;;
          --cooldown-sec)  cooldown="${2:-}";     shift 2 || { _usage; return 64; } ;;
          --max-attempts)  maxa="${2:-}";         shift 2 || { _usage; return 64; } ;;
          *) _usage; return 64 ;;
        esac
      done
      # Vocabulary checks BEFORE the required-arg pass: a value-shaped typo
      # (`--claimed --now 5`) must die here, not flow into `(( ))` arithmetic
      # where strings coerce and `a[$(...)]` can evaluate.
      for pair in "armed:$armed" "corrupt:$corrupt" "claimed:$claimed"; do
        [[ "${pair#*:}" =~ ^[01]$ ]] || { _usage; return 64; }
      done
      for pair in "attempts:$attempts" "now:$now" "cooldown:${cooldown:-0}" "maxa:${maxa:-0}"; do
        [[ "${pair#*:}" =~ ^[0-9]+$ ]] || { _usage; return 64; }
      done
      [[ "$last_epoch" =~ ^[0-9]+$|^none$ ]] || { _usage; return 64; }
      # Two parallel arrays, not `${!name}`: indirect expansion resolves a
      # variable chosen at runtime, which prints its VALUE under `bash -x` —
      # the credential-leak class lint-shell-trace-credential-refusal guards.
      local -a req_names=(verdict armed corrupt claimed attempts last_epoch now)
      local -a req_vals=("$verdict" "$armed" "$corrupt" "$claimed" "$attempts" "$last_epoch" "$now")
      for ri in "${!req_names[@]}"; do
        if [[ -z "${req_vals[$ri]}" ]]; then
          printf 'supabase-watchdog-classify.sh: --decide requires --%s\n' "${req_names[$ri]}" >&2
          _usage; return 64
        fi
      done
      if [[ -n "$cooldown" && -n "$maxa" ]]; then
        watchdog_decision "$verdict" "$armed" "$corrupt" "$claimed" "$attempts" "$last_epoch" "$now" "$cooldown" "$maxa"
      elif [[ -n "$cooldown" ]]; then
        watchdog_decision "$verdict" "$armed" "$corrupt" "$claimed" "$attempts" "$last_epoch" "$now" "$cooldown"
      elif [[ -n "$maxa" ]]; then
        watchdog_decision "$verdict" "$armed" "$corrupt" "$claimed" "$attempts" "$last_epoch" "$now" 1800 "$maxa"
      else
        watchdog_decision "$verdict" "$armed" "$corrupt" "$claimed" "$attempts" "$last_epoch" "$now"
      fi
      return
      ;;
    --help|-h) _usage; return 0 ;;
    "") _usage; return 64 ;;
  esac

  # Classify mode: --corroborator TOKEN + >=3 --read CODE BODY pairs.
  local corr="unreachable"
  local -a codes=() bodies=()
  while (( $# )); do
    case "$1" in
      # Same bare-shift infinite-loop guard as --decide.
      --corroborator) corr="${2:-unreachable}"; shift 2 || { _usage; return 64; } ;;
      --read)
        if (( $# < 3 )); then _usage; return 64; fi
        codes+=("$2"); bodies+=("$3"); shift 3 ;;
      *) _usage; return 64 ;;
    esac
  done
  local -a verdicts=()
  local i
  for i in "${!codes[@]}"; do
    local rv
    rv="$(classify_health_read "${codes[$i]}" "${bodies[$i]}")"
    verdicts+=("$rv")
    printf 'read %d: http=%s verdict=%s\n' "$((i + 1))" "${codes[$i]}" "$rv" >&2
  done
  local verdict
  verdict="$(classify_window "$corr" "${verdicts[@]}")"
  printf 'corroborator=%s verdict=%s\n' "$corr" "$verdict" >&2
  printf '%s\n' "$verdict"
  if [[ "$verdict" == "probe-unavailable" ]]; then
    return 2
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
