#!/usr/bin/env bash
# watch-notify-once.sh — shared helpers for the code-quality follow-up watchers
# (.github/workflows/code-quality-followups-watch.yml). SOURCED, never executed.
#
# The only GitHub write any caller can make is `wn_post` (one `gh issue comment` on
# the caller's own tracker). Every other `gh` call here is a read: `issue view` and
# GET-shaped `api` calls. Nothing here closes, reopens, edits, labels or locks an
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
WN_ORG="${WN_ORG:-jikig-ai}"
WN_REPO_SLUG="${WN_REPO_SLUG:-jikig-ai/soleur}"
WN_SENTINEL_PREFIX='code-quality-followups-watch'

WN_STATE=""; WN_CREATED=""; WN_JSON=""; WN_BODY=""; WN_BILL_STATUS=""; WN_BILL_JSON=""
WN_DRY_RUN="${WN_DRY_RUN:-0}"

wn_refuse_xtrace() {
  case "$-" in
    *x*) printf '[FATAL] refusing to run under xtrace: this script holds a live GitHub token and -x would print it (see #7797)\n' >&2; exit 78 ;;
  esac
}

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

# ------------------------------------------------------------ issue + comments --
wn_read_issue() {
  local n="$1" err errf out
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || return 3
  errf="$(mktemp "${TMPDIR:-/var/tmp}/wn-err.XXXXXXXX")" || return 3
  out="$(gh issue view "$n" --json state,createdAt,comments 2>"$errf")"
  local rc=$?
  err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  if [[ "$rc" -ne 0 ]]; then
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
  local n="$1"
  gh issue comment "$n" --body-file - >/dev/null 2>&1 || return 1
  return 0
}

# ----------------------------------------------------------------- sanitizing --
# Render ONE third-party string (title, login, path, commit subject, gate reason) as
# an inert code span: C0 controls, DEL, line/paragraph separators, bidi overrides and
# zero-width characters are dropped; backtick, <, > and & become spaces (so a closing
# `-->`, an HTML comment opener or an entity cannot survive); cut to 100 characters.
# Inside a code span @mentions, #N back-references and bare URLs do not notify.
wn_sanitize() {
  WN_S="$1" perl -e '
    use strict; use warnings; use Encode qw(decode encode);
    my $s = decode("UTF-8", $ENV{WN_S} // "", Encode::FB_DEFAULT);
    $s =~ s/[\x00-\x1f\x7f\x{2028}\x{2029}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{200B}-\x{200F}\x{2060}\x{FEFF}]//g;
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
  WN_BILL_STATUS=""; WN_BILL_JSON=""
  errf="$(mktemp "${TMPDIR:-/var/tmp}/wn-err.XXXXXXXX")" || return 3
  out="$(gh api "orgs/${WN_ORG}/settings/billing/usage?year=${y}&month=${m}" 2>"$errf")"
  rc=$?
  err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  if [[ "$rc" -ne 0 ]]; then
    http="$(printf '%s' "$err" | grep -oE 'HTTP [0-9]{3}' | head -n 1 | grep -oE '[0-9]{3}' || true)"
    case "$http" in
      401|404) WN_BILL_STATUS="unreadable:${http}"; return 0 ;;
      403)
        case "$err" in
          *[Rr]ate\ limit*|*secondary*) return 3 ;;
        esac
        WN_BILL_STATUS="unreadable:403"; return 0 ;;
    esac
    return 3
  fi
  WN_BILL_JSON="$(printf '%s' "$out" | jq -c '
      if (.usageItems | type) == "array" then
        [.usageItems[] | select((.product // "") | test("code[ _-]?quality"; "i"))]
        | {lines: length,
           gross: (map(.grossAmount // 0) | add // 0),
           net: (map(.netAmount // 0) | add // 0),
           first: (map(.date // empty) | min // null),
           last: (map(.date // empty) | max // null)}
      else error("no usageItems array") end' 2>/dev/null)" || return 3
  [[ -n "$WN_BILL_JSON" ]] || return 3
  WN_BILL_STATUS="ok"
  return 0
}

# ------------------------------------------------------------------ main flow ---
# wn_notify_once_main TRACKER EARLIEST KEY GATHER_FN
# Order: earliest gate -> tracker OPEN? -> sentinel? -> gather -> compose -> post.
# --dry-run (WN_DRY_RUN=1): skip the gate, the issue read and the sentinel, gather,
# print the would-be body, never post and never spend a sentinel.
wn_notify_once_main() {
  local tracker="$1" earliest="$2" key="$3" gather="$4" rc sentinel
  sentinel="$(wn_sentinel "$key")"

  if [[ "$WN_DRY_RUN" != 1 ]]; then
    wn_reached "$earliest"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::unusable earliest/now value; posting nothing" >&2; return 3; fi
    if [[ "$rc" -ne 0 ]]; then
      echo "::notice::#${tracker}: earliest ${earliest} not reached yet (now $(wn_now_iso)); nothing to do"
      return 0
    fi
    wn_read_issue "$tracker"; rc=$?
    if [[ "$rc" -eq 4 ]]; then echo "::notice::tracker #${tracker} no longer resolves; tracker gone, nothing to watch"; return 0; fi
    if [[ "$rc" -ne 0 ]]; then echo "::error::could not read #${tracker} (state/comments); posting nothing" >&2; return 3; fi
    if [[ "$WN_STATE" != "OPEN" ]]; then
      echo "::notice::#${tracker} is '${WN_STATE}' (not OPEN); nothing to watch; delete the watcher per the RETIREMENT block in code-quality-followups-watch.yml"
      return 0
    fi
    wn_sentinel_present "$key"; rc=$?
    if [[ "$rc" -eq 3 ]]; then echo "::error::could not evaluate the comments of #${tracker}; posting nothing" >&2; return 3; fi
    if [[ "$rc" -eq 0 ]]; then echo "already notified: sentinel present on #${tracker}"; return 0; fi
  fi

  WN_BODY=""
  "$gather"; rc=$?
  if [[ "$rc" -ne 0 ]]; then return "$rc"; fi
  [[ -n "$WN_BODY" ]] || { echo "::error::gather produced no body; posting nothing" >&2; return 3; }

  if [[ "$WN_DRY_RUN" == 1 ]]; then
    printf '%s\n\n%s\n' "$WN_BODY" "$sentinel"
    echo "dry-run: nothing posted, no sentinel spent"
    return 0
  fi
  # The sentinel is always the exact LAST line, built from constants only.
  if ! printf '%s\n\n%s\n' "$WN_BODY" "$sentinel" | wn_post "$tracker"; then
    echo "::error::posting the notice on #${tracker} failed" >&2
    return 1
  fi
  echo "posted the one-time notice on #${tracker}"
  return 0
}
