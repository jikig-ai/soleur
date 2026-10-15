#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2018,SC2019  # A && B || C is the check idiom (C is a fail_* that exits); tr A-Z is the portable ASCII lowering
# The shared validity chokepoint for a Standing Delegation and its Production Envelope.
# Format source (the only one): plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md
#
# Property: the verifier reports `valid` only when a marker-first, unedited, unexpired, admin-authored
# comment on THIS repository's still-open epic carries a verbatim quote, a Confirmation line, the cited
# Scope item and a complete Excluded list, and (when asked) a complete, committed envelope whose Command
# block contains each asked command as a byte-identical FULL line. Anything it cannot evaluate is exit 2.
#
# Callers: technical-ruling-gate.sh, pre-ask-technical-fork-gate.sh, hold-gate-eval.sh and the CTO's
# pre-execution check. A caller that re-implements any conjunct here is the defect. Exit 2 always blocks
# its caller and is never retried into a pass; the hook alone treats it as "ask the question".
#
# Usage:
#   delegation-verify.sh verify --delegation <comment-url> [--envelope <path[#title]>] [--command <line>]... [--audit]
#   delegation-verify.sh render --epic <N> --question-file <f> --answer-file <f> --scope-file <f> --expiry <YYYY-MM-DD>
#   delegation-verify.sh keywords          (the Excluded anchor keywords, one per line)
#   delegation-verify.sh --self-check      (offline; prints `delegation-verify: ready`)
#
# stdout (verify): `delegation: valid|invalid|unverifiable reason=<token>`; with --command and `valid` also
#   `verified-command: <the exact envelope line>` and `verified-sha256: <hex>` per command, so the caller runs
#   the line byte for byte. stderr: one plain sentence. Exit 0 valid, 1 invalid, 2 unverifiable or usage.
# --audit (ship-time gate only) skips exactly two authorization-time checks, `expired` and `epic-closed`: a
#   delegated act that ran legitimately must not fail its own audit row after the epic closes.
#
# Reason tokens: bad-url wrong-repo comment-unreadable api-error tool-missing usage no-marker wrong-issue
#   epic-is-pr bot-author not-admin-author edited no-quote quote-too-short no-confirmation no-scope-item
#   excluded-incomplete expiry-missing expiry-too-long expired epic-closed envelope-missing
#   envelope-not-committed parse-ambiguous envelope-delegation-mismatch envelope-incomplete rollback-unnamed
#   non-delegable-command command-not-in-envelope.
#
# Every `gh` call is a GET (`gh api repos/...` or `gh repo view`), capped at 5 s, retried once after 2 s on a
# transport error only. There is NO test seam: nothing in the environment can make this answer `valid`.
# `set -uo pipefail`, deliberately NOT `-e`. Portable to bash 3.2 and mawk: no `timeout`-only, `date -d`,
# `stat -c`, `sed -i`, `readlink -f`, `${var,,}` or associative arrays. Lines ending `# mut:<name>` are the
# mutation points the suite edits to prove each check can fail.

set -uo pipefail
export LC_ALL=C

MARKER='<!-- soleur-delegation v1 -->'
WORK=""
AUDIT=0
cleanup() { [ -n "$WORK" ] && rm -rf "${WORK:?}"; return 0; }
trap cleanup EXIT

excluded_keywords() {
  printf '%s\n' 'user-data loss' 'money' 'legal-risk' 'brand' 'scope' 'force-push' \
    'bypassing required checks' 'editing this delegation' 'credential rotation' 'third-party'
}

emit() { printf 'delegation: %s reason=%s\n' "$1" "$2"; }
fail_invalid() { emit invalid "$1"; printf '%s\n' "$2" >&2; exit 1; }
fail_unv() { emit unverifiable "$1"; printf '%s\n' "$2" >&2; exit 2; }
die_render() { printf 'delegation-verify render: %s\n' "$1" >&2; exit 2; }

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

TO=()
if command -v timeout >/dev/null 2>&1; then TO=(timeout 5)
elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout 5); fi

# gh_get <outfile> <gh args...>: 0 ok; 4 a definitive HTTP 4xx answer; 5 transport or other failure (after one retry).
gh_get() {
  local out="$1" try=0; shift
  while :; do
    if ${TO[@]+"${TO[@]}"} gh "$@" >"$out" 2>"$WORK/gh.err"; then return 0; fi
    if grep -qE 'HTTP 4[0-9][0-9]' "$WORK/gh.err"; then return 4; fi
    try=$((try + 1))
    [ "$try" -ge 2 ] && return 5
    sleep 2
  done
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then printf '%s' "$1" | openssl dgst -sha256 | sed 's/^.* //'
  else return 1; fi
}
have_hash() { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; }

# valid_date <YYYY-MM-DD>: a real calendar date (round-trips through jq).
valid_date() {
  local d="$1" e
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  e="$(jq -rn --arg d "${d}T23:59:59Z" '$d | fromdateiso8601' 2>/dev/null)" || return 1
  [ "$(jq -rn --argjson e "$e" '$e | strftime("%Y-%m-%d")' 2>/dev/null)" = "$d" ]
}
add_days() { jq -rn --arg d "$1" --argjson n "$2" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%d")'; }

# parse_body <file>: sets P_MARKER_OK P_QUOTE P_CONF P_MISSING P_EXPDATE and writes $WORK/scope.nums.
parse_body() {
  local b="$1" kw
  P_MARKER_OK=0
  [ "$(head -1 "$b")" = "$MARKER" ] && P_MARKER_OK=1
  awk '
    /Operator instruction, verbatim/ { on = 1; next }
    on && /^ ? ? ?>/ { sub(/^ ? ? ?> ?/, ""); print; got = 1; next }
    on && got { exit }
  ' "$b" > "$WORK/quote.txt"
  # The two label prefixes are boilerplate, so they do not count toward the 40-character floor.
  P_QUOTE="$(trim "$(tr '\n' ' ' < "$WORK/quote.txt" | sed -e 's/Question shown://g' -e 's/Operator answer://g')")"
  P_CONF="$(trim "$(awk '
    c { if ($0 ~ /^[ \t]*$/) next; if ($0 !~ /^\*\*/) print; exit }
    /^\*\*Confirmation:\*\*/ { sub(/^\*\*Confirmation:\*\*[ \t]*/, ""); if ($0 != "") { print; exit } c = 1 }
  ' "$b")")"
  awk '
    /^\*\*Scope/ { on = 1; next }
    on && /^\*\*/ { exit }
    on && /^[0-9]+\.[ \t]+/ { n = $0; sub(/\..*$/, "", n); print n }
  ' "$b" > "$WORK/scope.nums"
  awk '/^\*\*Excluded/ { on = 1; print; next } on && /^\*\*/ { exit } on { print }' "$b" | tr 'A-Z' 'a-z' > "$WORK/excl.txt"
  P_MISSING=""
  while IFS= read -r kw; do
    grep -qF -- "$kw" "$WORK/excl.txt" || P_MISSING="$P_MISSING $kw"
  done < <(excluded_keywords)
  P_MISSING="$(trim "$P_MISSING")"
  P_EXPDATE="$(grep -m1 '^\*\*Expiry:\*\*' "$b" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
}

# render_body <epic> <date> <qfile> <afile> <scopefile> <expiry>: the delegation record on stdout.
render_body() {
  local epic="$1" date="$2" qf="$3" af="$4" sf="$5" expiry="$6" first=1 n=0 line ans
  printf '%s\n' "$MARKER"
  printf '## Standing delegation - epic #%s (recorded %s)\n\n' "$epic" "$date"
  printf '**Operator instruction, verbatim (%s):**\n' "$date"
  first=1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$first" = 1 ]; then printf '> Question shown: %s\n' "$line"; first=0
    elif [ -z "$line" ]; then printf '>\n'
    else printf '> %s\n' "$line"; fi
  done < "$qf"
  first=1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$first" = 1 ]; then printf '> Operator answer: %s\n' "$line"; first=0
    elif [ -z "$line" ]; then printf '>\n'
    else printf '> %s\n' "$line"; fi
  done < "$af"
  ans="$(tr '\r\n' '  ' < "$af")"; ans="$(trim "$ans")"
  printf '\n**Confirmation:** %s\n\n' "$ans"
  printf '**Scope (act classes the CTO agent may run without a further per-command prompt):**\n'
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim "${line%$'\r'}")"
    [ -n "$line" ] || continue
    n=$((n + 1)); printf '%s. %s\n' "$n" "$line"
  done < "$sf"
  printf '\n**Excluded (still operator-only):** user-data loss or sole-copy destruction, money, legal-risk, brand, scope changes, force-push to main, bypassing required checks or rulesets, editing this delegation, credential rotation that can lock users out, anything on third-party or tenant systems, and any act whose rollback is not named.\n\n'
  printf '**Expiry:** %s (or when the epic closes, whichever comes first). **Revoke:** delete or edit this comment.\n' "$expiry"
}

# is_denied <command>: the closed text backstop for the Excluded list.
is_denied() {
  local c="$1" p
  local pats=(
    '(^|[^[:alnum:]_-])git[[:space:]]+(.*[[:space:]])?push([[:space:]]|$)'
    '(^|[[:space:]])--admin([[:space:]=]|$)'
    'gh[[:space:]]+api[[:space:]].*(ruleset|protection)'
    'doppler[[:space:]]+secrets[[:space:]]+(set|delete)'
    '(^|[^[:alnum:]_-])(terraform|tofu)[[:space:]].*(apply|destroy|import)'
    '(^|[^[:alnum:]_-])rm[[:space:]]+(-[a-zA-Z]*[rR]|--recursive)'
    'gh[[:space:]]+repo[[:space:]]+delete'
    '(^|[^[:alnum:]_-])gh[[:space:]]+secret([[:space:]]|$)'
  )
  for p in "${pats[@]}"; do
    printf '%s' "$c" | grep -Eiq -- "$p" && return 0
  done
  return 1
}

# cmd_in_block <command> <file>: the command equals, byte for byte, a FULL line of the file.
cmd_in_block() {
  DV_CMD="$1" awk 'BEGIN { c = ENVIRON["DV_CMD"] } ($0 "") == (c "") { f = 1 } END { exit !f }' "$2" # mut:cmd-awk
}

rollback_named() {
  local r
  r="$(lower "$(trim "$1")")"; r="${r%%[.!]}"
  case "$r" in ""|none|n/a|na|unknown|tbd|todo|-) return 1 ;; esac
  return 0
}

need_tools() {
  command -v jq >/dev/null 2>&1 || fail_unv tool-missing "I cannot check the standing approval because jq is not installed."
  command -v gh >/dev/null 2>&1 || fail_unv tool-missing "I cannot check the standing approval because the GitHub command line tool is not installed."
}

do_verify() {
  local DELEG="" ENV="" CMDS=() VER=() i c url_re sec n cnt login owner_l login_l grc irc
  local CREATED UPDATED ISSUE_URL STATE EXP_EPOCH LIMIT NOW CUR_REPO
  while [ $# -gt 0 ]; do
    case "$1" in
      --delegation) [ $# -ge 2 ] || fail_unv usage "--delegation needs a value"; DELEG="$2"; shift 2 ;;
      --envelope)   [ $# -ge 2 ] || fail_unv usage "--envelope needs a value"; ENV="$2"; shift 2 ;;
      --command)    [ $# -ge 2 ] || fail_unv usage "--command needs a value"; CMDS[${#CMDS[@]}]="$2"; shift 2 ;;
      --audit)      AUDIT=1; shift ;;
      *) fail_unv usage "unknown argument: $1" ;;
    esac
  done
  [ -n "$DELEG" ] || fail_unv usage "verify needs --delegation <comment-url>"
  if [ "${#CMDS[@]}" -gt 0 ] && [ -z "$ENV" ]; then fail_unv usage "--command needs --envelope"; fi
  need_tools
  if [ "${#CMDS[@]}" -gt 0 ] && ! have_hash; then fail_unv tool-missing "I cannot check the command because no hashing tool is installed."; fi
  if [ -n "$ENV" ]; then command -v git >/dev/null 2>&1 || fail_unv tool-missing "I cannot check the envelope because git is not installed."; fi

  url_re='^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)#issuecomment-([0-9]+)$'
  [[ "$DELEG" =~ $url_re ]] || fail_invalid bad-url "The standing approval link is not a GitHub comment link on an issue."
  local U_OWNER="${BASH_REMATCH[1]}" U_REPO="${BASH_REMATCH[2]}" U_ISSUE="${BASH_REMATCH[4]}" U_CID="${BASH_REMATCH[5]}"

  gh_get "$WORK/repo.txt" repo view --json nameWithOwner --jq .nameWithOwner || fail_unv api-error "I could not look up which repository this is, so I cannot check the standing approval."
  CUR_REPO="$(tr -d '\r\n' < "$WORK/repo.txt")"
  [ "$(lower "$U_OWNER/$U_REPO")" = "$(lower "$CUR_REPO")" ] || fail_invalid wrong-repo "The standing approval link points at a different repository." # mut:wrong-repo

  gh_get "$WORK/c.json" api "repos/$U_OWNER/$U_REPO/issues/comments/$U_CID"; grc=$?
  case "$grc" in 0) ;; 4) fail_unv comment-unreadable "The standing approval comment cannot be read; it may have been deleted." ;; *) fail_unv api-error "I could not reach GitHub to read the standing approval." ;; esac
  jq -e '(.body|type=="string") and (.created_at|type=="string") and (.updated_at|type=="string") and (.user.login|type=="string") and (.user.type|type=="string") and (.issue_url|type=="string")' "$WORK/c.json" >/dev/null 2>&1 || fail_unv api-error "GitHub returned an answer I could not read, so I cannot check the standing approval."
  jq -r '.body' "$WORK/c.json" | awk '{ sub(/\r$/, ""); print }' > "$WORK/body.txt"
  CREATED="$(jq -r '.created_at' "$WORK/c.json")"; UPDATED="$(jq -r '.updated_at' "$WORK/c.json")"
  ISSUE_URL="$(jq -r '.issue_url' "$WORK/c.json")"; login="$(jq -r '.user.login' "$WORK/c.json")"
  parse_body "$WORK/body.txt"
  [ "$P_MARKER_OK" = 1 ] || fail_invalid no-marker "The comment does not start with the standing approval marker." # mut:marker

  [ "${ISSUE_URL##*/}" = "$U_ISSUE" ] || fail_invalid wrong-issue "The comment belongs to a different piece of work than the link says." # mut:issue-bind
  gh_get "$WORK/issue.json" api "repos/$U_OWNER/$U_REPO/issues/$U_ISSUE"; irc=$?
  case "$irc" in 0) ;; *) fail_unv api-error "I could not read the epic from GitHub, so I cannot check the standing approval." ;; esac # mut:api-error
  [ -z "$(jq -r '.pull_request // empty' "$WORK/issue.json" 2>/dev/null)" ] || fail_invalid epic-is-pr "The standing approval sits on a change proposal, not on the epic." # mut:epic-pr
  STATE="$(jq -r '.state // empty' "$WORK/issue.json" 2>/dev/null)"

  [ "$(jq -r '.user.type' "$WORK/c.json")" = "User" ] || fail_invalid bot-author "The standing approval was not written by a person." # mut:bot
  [[ "$login" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || fail_unv api-error "The author name on the standing approval looks wrong, so I cannot check it."
  owner_l="$(lower "$U_OWNER")"; login_l="$(lower "$login")"
  if [ "$login_l" != "$owner_l" ]; then
    gh_get "$WORK/perm.json" api "repos/$U_OWNER/$U_REPO/collaborators/$login/permission" || fail_unv api-error "I could not check who wrote the standing approval."
    [ "$(jq -r '.permission // empty' "$WORK/perm.json" 2>/dev/null)" = "admin" ] || fail_invalid not-admin-author "The standing approval was not written by an administrator of the repository." # mut:admin
  fi
  [ "$UPDATED" = "$CREATED" ] || fail_invalid edited "The standing approval was changed after it was recorded, so it needs to be recorded again." # mut:edited

  [ -s "$WORK/quote.txt" ] || fail_invalid no-quote "The standing approval does not quote the operator's own words."
  [ "${#P_QUOTE}" -ge 40 ] || fail_invalid quote-too-short "The quoted words in the standing approval are too short to show what was agreed." # mut:quote-len
  [ -n "$P_CONF" ] || fail_invalid no-confirmation "The standing approval does not record the operator's answer." # mut:confirmation
  [ -s "$WORK/scope.nums" ] || fail_invalid no-scope-item "The standing approval lists no numbered acts." # mut:scope
  [ -z "$P_MISSING" ] || fail_invalid excluded-incomplete "The standing approval does not list everything that stays with the operator (missing: $P_MISSING)." # mut:excluded
  valid_date "$P_EXPDATE" || fail_invalid expiry-missing "The standing approval has no valid expiry date." # mut:expiry-missing
  LIMIT="$(add_days "${CREATED%%T*}" 30)"
  [[ ! "$P_EXPDATE" > "$LIMIT" ]] || fail_invalid expiry-too-long "The standing approval runs for more than 30 days." # mut:expiry-cap
  EXP_EPOCH="$(jq -rn --arg d "${P_EXPDATE}T23:59:59Z" '$d | fromdateiso8601')"
  NOW="$(date -u +%s)"
  (( AUDIT )) || [ "$NOW" -le "$EXP_EPOCH" ] || fail_invalid expired "The standing approval has run out." # mut:expired
  (( AUDIT )) || [ "$STATE" = "open" ] || fail_invalid epic-closed "The epic is finished, so the standing approval has ended." # mut:epic-open

  if [ -n "$ENV" ]; then
    local EPATH="${ENV%%#*}" ANCHOR="" edir ebase
    case "$ENV" in *'#'*) ANCHOR="${ENV#*#}" ;; esac
    [ -f "$EPATH" ] || fail_invalid envelope-missing "The envelope file does not exist."
    edir="$(dirname "$EPATH")"; ebase="$(basename "$EPATH")"
    git -C "$edir" ls-files --error-unmatch -- "$ebase" >/dev/null 2>&1 && git -C "$edir" diff --quiet HEAD -- "$ebase" >/dev/null 2>&1 || fail_invalid envelope-not-committed "The envelope file is not saved in the project history exactly as written." # mut:committed
    awk -v dir="$WORK" '
      { t = $0; sub(/\r$/, "", t)
        if (t ~ /^ ? ? ?```/ || t ~ /^ ? ? ?~~~/) { ch = substr(t, match(t, /[`~]/), 1); if (fch == "") fch = ch; else if (ch == fch) fch = "" }
        if (fch == "" && t ~ /^## /) {
          if (cur != "") close(cur)
          cur = ""
          if (t ~ /^## Production Envelope/) { n++; cur = dir "/sec." n; print t > (dir "/sec.heads") }
        }
        if (cur != "") print $0 > cur
      }
      END { print n + 0 > (dir "/sec.count") }
    ' "$EPATH"
    cnt="$(cat "$WORK/sec.count" 2>/dev/null || echo 0)"; sec=""; n=0
    if [ -z "$ANCHOR" ]; then
      [ "$cnt" -le 1 ] || fail_invalid parse-ambiguous "The envelope file holds several envelopes; name which one to use."
      [ "$cnt" -eq 1 ] && sec="$WORK/sec.1"
    else
      i=1
      while [ "$i" -le "$cnt" ]; do
        if sed -n "${i}p" "$WORK/sec.heads" | grep -qiF -- "$ANCHOR"; then n=$((n + 1)); sec="$WORK/sec.$i"; fi
        i=$((i + 1))
      done
      [ "$n" -le 1 ] || fail_invalid parse-ambiguous "More than one envelope matches that title."
    fi
    [ -n "$sec" ] && [ -s "$sec" ] || fail_invalid envelope-missing "The envelope file has no matching Production Envelope section."
    : > "$WORK/cmds"
    awk -v cmdfile="$WORK/cmds" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      NR == 1 { next }
      { raw = $0; t = raw; sub(/\r$/, "", t)
        if (t ~ /^ ? ? ?```/ || t ~ /^ ? ? ?~~~/) {
          if (!infence) { infence = 1; if (cur == "command" && !cmddone) cmdopen = 1 }
          else { infence = 0; if (cmdopen) { cmdopen = 0; cmddone = 1 } }
          next
        }
        if (infence) {
          if (cmdopen) { if (t !~ /^[ \t]*$/) { print raw > cmdfile; ncmd++ } next }
          if (cur != "" && t !~ /^[ \t]*$/) val[cur] = val[cur] " " trim(t)
          next
        }
        d = t; sub(/^[ \t]*(-[ \t]+)?/, "", d); gsub(/\*\*/, "", d)
        if (match(d, /^(Delegation|Scope item|Command|Blast radius|Preconditions|Verification|Abort|Rollback|Stop conditions):/)) {
          key = tolower(substr(d, 1, RLENGTH - 1)); rest = trim(substr(d, RLENGTH + 1)); cur = key; seen[key] = 1
          if (rest != "") val[key] = val[key] " " rest
          next
        }
        if (cur == "preconditions" && d ~ /^Gate:[ \t]*[^ \t]/) { gates++; val[cur] = val[cur] " " trim(d); next }
        if (cur != "" && t !~ /^[ \t]*$/) val[cur] = val[cur] " " trim(d)
      }
      END { for (k in seen) { v = trim(val[k]); gsub(/\t/, " ", v); print "part\t" k "\t" v } print "gates\t" gates + 0; print "cmds\t" ncmd + 0 }
    ' "$sec" > "$WORK/parts"
    part_val() { awk -F'\t' -v k="$1" '$1 == "part" && $2 == k { print $3; exit }' "$WORK/parts"; }
    [ "$(trim "$(part_val delegation)")" = "$DELEG" ] || fail_invalid envelope-delegation-mismatch "The envelope names a different standing approval than the one being checked." # mut:env-delegation
    local SI; SI="$(trim "$(part_val 'scope item')")"
    [[ "$SI" =~ ^[0-9]+$ ]] || fail_invalid envelope-incomplete "The envelope does not name which numbered act it falls under."
    for c in 'blast radius' preconditions verification abort rollback 'stop conditions'; do
      [ -n "$(trim "$(part_val "$c")")" ] || fail_invalid envelope-incomplete "The envelope is missing its '$c' part."
    done
    [ "$(awk -F'\t' '$1 == "gates" { print $2 }' "$WORK/parts")" -ge 1 ] || fail_invalid envelope-incomplete "The envelope lists no preconditions that can be checked."
    [ "$(awk -F'\t' '$1 == "cmds" { print $2 }' "$WORK/parts")" -ge 1 ] || fail_invalid envelope-incomplete "The envelope has no command block."
    grep -qx "$SI" "$WORK/scope.nums" || fail_invalid no-scope-item "The standing approval has no numbered act $SI, which the envelope relies on."
    rollback_named "$(part_val rollback)" || fail_invalid rollback-unnamed "The envelope does not name a way to undo the act." # mut:rollback

    for c in ${CMDS[@]+"${CMDS[@]}"}; do
      case "$c" in *$'\n'*) fail_invalid command-not-in-envelope "The command to run spans several lines." ;; esac
      is_denied "$c" && fail_invalid non-delegable-command "That command is on the list of things that are never delegated." # mut:denylist
      cmd_in_block "$c" "$WORK/cmds" || fail_invalid command-not-in-envelope "That command is not, word for word, a line of the envelope." # mut:cmd-match
      VER[${#VER[@]}]="$c"
    done
  fi

  emit valid ok
  for c in ${VER[@]+"${VER[@]}"}; do
    printf 'verified-command: %s\n' "$c"
    printf 'verified-sha256: %s\n' "$(sha256_of "$c")"
  done
  exit 0
}

# do_render: build the record, then prove it parses (fail closed: a record that would not verify is never printed).
do_render() {
  local EPIC="" QF="" AF="" SF="" EXPIRY="" today limit
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) EPIC="${2:-}"; shift 2 ;;
      --question-file) QF="${2:-}"; shift 2 ;;
      --answer-file) AF="${2:-}"; shift 2 ;;
      --scope-file) SF="${2:-}"; shift 2 ;;
      --expiry) EXPIRY="${2:-}"; shift 2 ;;
      *) die_render "unknown argument: $1" ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || die_render "jq is not installed"
  [[ "$EPIC" =~ ^[0-9]+$ ]] || die_render "--epic needs an issue number"
  for f in "$QF" "$AF" "$SF"; do [ -n "$f" ] && [ -s "$f" ] && grep -q '[^[:space:]]' "$f" || die_render "the question, answer and scope files must exist and not be empty"; done
  valid_date "$EXPIRY" || die_render "--expiry needs a real date (YYYY-MM-DD)"
  today="$(date -u +%Y-%m-%d)"; limit="$(add_days "$today" 30)"
  [[ ! "$EXPIRY" > "$limit" ]] || die_render "the expiry is more than 30 days away"
  [[ ! "$EXPIRY" < "$today" ]] || die_render "the expiry is in the past"
  render_body "$EPIC" "$today" "$QF" "$AF" "$SF" "$EXPIRY" > "$WORK/rendered.md"
  parse_body "$WORK/rendered.md"
  [ "$P_MARKER_OK" = 1 ] && [ "${#P_QUOTE}" -ge 40 ] && [ -n "$P_CONF" ] && [ -s "$WORK/scope.nums" ] && [ -z "$P_MISSING" ] && valid_date "$P_EXPDATE" \
    || die_render "the record would not verify (the quoted question and answer must total at least 40 characters)"
  cat "$WORK/rendered.md"
  exit 0
}

self_check() {
  local sample why=""
  command -v jq >/dev/null 2>&1 || { echo "delegation-verify: not ready - jq is not installed"; exit 2; }
  printf 'Is it OK to carry the sample rollout through by myself?\n' > "$WORK/sq"; printf 'Yes, go ahead.\n' > "$WORK/sa"; printf 'Merge the sample change\n' > "$WORK/ss"
  sample="$WORK/sample.md"
  render_body 1 2026-01-01 "$WORK/sq" "$WORK/sa" "$WORK/ss" 2026-01-15 > "$sample"
  parse_body "$sample"
  [ "$P_MARKER_OK" = 1 ] || why="marker"
  [ "${#P_QUOTE}" -ge 40 ] || why="$why quote"
  [ -n "$P_CONF" ] || why="$why confirmation"
  [ -s "$WORK/scope.nums" ] || why="$why scope"
  [ -z "$P_MISSING" ] || why="$why excluded"
  valid_date "$P_EXPDATE" || why="$why expiry"
  if [ -n "$why" ]; then echo "delegation-verify: not ready - sample did not parse:$why"; exit 2; fi
  echo "delegation-verify: ready"
  exit 0
}

WORK="$(mktemp -d -t dv.XXXXXXXX)" || { echo "delegation: unverifiable reason=tool-missing"; exit 2; }
sub="${1:-}"
[ "$sub" = verify ] || [ "$sub" = render ] || [ "$sub" = keywords ] || [ "$sub" = "--self-check" ] || fail_unv usage "usage: delegation-verify.sh verify|render|keywords|--self-check ..." # mut:dispatch
[ $# -gt 0 ] && shift
case "$sub" in
  verify) do_verify "$@" ;;
  render) do_render "$@" ;;
  keywords) excluded_keywords; exit 0 ;;
  --self-check) self_check ;;
esac
