#!/usr/bin/env bash
# watch-notify-once.sh — shared helpers for the code-quality follow-up watchers
# (.github/workflows/code-quality-followups-watch.yml). SOURCED, never executed.
#
# The only GitHub write any caller can make is `wn_post` (one `gh issue comment` on
# the caller's own tracker). Every other `gh` call here is a read: `issue view` and `api`
# reads (GET, plus one read-only GraphQL query). Nothing here closes, reopens, edits, labels or locks an
# issue, and nothing changes a repository setting (suite Guard 1 pins this).
#
# Contract for callers (set -uo pipefail, NOT set -e):
#   wn_read_issue N        -> rc 0 ok (sets WN_STATE WN_CREATED WN_JSON)
#                             rc 4 tracker gone (404/410/"Could not resolve to an issue")
#                             rc 3 any other failure (post nothing, retry next run)
#   wn_sentinel_present K  -> rc 0 present, 1 absent, 3 comments unreadable
#   wn_post N              -> body on stdin; rc 0 posted, rc 1 post failed
#   wn_notify_once_main T EARLIEST KEY GATHER_FN
#                          -> GATHER_FN sets WN_BODY (no sentinel) and returns 0, or 3
#
# Exit-code vocabulary shared by the callers: 0 ok / no-op, 1 post failed, 2 usage,
# 3 cannot establish, 78 refusing to run under xtrace.

# The org whose billing the dated watchers read, and the repo whose search they run.
WN_ORG=jikig-ai
# ADR-276: the metered Code Quality line dated 2026-10-20 covers usage up to the switch-off
# (the meter posts a day late), so NO `code_quality` line dated on or after this day is expected
# once the switch-off took effect. Both billing watchers compare against this one constant.
WN_BILLING_STOP_EXPECTED_BY=2026-10-21
WN_SENTINEL_PREFIX='code-quality-followups-watch'

WN_STATE=""; WN_CREATED=""; WN_JSON=""; WN_BODY=""; WN_BILL_STATUS=""; WN_BILL_JSON=""
# Unconditional: only the --dry-run flag may enable dry-run. An inherited WN_DRY_RUN=1 must never
# silently turn a real run into a dry one. (The xtrace refusal lives INLINE at the top of each script,
# before this file is sourced, so no -x trace can print the token while sourcing.)
WN_DRY_RUN=0
WN_ERR_HTTP=""

# wn_preflight: the tools every watcher needs. rc 3 names the first missing one.
wn_preflight() {
  local t
  for t in gh jq perl git; do
    command -v "$t" >/dev/null 2>&1 || { echo "::error::required tool '$t' is not on PATH; cannot run" >&2; return 3; }
  done
  return 0
}

# ---------------------------------------------------------------- date gate ----
# WATCH_NOW is a test seam (ISO-8601 Z). Epoch values are validated before arithmetic:
# a leading zero is octal in bash.
wn_now_iso() { printf '%s' "${WATCH_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"; }

wn_epoch() {
  local iso="$1" e
  [[ "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 3
  e="$(date -u -d "$iso" +%s 2>/dev/null)" || return 3
  [[ "$e" =~ ^[1-9][0-9]{0,15}$ ]] || return 3
  printf '%s' "$e"
}

# wn_reached ISO: rc 0 when now >= ISO, 1 when not yet, 3 on an unusable value.
wn_reached() {
  local now_e want_e
  now_e="$(wn_epoch "$(wn_now_iso)")" || return 3
  want_e="$(wn_epoch "$1")" || return 3
  [[ "$now_e" -ge "$want_e" ]]
}

# ------------------------------------------------------------------ scratch --
# One owning scratch directory per process, created here at source time from an absolute base so
# every write and removal below is rooted at a binding the fixture scanner can resolve (the same
# shape script 3 uses for its WORK directory). Stderr captures live inside it and the EXIT trap
# removes it, so nothing is left behind if a caller dies between allocation and cleanup. A caller
# that installs its own EXIT trap afterwards must call wn_cleanup from it (script 3 does).
WN_TMP_BASE=${TMPDIR:-/var/tmp}
WN_TMPDIR="$(mktemp -d "$WN_TMP_BASE/wn.XXXXXXXX")" || { echo "::error::cannot create the watcher scratch directory" >&2; return 3; }
WN_ERRF=""
wn_cleanup() {
  [[ -n "$WN_TMPDIR" ]] || return 0
  rm -rf "$WN_TMPDIR"
  WN_TMPDIR=""
}
trap wn_cleanup EXIT
# wn_errfile: set WN_ERRF to a fresh empty file inside the scratch directory (current shell only:
# never call this from a command substitution, or the assignment is lost with the subshell).
wn_errfile() {
  [[ -n "$WN_TMPDIR" ]] || return 1
  WN_ERRF="$(mktemp "$WN_TMPDIR/err.XXXXXXXX")" || return 1
}

# ------------------------------------------------------------ issue + comments --
wn_read_issue() {
  local n="$1" err errf out
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || return 3
  wn_errfile || return 3
  errf="$WN_ERRF"
  out="$(gh issue view "$n" --json state,createdAt,comments 2>"$errf")"
  local rc=$?
  err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  if [[ "$rc" -ne 0 ]]; then
    WN_ERR_HTTP="$(printf '%s' "$err" | grep -oE 'HTTP [0-9]{3}' | head -n 1 || true)"
    case "$err" in
      *"Could not resolve to an issue"*|*"HTTP 404"*|*"HTTP 410"*) return 4 ;;
    esac
    return 3
  fi
  WN_STATE="$(printf '%s' "$out" | jq -r '.state // empty' 2>/dev/null)" || WN_STATE=""
  WN_CREATED="$(printf '%s' "$out" | jq -r '.createdAt // empty' 2>/dev/null)" || WN_CREATED=""
  if [[ -z "$WN_STATE" ]]; then return 3; fi
  if ! printf '%s' "$out" | jq -e '(.comments | type) == "array"' >/dev/null 2>&1; then return 3; fi
  WN_JSON="$out"
  return 0
}

# The full namespaced sentinel for a key, e.g. `reeval-9730:v1` or `trigger-2:<40 hex>`.
wn_sentinel() { printf '<!-- %s:%s -->' "$WN_SENTINEL_PREFIX" "$1"; }

# Only a comment authored by the Actions bot counts: any account can paste the string,
# so a human-authored sentinel never suppresses. A jq failure is "unreadable", never
# "absent". The key is matched as the whole string including the closing `-->`, so a
# short sha or `v10` cannot false-match.
wn_sentinel_present() {
  local s count
  s="$(wn_sentinel "$1")"
  count="$(printf '%s' "$WN_JSON" | jq -r --arg s "$s" '
      [.comments[]
       | select(((.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]")
                and ((.body // "") | contains($s)))] | length' 2>/dev/null)" || return 3
  [[ "$count" =~ ^[0-9]+$ ]] || return 3
  [[ "$count" -gt 0 ]] && return 0
  return 1
}

# The one writer. Body on stdin.
wn_post() {
  local n="$1" errf rc
  if wn_errfile; then errf="$WN_ERRF"; else errf=/dev/null; fi
  gh issue comment "$n" --body-file - >/dev/null 2>"$errf"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    # Cause only (the HTTP status), never the response text.
    WN_ERR_HTTP="$(grep -oE 'HTTP [0-9]{3}' "$errf" 2>/dev/null | head -n 1 || true)"
    [[ "$errf" == /dev/null ]] || rm -f "$errf"
    return 1
  fi
  [[ "$errf" == /dev/null ]] || rm -f "$errf"
  return 0
}

# ----------------------------------------------------------------- sanitizing --
# Render ONE third-party string (title, login, path, commit subject, gate reason) as
# an inert code span: C0 controls, DEL, line/paragraph separators, bidi overrides,
# zero-width characters, every Default_Ignorable_Code_Point (Hangul fillers, the combining
# grapheme joiner, variation selectors, tag characters) and the blank braille U+2800 are dropped; backtick, <, > and & become spaces (so a closing
# `-->`, an HTML comment opener or an entity cannot survive); cut to 100 characters.
# Inside a code span @mentions, #N back-references and bare URLs do not notify.
wn_sanitize() {
  WN_S="$1" perl -e '
    use strict; use warnings; use Encode qw(decode encode);
    my $s = decode("UTF-8", $ENV{WN_S} // "", Encode::FB_DEFAULT);
    $s =~ s/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}\x{0085}\x{061C}\x{115F}\x{3164}\x{180B}-\x{180F}\x{2800}\x{FE00}-\x{FE0F}\x{E0000}-\x{E007F}]//g;
    $s =~ s/[`<>&]/ /g;
    $s = substr($s, 0, 100);
    print encode("UTF-8", "`" . $s . "`");'
}

# ------------------------------------------------------------------- billing ----
# wn_billing_month Y M: only the `code_quality` product is aggregated and kept; the
# org's whole bill is never published. Sets WN_BILL_STATUS (ok | unreadable:<http>) and
# WN_BILL_JSON ({lines,gross,net,first,last}). rc 0 for ok/unreadable, rc 3 for
# everything else (5xx, 429, rate-limit 403, network, unparseable) so a transient blip
# retries next run instead of spending the one-shot on a degraded comment.
# Year and month ride in the URL (never -f/-F), so the call stays a GET.
wn_billing_month() {
  local y="$1" m="$2" errf out err http rc
  [[ "$y" =~ ^20[0-9]{2}$ && "$m" =~ ^([1-9]|1[0-2])$ ]] || return 3
  local tag
  printf -v tag '%04d-%02d' "$y" "$((10#$m))"
  WN_BILL_STATUS=""; WN_BILL_JSON=""
  wn_errfile || return 3
  errf="$WN_ERRF"
  out="$(gh api "orgs/${WN_ORG}/settings/billing/usage?year=${y}&month=${m}" 2>"$errf")"
  rc=$?
  err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  if [[ "$rc" -ne 0 ]]; then
    http="$(printf '%s' "$err" | grep -oE 'HTTP [0-9]{3}' | head -n 1 | grep -oE '[0-9]{3}' || true)"
    case "$http" in
      401|404) WN_BILL_STATUS="unreadable:${http}"; return 0 ;;
      403)
        case "$err" in
          *[Rr]ate\ limit*|*secondary*)
            echo "::error::billing read for ${tag} was rate limited (HTTP 403); posting nothing, retrying next run" >&2
            return 3 ;;
        esac
        WN_BILL_STATUS="unreadable:403"; return 0 ;;
    esac
    echo "::error::billing read for ${tag} failed (${http:+HTTP }${http:-no HTTP status; network or client error}); posting nothing, retrying next run" >&2
    return 3
  fi
  WN_BILL_JSON="$(printf '%s' "$out" | jq -c '
      if (.usageItems | type) == "array" then
        [.usageItems[] | select((.product // "") | test("code[ _-]?quality"; "i"))]
        | {lines: length,
           gross: ((map(.grossAmount // 0) | add // 0) * 100 | round / 100),
           net: ((map(.netAmount // 0) | add // 0) * 100 | round / 100),
           first: (map(.date // empty) | min // null),
           last: (map(.date // empty) | max // null)}
      else error("no usageItems array") end' 2>/dev/null)" || {
    echo "::error::billing read for ${tag} returned an unexpected shape (no usageItems array); posting nothing, retrying next run" >&2
    return 3
  }
  [[ -n "$WN_BILL_JSON" ]] || return 3
  WN_BILL_STATUS="ok"
  return 0
}

# ------------------------------------------------------------------ main flow ---
# wn_notify_once_main TRACKER EARLIEST KEY GATHER_FN
# Order: earliest gate -> tracker OPEN? -> sentinel? -> gather -> compose -> post.
# --dry-run (WN_DRY_RUN=1): skip the earliest gate; still READ the tracker and its sentinel
# (read-only, never fatal) and report what was found; gather, print the would-be body, never
# post and never spend a sentinel.
wn_notify_once_main() {
  local tracker="$1" earliest="$2" key="$3" gather="$4" rc sentinel
  sentinel="$(wn_sentinel "$key")"
  if ! declare -F "$gather" >/dev/null 2>&1; then
    echo "::error::internal: gather function '${gather}' is not defined" >&2
    return 3
  fi

  if [[ "$WN_DRY_RUN" != 1 ]]; then
    wn_reached "$earliest"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::unusable earliest/now value; posting nothing" >&2; return 3; fi
    if [[ "$rc" -ne 0 ]]; then
      echo "::notice::#${tracker}: earliest ${earliest} not reached yet (now $(wn_now_iso)); nothing to do"
      return 0
    fi
    wn_read_issue "$tracker"; rc=$?
    if [[ "$rc" -eq 4 ]]; then echo "::notice::tracker #${tracker} no longer resolves; tracker gone, nothing to watch"; return 0; fi
    if [[ "$rc" -ne 0 ]]; then echo "::error::could not read #${tracker} (state/comments; ${WN_ERR_HTTP:-no HTTP status}); posting nothing, retrying next run" >&2; return 3; fi
    if [[ "$WN_STATE" != "OPEN" ]]; then
      echo "::notice::#${tracker} is '${WN_STATE}' (not OPEN); nothing to watch; delete the watcher per the RETIREMENT block in code-quality-followups-watch.yml"
      return 0
    fi
    wn_sentinel_present "$key"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::could not evaluate the comments of #${tracker}; posting nothing" >&2; return 3; fi
    if [[ "$rc" -eq 0 ]]; then echo "already notified: sentinel present on #${tracker}"; return 0; fi
  else
    # Dry-run still exercises the live READ path (read-only), so the post-merge dry-run dispatch
    # validates the tracker read and the sentinel reader. Never fatal here and never posts.
    wn_read_issue "$tracker"; rc=$?
    if [[ "$rc" -eq 0 ]]; then
      local notopen=""
      [[ "$WN_STATE" == "OPEN" ]] || notopen=" (not OPEN: a real run would post nothing)"
      wn_sentinel_present "$key"; rc=$?
      case "$rc" in
        0) echo "dry-run: tracker #${tracker} state=${WN_STATE}; sentinel already present (a real run would post nothing)" ;;
        1) echo "dry-run: tracker #${tracker} state=${WN_STATE}; sentinel absent${notopen}" ;;
        *) echo "::warning::dry-run: could not evaluate the comments of #${tracker}" ;;
      esac
    else
      echo "::warning::dry-run: could not read #${tracker} (${WN_ERR_HTTP:-rc ${rc}})"
    fi
  fi

  WN_BODY=""
  "$gather"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::#${tracker}: gathering the data failed (exit ${rc}); posting nothing, retrying next run" >&2
    return "$rc"
  fi
  [[ -n "$WN_BODY" ]] || { echo "::error::gather produced no body; posting nothing" >&2; return 3; }
  # GitHub rejects a comment over 65,536 characters; cut with a visible note rather than fail weekly.
  if [[ "${#WN_BODY}" -gt 60000 ]]; then
    WN_BODY="${WN_BODY:0:60000}"$'\n\n'"_(Truncated: the full data exceeded GitHub's comment size limit.)_"
    echo "::warning::#${tracker}: comment body truncated to fit GitHub's size limit"
  fi

  if [[ "$WN_DRY_RUN" == 1 ]]; then
    printf '%s\n\n%s\n' "$WN_BODY" "$sentinel"
    echo "dry-run: nothing posted, no sentinel spent"
    return 0
  fi
  # The sentinel is always the exact LAST line, built from constants only. wn_post runs in THIS
  # shell (a here-string, never a pipeline: a pipeline stage is a subshell and would drop
  # WN_ERR_HTTP, so the failure annotation below would never carry the real HTTP status).
  local payload
  payload="$(printf '%s\n\n%s' "$WN_BODY" "$sentinel")"
  if ! wn_post "$tracker" <<<"$payload"; then
    echo "::error::posting the notice on #${tracker} failed (${WN_ERR_HTTP:-no HTTP status}); nothing spent, retrying next run" >&2
    return 1
  fi
  echo "posted the one-time notice on #${tracker}"
  return 0
}
