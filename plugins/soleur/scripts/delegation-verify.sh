#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2018,SC2019  # A && B || C is the check idiom (C is a fail_* that exits); tr A-Z is the portable ASCII lowering
# The shared validity chokepoint for a Standing Delegation and its Production Envelope.
# Format source (the only one): plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md
#
# Property: the verifier reports `valid` only when a marker-first, unedited, unexpired, admin-authored,
# person-authored (not an App) comment on THIS repository's still-open epic carries a verbatim quote, a
# Confirmation that starts with Yes, the cited Scope item and the fixed Excluded sentence, and (when asked) a
# complete envelope READ FROM HEAD (never the working tree) for that same epic, whose every Command line is on
# a closed grammar (merge, ready, workflow dispatch, create-change), is covered by the cited Scope item's own
# words, and contains each asked command as a byte-identical FULL line. Anything it cannot evaluate is exit 2.
#
# Callers: technical-ruling-gate.sh, hold-gate-eval.sh and the CTO's pre-execution check. A caller that
# re-implements any conjunct here is the defect. Exit 2 always blocks its caller and is never retried into a pass.
#
# Usage:
#   delegation-verify.sh verify --delegation <comment-url> [--envelope <path[#title]>] [--command <line>]...
#                               [--audit --at <YYYY-MM-DDTHH:MM:SSZ>]
#   delegation-verify.sh render --epic <N> --question-file <f> --answer-file <f> --scope-file <f> --expiry <YYYY-MM-DD>
#
# stdout (verify): `delegation: valid|invalid|unverifiable reason=<token>`; on `valid` always, next,
#   `verified-created-at: <ISO time the delegation comment was created>` and `verified-expiry: <YYYY-MM-DD>` (the
#   window a receipt is bound to); with an envelope and `valid` also
#   `verified-envelope-sha256: <hex>` (the sha256 of the HEAD blob that was read), and with --command per command
#   `verified-command: <the exact envelope line>` and `verified-sha256: <hex>`, so the caller runs the line byte for
#   byte. stderr: one plain sentence. Exit 0 valid, 1 invalid, 2 unverifiable or usage.
# --audit (ship-time gate, for an act that already ran) REQUIRES --at <time the act ran>: it then enforces
#   created_at <= at <= the end of the expiry day, and skips exactly one check, `epic-closed`: a delegated act that
#   ran legitimately must not fail its own audit row after the epic closes. Plain verify enforces expiry and
#   epic-open against now.
#
# Reason tokens: bad-url wrong-repo comment-unreadable api-error tool-missing usage no-marker wrong-issue
#   epic-is-pr bot-author not-admin-author edited no-quote quote-too-short no-confirmation no-scope-item
#   excluded-incomplete expiry-missing expiry-too-long expired before-delegation epic-closed envelope-missing
#   envelope-not-committed envelope-outside-repo envelope-not-regular-file parse-ambiguous
#   envelope-delegation-mismatch envelope-incomplete epic-mismatch rollback-unnamed non-delegable-command
#   command-not-delegable scope-mismatch command-not-in-envelope.
#
# Every `gh` call is a GET (`gh api repos/...` or `gh repo view`), reads no stdin, is capped at 5 s and is retried
# once after 2 s on a transport error only; with neither `timeout` nor `gtimeout` the verifier answers tool-missing
# rather than run unbounded. There is no seam INSIDE this script: nothing in its arguments can make it answer
# `valid`. (The caller's PATH and gh credentials are, as for any script, the caller's to protect.)
# `set -uo pipefail`, deliberately NOT `-e`. Portable to bash 3.2 and mawk: no `mapfile`, `date -d`, `stat -c`,
# `sed -i`, `readlink -f`, `${var,,}` or associative arrays. Lines ending `# mut:<name>` are the mutation points
# the suite edits to prove each check can fail.

set -uo pipefail
export LC_ALL=C

MARKER='<!-- soleur-delegation v1 -->'
# The only Excluded paragraph a record may carry (compared after whitespace normalisation). Section 5 of the
# format reference holds the same text; the suite instantiates the reference's templates and requires `valid`.
EXCLUDED='**Excluded (still operator-only):** user-data loss or sole-copy destruction, money, legal-risk, brand, scope changes, force-push to main, bypassing required checks or rulesets, editing this delegation, credential rotation that can lock users out, anything on third-party or tenant systems, and any act whose rollback is not named.'
# Credential shapes `render` refuses to publish (the answer is posted verbatim on a public issue).
SECRET_RE='(gh[pousr]_[A-Za-z0-9._~+/=-]{20,})|(github_pat_[A-Za-z0-9._~+/=-]{20,})|(sk-[A-Za-z0-9_-]{20,})|(AKIA[0-9A-Z]{16})|(xox[baprsce]-[A-Za-z0-9-]{10,})|(dp\.[a-z]{1,4}\.[A-Za-z0-9]{20,})|(sbp_[A-Za-z0-9]{20,})|(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)|(-----BEGIN [A-Z ]*PRIVATE KEY-----)'
ANSWER_CAP=600
WORK=""
AUDIT=0
cleanup() { [ -n "$WORK" ] && rm -rf "${WORK:?}"; return 0; }
trap cleanup EXIT

emit() { printf 'delegation: %s reason=%s\n' "$1" "$2"; }
fail_invalid() { emit invalid "$1"; printf '%s\n' "$2" >&2; exit 1; }
fail_unv() { emit unverifiable "$1"; printf '%s\n' "$2" >&2; exit 2; }
die_render() { printf 'delegation-verify render: %s\n' "$1" >&2; exit 2; }

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
squash() { printf '%s' "$1" | tr -s '[:space:]' ' '; }

TO=()
if command -v timeout >/dev/null 2>&1; then TO=(timeout 5)
elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout 5); fi

# gh_get <outfile> <gh args...>: 0 ok; 4 a definitive HTTP 4xx answer; 5 transport or other failure (after one retry).
gh_get() {
  local out="$1" try=0; shift
  while :; do
    if ${TO[@]+"${TO[@]}"} gh "$@" >"$out" 2>"$WORK/gh.err" </dev/null; then return 0; fi
    if grep -qE 'HTTP 4[0-9][0-9]' "$WORK/gh.err"; then return 4; fi
    try=$((try + 1))
    [ "$try" -ge 2 ] && return 5
    sleep 2
  done
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 < "$1" | sed 's/^.* //'
  else return 1; fi
}
sha256_of() { printf '%s' "$1" > "$WORK/sha.in"; sha256_file "$WORK/sha.in"; }
have_hash() { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; }

# valid_date <YYYY-MM-DD>: a real calendar date (round-trips through jq).
valid_date() {
  local d="$1" e
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  e="$(jq -rn --arg d "${d}T23:59:59Z" '$d | fromdateiso8601' 2>/dev/null)" || return 1
  [ "$(jq -rn --argjson e "$e" '$e | strftime("%Y-%m-%d")' 2>/dev/null)" = "$d" ]
}
add_days() { jq -rn --arg d "$1" --argjson n "$2" '($d + "T00:00:00Z" | fromdateiso8601) + ($n * 86400) | strftime("%Y-%m-%d")'; }
# valid_instant <YYYY-MM-DDTHH:MM:SSZ>: a real UTC time (round-trips through jq).
valid_instant() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  [ "$(jq -rn --arg d "$1" '$d | fromdateiso8601 | todateiso8601' 2>/dev/null)" = "$1" ]
}
epoch_of() { jq -rn --arg d "$1" '$d | fromdateiso8601' 2>/dev/null; }

# fence helper shared by both envelope awk programs: a CommonMark fence is a run of >= 3 backticks or tildes
# (up to 3 spaces of indent); it closes only on the SAME character, a run at least as long, and no info string.
FENCE_AWK='
  function fnc(t,   s, ch, n) {
    s = t; sub(/^ ? ? ?/, "", s); ch = substr(s, 1, 1)
    if (ch != "`" && ch != "~") return 0
    n = 0; while (substr(s, n + 1, 1) == ch) n++
    if (n < 3) return 0
    FCH = ch; FLEN = n; FREST = substr(s, n + 1)
    if (ch == "`" && index(FREST, "`") > 0) return 0
    return 1
  }
'

# strip_html <file> <keep first line 1|0>: the file without <!-- ... --> comments (also across lines), so a scope item
# or an envelope section that a reader of the rendered text cannot see is not parsed either. Code fences and inline code
# spans are shown literally by a renderer, so they are left alone; <!--> and <!---> are one-line empty comments. A comment
# that is never closed hides the rest of the file, so it is flagged in $WORK/html.unterminated. The delegation marker is
# line 1 of the record and is kept verbatim.
strip_html() {
  awk -v keep="$2" -v flag="$WORK/html.unterminated" "$FENCE_AWK"'
    NR == 1 && keep == 1 { print; next }
    { t = $0; sub(/\r$/, "", t)
      if (!inc && fnc(t)) {
        if (!infence) { infence = 1; fch = FCH; flen = FLEN; print; next }
        if (FCH == fch && FLEN >= flen && FREST ~ /^[ \t]*$/) { infence = 0; print; next }
      }
      if (infence && !inc) { print; next }
      s = $0; out = ""; code = 0; n = length(s); i = 1
      while (i <= n) {
        c = substr(s, i, 1)
        if (inc) { if (substr(s, i, 3) == "-->") { inc = 0; i += 3 } else i++; continue }
        if (c == "`") { code = !code; out = out c; i++; continue }
        if (!code && substr(s, i, 4) == "<!--") {
          if (substr(s, i, 5) == "<!-->") { i += 5; continue }
          if (substr(s, i, 6) == "<!--->") { i += 6; continue }
          inc = 1; i += 4; continue
        }
        out = out c; i++
      }
      print out }
    END { if (inc) print "1" > flag }
  ' "$1"
}

# parse_body <file>: sets P_MARKER_OK P_QUOTE P_CONF P_EXCL_OK P_EXPDATE and writes $WORK/scope.items / scope.nums.
parse_body() {
  local b="$1" ex
  P_MARKER_OK=0
  [ "$(head -1 "$b")" = "$MARKER" ] && P_MARKER_OK=1
  strip_html "$b" 1 > "$WORK/pb.txt"; b="$WORK/pb.txt" # mut:strip-body
  awk '
    /Operator instruction, verbatim/ { on = 1; next }
    on && /^ ? ? ?>/ { sub(/^ ? ? ?> ?/, ""); print; got = 1; next }
    on && got { exit }
  ' "$b" > "$WORK/quote.txt"
  # The two label prefixes are boilerplate, so they do not count toward the 40-byte floor.
  P_QUOTE="$(trim "$(tr '\n' ' ' < "$WORK/quote.txt" | sed -e 's/Question shown://g' -e 's/Operator answer://g')")"
  P_CONF="$(trim "$(awk '
    c { if ($0 ~ /^[ \t]*$/) next; if ($0 !~ /^\*\*/) print; exit }
    /^\*\*Confirmation:\*\*/ { sub(/^\*\*Confirmation:\*\*[ \t]*/, ""); if ($0 != "") { print; exit } c = 1 }
  ' "$b")")"
  awk '
    /^\*\*Scope/ { on = 1; next }
    on && /^\*\*/ { exit }
    on && /^[0-9]+\.[ \t]+/ { if (n != "") print n "\t" txt; n = $0; sub(/\..*$/, "", n); txt = $0; sub(/^[0-9]+\.[ \t]+/, "", txt); next }
    on && /^[ \t]*$/ { if (n != "") print n "\t" txt; n = ""; next }
    on && n != "" { t = $0; sub(/^[ \t]+/, "", t); txt = txt " " t }
    END { if (n != "") print n "\t" txt }
  ' "$b" > "$WORK/scope.items"
  cut -f1 "$WORK/scope.items" > "$WORK/scope.nums"
  # The Excluded paragraph is a fixed sentence: one paragraph, equal to it after whitespace normalisation.
  ex="$(awk '/^\*\*Excluded/ { on = 1; print; next } on && /^\*\*/ { exit } on { print }' "$b")"
  P_EXCL_OK=0
  [ "$(trim "$(squash "$ex")")" = "$(trim "$(squash "$EXCLUDED")")" ] && [ "$(grep -c '^\*\*Excluded' "$b")" = 1 ] && P_EXCL_OK=1
  P_EXPDATE="$(grep -m1 '^\*\*Expiry:\*\*' "$b" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
  P_ONE_CONF=0; [ "$(grep -c '^\*\*Confirmation:\*\*' "$b")" = 1 ] && P_ONE_CONF=1
  P_ONE_EXP=0; [ "$(grep -c '^\*\*Expiry:\*\*' "$b")" = 1 ] && P_ONE_EXP=1
}

# says_yes <text>: the Confirmation starts with the word Yes.
says_yes() { [[ "$1" =~ ^Yes([^[:alnum:]]|$) ]]; }

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
  printf '\n%s\n\n' "$EXCLUDED"
  printf '**Expiry:** %s (or when the epic closes, whichever comes first). **Revoke:** delete or edit this comment.\n' "$expiry"
}

# The tools whose mere use is never delegated, and where a word counts as a COMMAND: at the start of a line or after
# ; & | ( or a backtick, optionally behind wrapper words (env, timeout 5, nohup, xargs, sudo ...) and their flags or
# assignments. So `timeout 5 kubectl ...` and `xargs ssh ...` are refused while `-f cloud=aws` and `--head docker`, where
# the same letters are a value, are not.
DENY_TOOLS='kubectl|supabase|psql|hcloud|ssh|scp|helm|docker|aws|gcloud|flyctl'
OPS_TOOLS="$DENY_TOOLS|curl|wget|terraform|tofu|doppler|rm|dd|mkfs[.a-z0-9]*|nc|ncat|socat"
CMDPOS_RE='(^|[;&|(`]|\$\()[[:space:]]*((env|timeout|nohup|xargs|sudo|nice|command|exec|time|setsid|stdbuf|doas)[[:space:]]+(-[^[:space:]]+[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|[0-9]+[smhd]?[[:space:]]+)*)*'
cmd_word() { # <text> <alternation of words>: 0 when the text runs one of them as a command
  printf '%s\n' "$1" | grep -Eiq -- "${CMDPOS_RE}($2)([[:space:]]|\$)"
}

# is_denied <command>: the text backstop for the Excluded list, a SECOND layer behind the allowlist. It runs on the
# command as written and on a copy with quotes, backslashes and expansion characters removed, so g''it push and
# --admi""n are read as the shell would read them.
is_denied() {
  local c="$1" n p
  n="$(printf '%s' "$c" | tr -d "'\"\\\\\`\$")"
  local pats=(
    '(^|[^[:alnum:]_-])git[^[:alnum:]]*[[:space:]]+(.*[[:space:]])?push([[:space:]"'"'"';&|)]|$)'
    '(^|[^[:alnum:]_-])git[[:space:]]+(.*[[:space:]])?(reset[[:space:]]+(.*[[:space:]])?--hard|branch[[:space:]]+(.*[[:space:]])?-D|tag[[:space:]]+(.*[[:space:]])?-d|clean|filter-branch|update-ref)([[:space:]]|$)'
    '(^|[[:space:]])--admin([[:space:]=;&|)]|$)'
    'gh[[:space:]]+api[[:space:]].*(ruleset|protection)'
    'gh[[:space:]]+api[[:space:]].*(-X|--method)[[:space:]=]*(DELETE|PATCH|PUT)'
    'doppler[[:space:]]+(.*[[:space:]])?secrets[[:space:]]+(set|delete|upload)'
    '(^|[^[:alnum:]_-])(terraform|tofu)[[:space:]].*(apply|destroy|import|state|taint|force-unlock)'
    '(^|[^[:alnum:]_-])rm[[:space:]]+(.*[[:space:]])?(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)'
    '(^|[^[:alnum:]_-])find[[:space:]].*-delete'
    'gh[[:space:]]+repo[[:space:]]+(delete|archive|rename|transfer|edit)'
    '(^|[^[:alnum:]_-])gh[[:space:]]+(secret|variable)([[:space:]]|$)'
    'gh[[:space:]]+[a-z-]+[[:space:]]+delete([[:space:]]|$)'
    "${CMDPOS_RE}(${DENY_TOOLS})([[:space:]]|\$)"
    '(^|[^[:alnum:]_-])(curl|wget)[[:space:]]+(.*[[:space:]])?(-X|--request)'
    '\|[[:space:]]*(sh|bash)([[:space:]]|$)'
  )
  for p in "${pats[@]}"; do
    printf '%s\n%s\n' "$c" "$n" | grep -Eiq -- "$p" && return 0
  done
  return 1
}

# The closed command grammar. N = [0-9]+; every character is in [A-Za-z0-9 ._=:/@+,-].
RE_MERGE='^gh pr merge ([0-9]+)( --squash| --merge| --rebase)?( --auto)?$'
RE_READY='^gh pr ready ([0-9]+)$'
RE_RUN='^gh workflow run ([A-Za-z0-9._-]+\.(yml|yaml))( -f [A-Za-z0-9_.-]+=[A-Za-z0-9._/:@+,-]+)*$'
RE_CREATE='^gh pr create --fill( --head [A-Za-z0-9._/-]+)?( --base [A-Za-z0-9._/-]+)?$'
classify_command() { # <line>: sets CMD_KIND CMD_TARGET; 1 when the line is not on the allowlist
  [[ "$1" =~ $RE_MERGE ]] && { CMD_KIND=merge; CMD_TARGET="${BASH_REMATCH[1]}"; return 0; }
  [[ "$1" =~ $RE_READY ]] && { CMD_KIND=ready; CMD_TARGET="${BASH_REMATCH[1]}"; return 0; }
  [[ "$1" =~ $RE_RUN ]] && { CMD_KIND=run; CMD_TARGET="${BASH_REMATCH[1]}"; return 0; }
  [[ "$1" =~ $RE_CREATE ]] && { CMD_KIND=create; CMD_TARGET=""; return 0; }
  return 1
}

# scope_covers <kind> <target> <scope item text>: an item with a negation or a condition (not, never, no, nor, except,
# excluding, without, unless, avoid, skip, prohibited, forbidden, any n't, only if, only after, nothing but) never covers
# anything, and an item must START with an act word (merge, ready, dispatch, run, create, revert, open). Otherwise the item
# names the act's target as a whole token. merge and ready: the PR number (as #N, PR N, or right after `pr merge` /
# `pr ready`) AND the word merge / ready. workflow run: the workflow file name. pr create: the word revert (a revert PR).
scope_covers() {
  SC_K="$1" SC_T="$2" SC_X="$3" awk '
    function isl(c) { return c ~ /^[a-z]$/ }
    function isd(c) { return c ~ /^[0-9]$/ }
    function istc(c) { return c ~ /^[A-Za-z0-9_-]$/ }
    function hasw(t, w,   s, i, p, a, b) {
      s = 1
      while ((i = index(substr(t, s), w)) > 0) {
        p = s + i - 1; a = (p > 1) ? substr(t, p - 1, 1) : " "; b = substr(t, p + length(w), 1); if (b == "") b = " "
        if (!isl(a) && !isl(b)) return 1
        s = p + 1
      }
      return 0
    }
    function hasneg(t,   w, k, k2, u) {
      u = t; gsub("\342\200\231", "\047", u); gsub(/[ \t]+/, " ", u)
      if (index(u, "n\047t") > 0) return 1
      if (index(" " u " ", " only if ") > 0 || index(" " u " ", " only after ") > 0 || index(" " u " ", " nothing but ") > 0) return 1
      k2 = split("not never no nor except excluding without unless avoid skip cannot prohibit prohibited prohibits forbid forbidden forbids refrain", w, " ")
      for (k = 1; k <= k2; k++) if (hasw(u, w[k])) return 1
      return 0
    }
    function startok(t,   s, w) {
      s = t; sub(/^[ \t*+-]*([0-9]+[.)])?[ \t*]*/, "", s); w = s; sub(/[^a-z].*$/, "", w)
      return w == "merge" || w == "ready" || w == "dispatch" || w == "run" || w == "create" || w == "revert" || w == "open"
    }
    function hasnum(t, n,   s, i, p, a, b, pre) {
      s = 1
      while ((i = index(substr(t, s), n)) > 0) {
        p = s + i - 1; a = (p > 1) ? substr(t, p - 1, 1) : " "; b = substr(t, p + length(n), 1); if (b == "") b = " "
        pre = substr(t, 1, p - 1)
        if (!isd(a) && !isd(b) && (pre ~ /#$/ || pre ~ /pr $/ || pre ~ /pr merge $/ || pre ~ /pr ready $/)) return 1
        s = p + 1
      }
      return 0
    }
    function hasfile(t, f,   s, i, p, a, b, c2) {
      s = 1
      while ((i = index(substr(t, s), f)) > 0) {
        p = s + i - 1; a = (p > 1) ? substr(t, p - 1, 1) : " "; b = substr(t, p + length(f), 1); c2 = substr(t, p + length(f) + 1, 1)
        if (!istc(a) && a != "." && (b == "" || (!istc(b) && !(b == "." && istc(c2)))) ) return 1
        s = p + 1
      }
      return 0
    }
    BEGIN {
      k = ENVIRON["SC_K"]; tg = ENVIRON["SC_T"]; x = ENVIRON["SC_X"]; t = tolower(x); ok = 0
      if (hasneg(t) || !startok(t)) exit 1
      if (k == "merge") ok = hasnum(t, tg) && hasw(t, "merge")
      else if (k == "ready") ok = hasnum(t, tg) && hasw(t, "ready")
      else if (k == "run") ok = hasfile(x, tg)
      else if (k == "create") ok = hasw(t, "revert")
      exit !ok
    }
  '
}

# check_command <line> <scope item text>: deny list, then the closed grammar, then scope binding. Exits via fail_invalid.
check_command() {
  local c="$1" st="$2"
  CMD_KIND=""; CMD_TARGET=""
  is_denied "$c" && fail_invalid non-delegable-command "That command is on the list of things that are never delegated." # mut:denylist
  # Defence in depth: no whitespace other than a space, and no character outside the grammar's alphabet, ever reaches the regexes.
  case "$c" in *[!A-Za-z0-9\ ._=:/@+,-]*) fail_invalid command-not-delegable "That command is not one of the few kinds of act a standing approval can cover." ;; esac
  classify_command "$c" || fail_invalid command-not-delegable "That command is not one of the few kinds of act a standing approval can cover." # mut:allowlist
  scope_covers "$CMD_KIND" "$CMD_TARGET" "$st" || fail_invalid scope-mismatch "That command is not what the numbered act in the standing approval says it covers." # mut:scope-bind
}

# ops_readonly <unit>: in a Verification, Abort or Stop text a gh or git command may only READ.
ops_readonly() {
  local u="$1" seg tool t1 t2 t3
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    tool="$(printf '%s' "$seg" | grep -oEi '(gh|git)[[:space:]]+[a-z-]+([[:space:]]+[a-z-]+)?$')"
    set -f; set -- $tool; set +f
    t1="$(lower "${1:-}")"; t2="$(lower "${2:-}")"; t3="$(lower "${3:-}")"
    case "$t1 $t2 $t3" in
      "gh run view"*|"gh run list"*|"gh pr view"*|"gh pr list"*|"gh pr checks"*|"gh pr diff"*|"gh pr status"*|"gh issue view"*|"gh issue list"*|"gh workflow view"*|"gh workflow list"*|"gh release view"*|"gh release list"*|"gh repo view"*) ;;
      "gh api"*) printf '%s\n' "$u" | grep -Eq -- '(^|[[:space:]])(-X|--method|-f|-F|--field|--raw-field|--input)' && fail_invalid non-delegable-command "A check, abort or stop text in the envelope would change something through the GitHub API, not just read." ;; # mut:ops-api
      "git log"*|"git show"*|"git status"*|"git diff"*|"git rev-parse"*|"git ls-tree"*|"git cat-file"*|"git merge-base"*|"git describe"*|"git blame"*) ;;
      *) fail_invalid non-delegable-command "A check, abort or stop text in the envelope runs a command that changes something, and only reading is allowed there." ;; # mut:ops-readonly
    esac
  done < <(printf '%s\n' "$u" | grep -oEi -- "${CMDPOS_RE}(gh|git)[[:space:]]+[a-z-]+([[:space:]]+[a-z-]+)?")
}

# ops_check <section> <F|L> <text> <scope item text>: the Verification, Abort, Rollback and Stop conditions text is run by
# the CTO, so each line of it (as a whole, as a fenced line, and as every backticked span) is tested: the denylist, then the
# tools that are never run (at command position, behind any wrapper), then, outside a Rollback, gh and git may only read.
# In a Rollback every fenced line and every backticked span must be a command on the grammar AND covered by the cited Scope
# item, and the rest of the line must be plain words: no shell characters and no instructions to fetch or run something.
ops_check() {
  local key="$1" kind="$2" txt="$3" st="$4" rest span bt='`' re unit units=()
  units[0]="$txt"; rest="$txt"; re="${bt}([^${bt}]*)${bt}"
  if [ "$kind" = L ]; then
    while [[ "$rest" =~ $re ]]; do
      span="${BASH_REMATCH[1]}"; units[${#units[@]}]="$span"
      rest="${rest/"$bt$span$bt"/ }"
    done
  fi
  for unit in "${units[@]}"; do
    is_denied "$unit" && fail_invalid non-delegable-command "A command in the envelope's checks, abort, rollback or stop text is on the list of things that are never delegated." # mut:ops-deny
    cmd_word "$unit" "$OPS_TOOLS" && fail_invalid non-delegable-command "The envelope's checks, abort, rollback or stop text runs a tool that is never delegated." # mut:ops-tools
    [ "$key" = rollback ] || ops_readonly "$unit"
  done
  [ "$key" = rollback ] || return 0
  if [ "$kind" = F ]; then
    classify_command "$txt" || fail_invalid command-not-delegable "A command in the envelope's rollback is not one of the few kinds of act a standing approval can cover." # mut:ops-rollback
    scope_covers "$CMD_KIND" "$CMD_TARGET" "$st" || fail_invalid scope-mismatch "A command in the envelope's rollback is not what the numbered act in the standing approval says it covers." # mut:ops-rscope
    return 0
  fi
  rest="$txt"
  while [[ "$rest" =~ $re ]]; do
    span="${BASH_REMATCH[1]}"
    classify_command "$span" || fail_invalid command-not-delegable "A command in the envelope's rollback is not one of the few kinds of act a standing approval can cover." # mut:ops-span
    scope_covers "$CMD_KIND" "$CMD_TARGET" "$st" || fail_invalid scope-mismatch "A command in the envelope's rollback is not what the numbered act in the standing approval says it covers." # mut:ops-sscope
    rest="${rest/"$bt$span$bt"/ }"
  done
  case "$rest" in *[\;\&\|\<\>\$\`\\\{\}\*]*) fail_invalid command-not-delegable "The envelope's rollback holds shell characters, so it is not plain words or an allowed command." ;; esac # mut:ops-meta
  printf '%s\n' "$rest" | grep -Eiq -- '(^|[^[:alnum:]_-])(wget|curl|bash|eval|nc|ncat|socat|python3?|perl|ruby|node|php)([^[:alnum:]_-]|$)|(^|[^[:alnum:]_-])sh[[:space:]]+-c|(run|execute|paste|download)[[:space:]]+(it|that|this|the[[:space:]]+script)|(^|[^[:alnum:]_-])gh[[:space:]]+(pr|workflow|issue|api|release|run|repo)' && fail_invalid non-delegable-command "The envelope's rollback tells the reader to fetch or run something, which is never delegated." # mut:ops-prose
}

# cmd_in_block <command> <file>: the command equals, byte for byte, a FULL line of the file.
cmd_in_block() {
  DV_CMD="$1" awk 'BEGIN { c = ENVIRON["DV_CMD"] } ($0 "") == (c "") { f = 1 } END { exit !f }' "$2" # mut:cmd-awk
}

# rollback_named <text>: a real way to undo the act, in at least three words, not a placeholder or an admission.
rollback_named() {
  local r
  r="$(lower "$(trim "$1")")"
  [ "$(printf '%s' "$r" | wc -w | tr -d ' ')" -ge 3 ] || return 1
  printf '%s' "$r" | grep -Eq "(^|[^a-z])(none|irreversible|cannot|unknown|tbd|todo|nothing|impossible|n/a)([^a-z]|\$)|can't|no[[:space:]]+rollback|not[[:space:]]+(reversible|possible|undoable)" && return 1
  return 0
}

need_tools() {
  command -v jq >/dev/null 2>&1 || fail_unv tool-missing "I cannot check the standing approval because a helper program (jq) is not installed."
  command -v gh >/dev/null 2>&1 || fail_unv tool-missing "I cannot check the standing approval because the GitHub command line tool is not installed."
  [ "${#TO[@]}" -gt 0 ] || fail_unv tool-missing "I cannot check the standing approval safely because this computer has no time-limit tool (timeout or gtimeout)." # mut:tool-timeout
}

# envelope_fetch <path>: copies the HEAD blob of <path> to $WORK/env.blob. Never reads the working tree.
envelope_fetch() {
  local p="$1" ls mode type sha rest
  while [[ "$p" == ./* ]]; do p="${p#./}"; done
  [ -n "$p" ] || fail_invalid envelope-missing "The envelope path is empty."
  [[ "$p" == /* ]] && fail_invalid envelope-outside-repo "The envelope must be a file inside this project, named relative to it." # mut:env-abs
  [[ "$p" =~ (^|/)\.\.(/|$) ]] && fail_invalid envelope-outside-repo "The envelope must be a file inside this project, named relative to it." # mut:env-dotdot
  case "$p" in
    *[*?[\\]*|*[[:cntrl:]]*|*/) fail_invalid envelope-missing "The envelope path has characters that are not allowed in a file name here." ;;
  esac
  git rev-parse --show-toplevel >/dev/null 2>&1 </dev/null || fail_invalid envelope-outside-repo "I am not inside a project, so there is no saved envelope to read."
  ls="$(GIT_LITERAL_PATHSPECS=1 git ls-tree HEAD -- "$p" 2>/dev/null </dev/null)" || ls=""
  [ -n "$ls" ] && [ "$(printf '%s\n' "$ls" | wc -l | tr -d ' ')" = 1 ] || fail_invalid envelope-not-committed "The envelope file is not saved in the project history." # mut:committed
  mode="${ls%% *}"; rest="${ls#* }"; type="${rest%% *}"; rest="${rest#* }"; sha="${rest%%[[:space:]]*}"
  { [ "$mode" = 100644 ] && [ "$type" = blob ]; } || fail_invalid envelope-not-regular-file "The envelope must be an ordinary saved file, not a shortcut or a folder." # mut:env-mode
  [[ "$sha" =~ ^[0-9a-f]{40,64}$ ]] || fail_invalid envelope-not-committed "I could not read the saved envelope."
  git cat-file blob "$sha" > "$WORK/env.blob" 2>/dev/null </dev/null || fail_invalid envelope-not-committed "I could not read the saved envelope." # mut:env-blob
}

do_verify() {
  local DELEG="" ENV="" AT="" CMDS=() VER=() i c url_re sec n cnt login owner_l login_l grc irc okey okind otxt
  local CREATED UPDATED ISSUE_URL STATE EXP_EPOCH LIMIT NOW CUR_REPO CHK_EPOCH CREATED_EPOCH AT_EPOCH
  while [ $# -gt 0 ]; do
    case "$1" in
      --delegation) [ $# -ge 2 ] || fail_unv usage "--delegation needs a value"; DELEG="$2"; shift 2 ;;
      --envelope)   [ $# -ge 2 ] || fail_unv usage "--envelope needs a value"; ENV="$2"; shift 2 ;;
      --command)    [ $# -ge 2 ] || fail_unv usage "--command needs a value"; CMDS[${#CMDS[@]}]="$2"; shift 2 ;;
      --at)         [ $# -ge 2 ] || fail_unv usage "--at needs a value"; AT="$2"; shift 2 ;;
      --audit)      AUDIT=1; shift ;;
      *) fail_unv usage "unknown argument: $1" ;;
    esac
  done
  [ -n "$DELEG" ] || fail_unv usage "verify needs --delegation <comment-url>"
  if [ "${#CMDS[@]}" -gt 0 ] && [ -z "$ENV" ]; then fail_unv usage "--command needs --envelope"; fi
  [ "$AUDIT" = 0 ] || [ -n "$AT" ] || fail_unv usage "--audit needs --at <the time the act ran, YYYY-MM-DDTHH:MM:SSZ>" # mut:audit-needs-at
  [ -z "$AT" ] || [ "$AUDIT" = 1 ] || fail_unv usage "--at is only valid together with --audit"
  need_tools
  if [ -n "$AT" ]; then valid_instant "$AT" || fail_unv usage "--at needs a real UTC time like 2026-01-31T12:00:00Z"; fi
  if [ -n "$ENV" ] && ! have_hash; then fail_unv tool-missing "I cannot check the envelope because no hashing tool is installed."; fi
  if [ -n "$ENV" ]; then command -v git >/dev/null 2>&1 || fail_unv tool-missing "I cannot check the envelope because git is not installed."; fi

  url_re='^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)#issuecomment-([0-9]+)$'
  [[ "$DELEG" =~ $url_re ]] || fail_invalid bad-url "The standing approval link is not a GitHub comment link on an issue."
  local U_OWNER="${BASH_REMATCH[1]}" U_REPO="${BASH_REMATCH[2]}" U_ISSUE="${BASH_REMATCH[4]}" U_CID="${BASH_REMATCH[5]}"

  gh_get "$WORK/repo.txt" repo view --json nameWithOwner --jq .nameWithOwner || fail_unv api-error "I could not look up which project this is, so I cannot check the standing approval."
  CUR_REPO="$(tr -d '\r\n' < "$WORK/repo.txt")"
  [ "$(lower "$U_OWNER/$U_REPO")" = "$(lower "$CUR_REPO")" ] || fail_invalid wrong-repo "The standing approval link points at a different project." # mut:wrong-repo

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
  jq -e '.performed_via_github_app == null' "$WORK/c.json" >/dev/null 2>&1 || fail_invalid bot-author "The standing approval was written through an app, not by a person." # mut:app
  [[ "$login" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || fail_unv api-error "The author name on the standing approval looks wrong, so I cannot check it."
  owner_l="$(lower "$U_OWNER")"; login_l="$(lower "$login")"
  if [ "$login_l" != "$owner_l" ]; then
    gh_get "$WORK/perm.json" api "repos/$U_OWNER/$U_REPO/collaborators/$login/permission" || fail_unv api-error "I could not check who wrote the standing approval."
    [ "$(jq -r '.permission // empty' "$WORK/perm.json" 2>/dev/null)" = "admin" ] || fail_invalid not-admin-author "The standing approval was not written by an administrator of the project." # mut:admin
  fi
  [ "$UPDATED" = "$CREATED" ] || fail_invalid edited "The standing approval was changed after it was recorded, so it needs to be recorded again." # mut:edited

  [ -s "$WORK/quote.txt" ] || fail_invalid no-quote "The standing approval does not quote the operator's own words."
  [ "${#P_QUOTE}" -ge 40 ] || fail_invalid quote-too-short "The quoted words in the standing approval are too short to show what was agreed." # mut:quote-len
  { [ "$P_ONE_CONF" = 1 ] && says_yes "$P_CONF"; } || fail_invalid no-confirmation "The standing approval does not record a clear Yes from the operator." # mut:confirmation
  [ -s "$WORK/scope.nums" ] || fail_invalid no-scope-item "The standing approval lists no numbered acts." # mut:scope
  ! grep -qE '<[!?]' "$WORK/scope.items" || fail_invalid no-scope-item "A numbered act in the standing approval holds hidden markup, so it cannot be relied on." # mut:scope-html
  [ "$P_EXCL_OK" = 1 ] || fail_invalid excluded-incomplete "The standing approval does not carry the exact list of what stays with the operator." # mut:excluded
  { [ "$P_ONE_EXP" = 1 ] && valid_date "$P_EXPDATE"; } || fail_invalid expiry-missing "The standing approval has no valid expiry date." # mut:expiry-missing
  LIMIT="$(add_days "${CREATED%%T*}" 30)"
  [[ ! "$P_EXPDATE" > "$LIMIT" ]] || fail_invalid expiry-too-long "The standing approval runs for more than 30 days." # mut:expiry-cap
  EXP_EPOCH="$(epoch_of "${P_EXPDATE}T23:59:59Z")"
  CREATED_EPOCH="$(epoch_of "$CREATED")"; NOW="$(date -u +%s)"; CHK_EPOCH="$NOW"
  if [ "$AUDIT" = 1 ]; then
    AT_EPOCH="$(epoch_of "$AT")"; CHK_EPOCH="$AT_EPOCH"
    [ "$AT_EPOCH" -ge "$CREATED_EPOCH" ] || fail_invalid before-delegation "The act is dated before the standing approval was recorded." # mut:audit-before
  fi
  [ "$CHK_EPOCH" -le "$EXP_EPOCH" ] || fail_invalid expired "The standing approval had run out." # mut:expired
  (( AUDIT )) || [ "$STATE" = "open" ] || fail_invalid epic-closed "The epic is finished, so the standing approval has ended." # mut:epic-open

  if [ -n "$ENV" ]; then
    local EPATH="${ENV%%#*}" ANCHOR="" EPIC_N
    case "$ENV" in *'#'*) ANCHOR="${ENV#*#}" ;; esac
    envelope_fetch "$EPATH"
    rm -f "$WORK/html.unterminated"
    strip_html "$WORK/env.blob" 0 > "$WORK/env.txt" # mut:strip-env
    [ ! -e "$WORK/html.unterminated" ] || fail_invalid envelope-incomplete "The envelope has a comment that is never closed, which hides the rest of the file." # mut:html-unterm
    awk -v dir="$WORK" "$FENCE_AWK"'
      { t = $0; sub(/\r$/, "", t)
        if (fnc(t)) {
          if (fch == "") { fch = FCH; flen = FLEN }
          else if (FCH == fch && FLEN >= flen && FREST ~ /^[ \t]*$/) fch = ""
        }
        if (fch == "" && t ~ /^## /) {
          if (cur != "") close(cur)
          cur = ""
          if (t ~ /^## Production Envelope/) { n++; cur = dir "/sec." n; print t > (dir "/sec.heads") }
        }
        if (cur != "") print $0 > cur
      }
      END { print n + 0 > (dir "/sec.count") }
    ' "$WORK/env.txt"
    cnt="$(cat "$WORK/sec.count" 2>/dev/null || echo 0)"; sec=""; n=0
    if [ -z "$ANCHOR" ]; then
      [ "$cnt" -le 1 ] || fail_invalid parse-ambiguous "The envelope file holds several envelopes; name which one to use."
      [ "$cnt" -eq 1 ] && sec="$WORK/sec.1"
    else
      i=1
      while [ "$i" -le "$cnt" ]; do
        # the title is what follows `## Production Envelope` and an optional hyphen; match it case-insensitively
        if sed -n "${i}p" "$WORK/sec.heads" | sed -e 's/^## Production Envelope//' -e 's/^[[:space:]]*-*[[:space:]]*//' | grep -qiF -- "$ANCHOR"; then n=$((n + 1)); sec="$WORK/sec.$i"; fi
        i=$((i + 1))
      done
      [ "$n" -le 1 ] || fail_invalid parse-ambiguous "More than one envelope matches that title."
    fi
    [ -n "$sec" ] && [ -s "$sec" ] || fail_invalid envelope-missing "The envelope file has no matching Production Envelope section."
    : > "$WORK/cmds"; : > "$WORK/ops"
    awk -v cmdfile="$WORK/cmds" -v opsfile="$WORK/ops" -v unterm="$WORK/unterminated" "$FENCE_AWK"'
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function isop(k) { return k == "verification" || k == "abort" || k == "rollback" || k == "stop conditions" }
      function op(k, kind, x) { gsub(/\t/, " ", x); x = trim(x); if (isop(k) && x != "") print k "\t" kind "\t" x > opsfile }
      NR == 1 { next }
      { raw = $0; t = raw; sub(/\r$/, "", t)
        if (fnc(t)) {
          if (!infence) { infence = 1; fch = FCH; flen = FLEN; cmdopen = (cur == "command"); next }
          if (FCH == fch && FLEN >= flen && FREST ~ /^[ \t]*$/) { infence = 0; cmdopen = 0; next }
        }
        if (infence) {
          if (cmdopen) { if (t !~ /^[ \t]*$/) { print raw > cmdfile; ncmd++ } next }
          if (cur != "" && t !~ /^[ \t]*$/) { val[cur] = val[cur] " " trim(t); op(cur, "F", t) }
          next
        }
        d = t; sub(/^[ \t]*(-[ \t]+)?/, "", d); gsub(/\*\*/, "", d)
        if (match(d, /^(Delegation|Epic|Scope item|Command|Blast radius|Preconditions|Verification|Abort|Rollback|Stop conditions):/)) {
          key = tolower(substr(d, 1, RLENGTH - 1)); rest = trim(substr(d, RLENGTH + 1)); cur = key; seen[key] = 1
          if (rest != "") { val[key] = val[key] " " rest; op(key, "L", rest) }
          next
        }
        if (cur == "preconditions" && d ~ /^Gate:[ \t]*[^ \t]/) { gates++; val[cur] = val[cur] " " trim(d); next }
        if (cur != "" && t !~ /^[ \t]*$/) { val[cur] = val[cur] " " trim(d); op(cur, "L", d) }
      }
      END { if (cmdopen) print "1" > unterm; for (k in seen) { v = trim(val[k]); gsub(/\t/, " ", v); print "part\t" k "\t" v } print "gates\t" gates + 0; print "cmds\t" ncmd + 0 }
    ' "$sec" > "$WORK/parts"
    part_val() { awk -F'\t' -v k="$1" '$1 == "part" && $2 == k { print $3; exit }' "$WORK/parts"; }
    [ "$(trim "$(part_val delegation)")" = "$DELEG" ] || fail_invalid envelope-delegation-mismatch "The envelope names a different standing approval than the one being checked." # mut:env-delegation
    EPIC_N="$(trim "$(part_val epic)")"
    [[ "$EPIC_N" =~ ^#[0-9]+$ ]] || fail_invalid envelope-incomplete "The envelope does not say which epic it belongs to." # mut:env-epic-line
    [ "${EPIC_N#\#}" = "$U_ISSUE" ] || fail_invalid epic-mismatch "The envelope belongs to a different epic than the standing approval." # mut:epic-bind
    local SI; SI="$(trim "$(part_val 'scope item')")"
    [[ "$SI" =~ ^[0-9]+$ ]] || fail_invalid envelope-incomplete "The envelope does not name which numbered act it falls under." # mut:env-scopenum
    for c in 'blast radius' preconditions verification abort rollback 'stop conditions'; do [ -n "$(trim "$(part_val "$c")")" ] || fail_invalid envelope-incomplete "The envelope is missing its '$c' part."; done # mut:env-parts
    [ "$(awk -F'\t' '$1 == "gates" { print $2 }' "$WORK/parts")" -ge 1 ] || fail_invalid envelope-incomplete "The envelope lists no preconditions that can be checked." # mut:env-gates
    [ "$(awk -F'\t' '$1 == "cmds" { print $2 }' "$WORK/parts")" -ge 1 ] || fail_invalid envelope-incomplete "The envelope has no command block." # mut:env-cmds
    [ ! -e "$WORK/unterminated" ] || fail_invalid envelope-incomplete "The command block in the envelope is never closed." # mut:env-unterminated
    grep -qx "$SI" "$WORK/scope.nums" || fail_invalid no-scope-item "The standing approval has no numbered act $SI, which the envelope relies on."
    rollback_named "$(part_val rollback)" || fail_invalid rollback-unnamed "The envelope does not name a real way to undo the act." # mut:rollback

    local SCOPE_TEXT; SCOPE_TEXT="$(awk -F'\t' -v n="$SI" '$1 == n { print $2; exit }' "$WORK/scope.items")"
    # EVERY line of every Command block must be an allowed, scope-covered act, whether or not it is asked for.
    while IFS= read -r c || [ -n "$c" ]; do check_command "$c" "$SCOPE_TEXT"; done < "$WORK/cmds"
    while IFS=$'\t' read -r okey okind otxt || [ -n "$okey" ]; do ops_check "$okey" "$okind" "$otxt" "$SCOPE_TEXT"; done < "$WORK/ops"
    for c in ${CMDS[@]+"${CMDS[@]}"}; do
      check_command "$c" "$SCOPE_TEXT"
      cmd_in_block "$c" "$WORK/cmds" || fail_invalid command-not-in-envelope "That command is not, word for word, a line of the envelope." # mut:cmd-match
      VER[${#VER[@]}]="$c"
    done
  fi

  emit valid ok
  printf 'verified-created-at: %s\nverified-expiry: %s\n' "$CREATED" "$P_EXPDATE"
  if [ -n "$ENV" ]; then printf 'verified-envelope-sha256: %s\n' "$(sha256_file "$WORK/env.blob")"; fi
  for c in ${VER[@]+"${VER[@]}"}; do
    printf 'verified-command: %s\n' "$c"
    printf 'verified-sha256: %s\n' "$(sha256_of "$c")"
  done
  exit 0
}

# do_render: build the record, then prove it parses (fail closed: a record that would not verify is never printed).
do_render() {
  local EPIC="" QF="" AF="" SF="" EXPIRY="" today limit f ans
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic)          [ $# -ge 2 ] || die_render "--epic needs a value"; EPIC="$2"; shift 2 ;;
      --question-file) [ $# -ge 2 ] || die_render "--question-file needs a value"; QF="$2"; shift 2 ;;
      --answer-file)   [ $# -ge 2 ] || die_render "--answer-file needs a value"; AF="$2"; shift 2 ;;
      --scope-file)    [ $# -ge 2 ] || die_render "--scope-file needs a value"; SF="$2"; shift 2 ;;
      --expiry)        [ $# -ge 2 ] || die_render "--expiry needs a value"; EXPIRY="$2"; shift 2 ;;
      *) die_render "unknown argument: $1" ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || die_render "jq is not installed"
  [[ "$EPIC" =~ ^[0-9]+$ ]] || die_render "--epic needs an issue number"
  for f in "$QF" "$AF" "$SF"; do [ -n "$f" ] && [ -s "$f" ] && grep -q '[^[:space:]]' "$f" || die_render "the question, answer and scope files must exist and not be empty"; done
  if grep -qE -e '<[!?]' -e '-->' "$SF"; then die_render "the scope items may not hold hidden comments (the operator cannot see them)"; fi # mut:render-html
  ans="$(tr '\r\n' '  ' < "$AF")"; ans="$(trim "$ans")"
  says_yes "$ans" || die_render "the answer must start with Yes: a record of anything else is not a standing approval" # mut:render-yes
  [ "${#ans}" -le "$ANSWER_CAP" ] || die_render "the answer is longer than $ANSWER_CAP characters; it is posted word for word on a public issue, so keep it short" # mut:render-cap
  if grep -Eq -- "$SECRET_RE" "$QF" "$AF"; then die_render "the question or answer looks like it holds a password or key; it would be posted publicly, so I will not write it"; fi # mut:render-secret
  valid_date "$EXPIRY" || die_render "--expiry needs a real date (YYYY-MM-DD)"
  today="$(date -u +%Y-%m-%d)"; limit="$(add_days "$today" 30)"
  [[ ! "$EXPIRY" > "$limit" ]] || die_render "the expiry is more than 30 days away"
  [[ ! "$EXPIRY" < "$today" ]] || die_render "the expiry is in the past"
  render_body "$EPIC" "$today" "$QF" "$AF" "$SF" "$EXPIRY" > "$WORK/rendered.md"
  parse_body "$WORK/rendered.md"
  [ "$P_MARKER_OK" = 1 ] && [ "${#P_QUOTE}" -ge 40 ] && [ "$P_ONE_CONF" = 1 ] && [ -s "$WORK/scope.nums" ] && [ "$P_EXCL_OK" = 1 ] && valid_date "$P_EXPDATE" \
    || die_render "the record would not verify (the quoted question and answer must total at least 40 characters)"
  cat "$WORK/rendered.md"
  exit 0
}

WORK="$(mktemp -d -t dv.XXXXXXXX)" || { echo "delegation: unverifiable reason=tool-missing"; exit 2; }
sub="${1:-}"
[ "$sub" = verify ] || [ "$sub" = render ] || fail_unv usage "usage: delegation-verify.sh verify|render ..." # mut:dispatch
[ $# -gt 0 ] && shift
case "$sub" in
  verify) do_verify "$@" ;;
  render) do_render "$@" ;;
esac
