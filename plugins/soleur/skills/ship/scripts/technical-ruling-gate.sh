#!/usr/bin/env bash
# The /ship Phase 5.5 Technical-Ruling Gate (hard rule hr-technical-fork-is-not-an-operator-question).
#
# Property: no PR reaches ready with a decision-challenges.md or PR-body line that asks the operator a
# TECHNICAL question. Every row of the artifact's `| Item | Class | Ruling |` tables has a valid class;
# every `technical` row carries a `Ruled by CTO|CLO agent, <date>:` cell; no `pending - assumed`
# placeholder survives; and the "Owner decision needed" / "Owner ruling needed" label appears only with
# `(operator: <category>)`. The gate checks FORM, never truth: a model that mislabels a technical
# question as `operator (scope)` still passes (a stated residual, technical-ruling-delegation.md
# section 6); the check on that is review and the operator-visible rendering of operator rows.
#
# Usage:
#   technical-ruling-gate.sh <path>             check one decision-challenges.md
#   technical-ruling-gate.sh --branch           check this branch's artifact under
#                                               knowledge-base/project/specs/<branch>/, or under
#                                               specs/archive/<date>-<slug>/ when archived early;
#                                               an absent artifact is `[PASS] no decision-challenges artifact`
#   technical-ruling-gate.sh --pr-body <file>   check a PR body for an unscoped owner-decision label
#                                               or a surviving `pending - assumed` placeholder
#
# Exit codes:
#   0  every examined row passes (`[PASS]` on stdout). An artifact with NO table is `[WARN]` + exit 0
#      (legacy artifacts and in-flight branches are not blocked); the label and `pending` lints still run.
#   1  at least one failure (`[FAIL] <path>:<line>: <reason> - <remedy>` on stderr, one per finding;
#      <line> is always a line of the checked file)
#   2  could not measure: usage error, an unreadable or EMPTY artifact or PR body (whitespace only counts as
#      empty), a table header with 0 data rows, a header that looks like the Decision Classes header (a
#      separator line follows it) but is not exactly `| Item | Class | Ruling |`, a row whose Class is
#      `technical` that sits OUTSIDE any recognised table (a row after a blank line, a header-less table),
#      an unclosed code fence in the artifact or the PR body (everything after it would be hidden), or an
#      ambiguous archive match. Never a silent pass on something that exists but was not examined.
#
# Table rules (GFM): a table ends at the first line that does not start with `|` (a blank line included);
# a row appended after a blank line is outside the table (a `technical` one is exit 2, never skipped). A
# later writer adds its own header+separator. Inline `code spans` are ignored by the label and pending
# lints (a PR that documents this machinery may quote the strings). A UTF-8 BOM is tolerated. Tables without
# a leading pipe, inside a blockquote or inside a list item are not recognised (residual: the stray-row
# check above catches a `technical` row there).
#
# Reasons (the suite asserts each): bad-class, bad-category, unruled-technical, bad-ruling-shape,
# owner-label-unscoped, delegation-invalid, delegation-unverifiable, receipt-missing, receipt-mismatch,
# receipt-unreadable.
#
# Delegation arm (ADR-289, hr-menu-option-ack-not-prod-write-auth): a row whose Class is exactly
# `operator (production-mutating)` and whose Ruling is
#   Authorized by delegation <comment-url>, envelope <path>[, ran <ISO 8601 UTC time>]
# is validated through plugins/soleur/scripts/delegation-verify.sh. A row WITHOUT `ran` is an authorization for an
# act that has not happened: plain `verify` (expiry and an open epic are enforced now). A row WITH `ran` records an
# act that did: `verify --audit --at <time>` (the delegation must have been in force at that time; only a closed
# epic is forgiven), and the row must also be backed by an execution receipt on the epic: a comment whose FIRST line
# is `<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<verified-envelope-sha256> result=ok|rolled-back
# run=<url|none> -->`, written by an OWNER, MEMBER or COLLABORATOR, naming this row's delegation URL and envelope
# path, the sha256 the verifier just reported for that envelope, and a result of ok or rolled-back. Every field is
# compared EXACTLY, a missing author_association never defaults, and the receipt must lie inside the delegation's life
# (created at or after the delegation, not after the end of its expiry day, not in the future), must never have been
# edited (updated_at == created_at), must come from a User (not a bot), must be created at or after the `ran` instant it
# vouches for (a receipt posted in advance is no receipt), and satisfies at most ONE row (three rows
# cannot share one receipt). A `ran` time later than now is `delegation-invalid`. A delegation row needs a time-limit tool
# (timeout or gtimeout); without one it is `delegation-unverifiable`, never an unbounded call. That is all the check proves:
# a receipt exists, is attributable and matches the row. It is NOT proof of what ran (a receipt-checking
# hook on the executed command is the stronger follow-up, #10361). Missing, mismatching or unreadable receipts are
# `receipt-missing`, `receipt-mismatch`, `receipt-unreadable` (exit 2, never a pass).
# Verdicts: valid passes; invalid is `delegation-invalid` (exit 1); unverifiable, including a missing verifier or a
# verifier whose rc and first line disagree, is `delegation-unverifiable` (exit 2, never a pass). The same ruling
# shape on any other Class is `bad-ruling-shape`: a delegation authorizes only production-mutating acts. The row
# stays required (no row, no pass), every delegation row is examined (the first valid one does not end the scan),
# one verifier call per (delegation, envelope, time) and one receipt read per epic, and a delegation row outside a
# recognised table is exit 2. An ARCHIVED artifact (`--branch` found it under specs/archive/) is checked for row
# shape ONLY, with no network, and says so in its [NOTE] and [PASS] lines. A plain `operator (production-mutating)`
# row with no delegation text passes on form, as before. Format source:
# skills/brainstorm-techniques/references/standing-delegation.md.
#
# Test seams: TRG_VERIFY_TIMEOUT (seconds, 1-59: it can only SHORTEN the 60 s verifier limit), TRG_EXEC_LOG (append one line per examined row), TRG_SPECS_ROOT and TRG_BRANCH (the
# `--branch` lookup, so a suite needs no git repository); any of them being set is announced on stderr.
# Lines carrying `# mut:<name>` are the mutation points the suite edits to prove each check can fail.
#
# `set -uo pipefail`, deliberately NOT `-e`: the scanners are pipelines whose `grep` exits 1 on no match.
# Portable to bash 3.2 and to mawk (no `${var,,}`, no `sed -i`, no awk `{m,n}` intervals).

set -uo pipefail
export LC_ALL=C
shopt -s nocasematch

CATEGORIES="money scope priority schedule irreversible production-mutating legal-risk brand"
CATS_RE="${CATEGORIES// /|}"
LABEL_RE='owner[ \t-]+(decision|ruling)s?[ \t]+((is|are)[ \t]+)?(needed|required)|decision[ \t]+needed[ \t]+from[ \t]+the[ \t]+owner|needs?[ \t]+(the[ \t]+)?owner[ \t]+(decision|ruling)'
RULING_RE='^Ruled by (CTO|CLO) agent, [0-9]{4}-[0-9]{2}-[0-9]{2}: .+'
PENDING_RE='pending[ \t]*[^a-z0-9 \t]+[ \t]*assumed'
VERIFIER="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../../../scripts/delegation-verify.sh"

# Shared context-sanitize lib (#10395), three levels up at scripts/lib/. When it
# is unreadable the same-name fallback carries this site's pre-change strip set
# (tr's [[:cntrl:]] class, under the ambient locale exactly as before — no
# LC_ALL=C pin, so the fallback never strips less than the site did) — never
# weaker than today.
_ctx_lib="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/../../../scripts/lib/context-sanitize.sh"
# shellcheck source=/dev/null
[[ -r "$_ctx_lib" ]] && . "$_ctx_lib" || true
declare -F soleur_ctx_sanitize >/dev/null 2>&1 \
  || soleur_ctx_sanitize() { tr -d '[:cntrl:]'; }
DELEG_RE='^Authorized by delegation (https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)#issuecomment-[0-9]+), envelope ([A-Za-z0-9_./#@ -]+)(, ran ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z))?$'
SHAPE_ONLY=0
SHAPE_ROWS=0
DR=0
TOG=(); TOV=(); HAVE_TO=0; TOBIN=""
CONSUMED=""
if command -v timeout >/dev/null 2>&1; then TOBIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then TOBIN=gtimeout; fi # mut:gtimeout
if [[ -n "$TOBIN" ]]; then
  HAVE_TO=1
  VT=60
  case "${TRG_VERIFY_TIMEOUT:-}" in ''|*[!0-9]*) ;; *) [[ "$TRG_VERIFY_TIMEOUT" -ge 1 && "$TRG_VERIFY_TIMEOUT" -lt 60 ]] && VT="$TRG_VERIFY_TIMEOUT" ;; esac
  TOG=("$TOBIN" 60); TOV=("$TOBIN" "$VT")
fi
CTO_REMEDY='spawn soleur:engineering:cto now (at most two attempts, see technical-ruling-delegation.md), write the Ruled by cell, re-run; after two failed attempts leave the PR draft and file one domain/engineering issue, never an operator question'

work_dir=""
UNCLOSED_SEEN=0
cleanup() { [[ -n "$work_dir" ]] && rm -rf "${work_dir:?}"; return 0; }
trap cleanup EXIT

cat_ok() { case " $CATEGORIES " in *" $1 "*) return 0 ;; esac; return 1; } # mut:cat
is_unruled() { [[ -z "$1" ]]; } # mut:unruled
shape_ok() { [[ "$1" =~ $RULING_RE ]]; } # mut:shape

die2() { printf '[ERROR] %s\n' "$*" >&2; cleanup; exit 2; }

# unfenced_match <file> <regex>: `<line>\t<text>` for every unfenced line whose lowercase form matches, with
# inline `code spans` removed first. A fence closes only on the same character, at least as long, with no info
# string (CommonMark); a backtick fence whose info string contains a backtick is inline code, not a fence.
# `@UNCLOSED` is printed when a fence is still open at end of file.
unfenced_match() {
  awk -v re="$2" '
    function fence_toggle(   tok, c, n) {
      tok = $0; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    { sub(/\r$/, ""); if (NR == 1) sub(/^\357\273\277/, "") }
    /^ ? ? ?(```+|~~~+)/ { fence_toggle(); next } # mut:fence
    f { next }
    { line = $0; gsub(/`[^`]*`/, "", line); if (tolower(line) ~ re) printf "%d\t%s\n", NR, $0 }
    END { if (f) print "@UNCLOSED" }
  ' "$1"
}

# table_rows <file>: per unfenced `| Item | Class | Ruling |` header `@TABLE`, then `<line>\t<row>` per data
# row; `@EMPTY` for a table with no data row, `@BADHEADER` for a header-like row followed by a separator
# that is not exactly ours, `@STRAY` for a `technical` row outside any recognised table, `@UNCLOSED` when a
# code fence is still open at end of file.
table_rows() {
  awk '
    function fence_toggle(   tok, c, n) {
      tok = $0; sub(/^ +/, "", tok)
      match(tok, /^(`+|~+)/); c = substr(tok, 1, 1); n = RLENGTH
      if (!f) { if (c == "`" && substr(tok, n + 1) ~ /`/) return; f = 1; fc = c; fn = n; return }
      if (c == fc && n >= fn && tok ~ /^(`+|~+)[ \t]*$/) f = 0
    }
    function end_table() { if ((state == 3 && rows_in == 0) || state == 2) print "@EMPTY"; state = 0 }
    { sub(/\r$/, ""); if (NR == 1) sub(/^\357\273\277/, "") }
    /^ ? ? ?(```+|~~~+)/ { fence_toggle(); next } # mut:fence-table
    f { next }
    { if (hdr_pending) { if ($0 ~ /^ ? ? ?\|[ :|-]+$/) print "@BADHEADER"; hdr_pending = 0 } }
    { if ((state != 3 || $0 !~ /^ ? ? ?\|/) && tolower($0) ~ /\|[ \t]*technical[ \t]*\|/) print "@STRAY" }
    { if ((state != 3 || $0 !~ /^ ? ? ?\|/) && $0 ~ /^ ? ? ?\|/ && tolower($0) ~ /authorized by delegation/) print "@STRAY" } # mut:stray-deleg
    /^ ? ? ?\|/ {
      line = $0; sub(/^ +/, "", line); sub(/[ \t]+$/, "", line); low = tolower(line)
      if (line ~ /^\|[ \t]*Item[ \t]*\|[ \t]*Class[ \t]*\|[ \t]*Ruling[ \t]*\|$/) { end_table(); print "@TABLE"; state = 2; rows_in = 0; next }
      if (low ~ /item/ && low ~ /class/ && low ~ /ruling/ && state != 3) { hdr_pending = 1; next }
      if (state == 2 && line ~ /^\|[ :|-]+$/) { state = 3; next }
      if (state == 3) { printf "%d\t%s\n", NR, line; rows_in++; next }
      end_table(); next
    }
    { end_table() }
    END { end_table(); if (f) print "@UNCLOSED" }
  ' "$1"
}

check_labels() { # <file> <display-path>; prints [FAIL] lines, returns the count (capped: a status wraps at 256)
  local file="$1" shown="$2" n=0 ln text
  while IFS=$'\t' read -r ln text; do
    [[ -n "$ln" ]] || continue
    if [[ "$ln" == "@UNCLOSED" ]]; then UNCLOSED_SEEN=1; continue; fi
    if [[ ! "$text" =~ \(operator:\ ($CATS_RE)\) ]]; then
      printf '[FAIL] %s:%s: owner-label-unscoped - the owner-decision label may only carry an operator-class item; append (operator: <category>) with a category from the closed list (%s), or route the question to the CTO (technical-ruling-delegation.md)\n' "$shown" "$ln" "$CATEGORIES" >&2
      n=$((n + 1))
    fi
  done < <(unfenced_match "$file" "$LABEL_RE")
  (( n > 255 )) && n=255
  return "$n"
}

check_pending() { # <file> <display-path>; an unresolved placeholder anywhere in the file, returns the count (capped)
  local file="$1" shown="$2" n=0 ln text
  while IFS=$'\t' read -r ln text; do
    [[ -n "$ln" ]] || continue
    if [[ "$ln" == "@UNCLOSED" ]]; then UNCLOSED_SEEN=1; continue; fi
    printf '[FAIL] %s:%s: unruled-technical - a "pending - assumed" placeholder survives: %s\n' "$shown" "$ln" "$CTO_REMEDY" >&2
    n=$((n + 1))
  done < <(unfenced_match "$file" "$PENDING_RE") # mut:pending
  (( n > 255 )) && n=255
  return "$n"
}

# memo_find <keyfile> <key>: prints the 1-based entry number of <key>, or nothing. One key per line.
memo_find() { [[ -f "$1" ]] || return 0; grep -nxF -- "$2" "$1" 2>/dev/null </dev/null | head -1 | cut -d: -f1; } # mut:memo

# receipt_check <delegation-url> <repo> <epic> <envelope-path> <sha> <verified-created-at> <verified-expiry>: sets
# RC_REASON to ok, receipt-missing, receipt-mismatch or receipt-unreadable. One read of the epic's comments per epic;
# every call has stdin closed. A receipt counts only if: its delegation and envelope equal the row's EXACTLY, its sha256
# is the verifier's, its result is ok or rolled-back, its author_association is OWNER, MEMBER or COLLABORATOR (a missing
# one never defaults), it was created inside the delegation's life (not before the delegation, not after the end of its
# expiry day) and not in the future, it was never edited (updated_at == created_at), its author is a User (not a bot),
# and it has not already satisfied another row (a receipt is consumed by the row that uses it).
receipt_check() {
  local durl="$1" repo="$2" epic="$3" env="$4" sha="$5" vcre="$6" vexp="$7" ran="$8" key="$2#$3" n rd re rs rr ra rk rcre rupd rtyp nrec=0 okrec=0 now
  RC_REASON=unreadable
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  n="$(memo_find "$work_dir/rcpt.keys" "$key")"
  if [[ -z "$n" ]]; then
    echo "$key" >> "$work_dir/rcpt.keys"; n="$(wc -l < "$work_dir/rcpt.keys" | tr -d ' ')"
    if ${TOG[@]+"${TOG[@]}"} gh api "repos/$repo/issues/$epic/comments" --paginate >"$work_dir/rcpt.$n.json" 2>/dev/null </dev/null \
       && jq -r -s '[.[][]] | to_entries | .[] | .key as $k | .value
           | (.body // "" | split("\n") | (.[0] // "") | sub("\r$"; "")) as $l
           | ([$l | capture("^<!-- soleur-delegated-act v1 delegation=(?<d>[^ ]+) envelope=(?<e>.+?) sha256=(?<s>[0-9a-f]{64}) result=(?<r>[A-Za-z-]+) run=(?<u>[^ ]+) -->$")] | .[0]) as $m
           | select($m != null) | [$m.d, $m.e, $m.s, $m.r, (.author_association // "ABSENT"), ($k | tostring), (.created_at // "none"), (.updated_at // "none2"), (.user.type // "NONE")] | @tsv' "$work_dir/rcpt.$n.json" >"$work_dir/rcpt.$n.tsv" 2>/dev/null </dev/null; then
      echo ok > "$work_dir/rcpt.$n.st"
    else
      echo bad > "$work_dir/rcpt.$n.st"
    fi
  fi
  [[ "$(cat "$work_dir/rcpt.$n.st")" == ok ]] || return 0
  while IFS=$'\t' read -r rd re rs rr ra rk rcre rupd rtyp; do
    [[ "$rd" == "$durl" ]] || continue # mut:receipt-deleg
    case " $CONSUMED " in *" $n:$rk "*) continue ;; esac # mut:receipt-consume
    nrec=$((nrec + 1))
    [[ "$re" == "$env" ]] || continue # mut:receipt-env
    [[ "$rs" == "$sha" ]] || continue # mut:receipt-sha
    case "$rr" in ok|rolled-back) ;; *) continue ;; esac # mut:receipt-result
    case "$ra" in OWNER|MEMBER|COLLABORATOR) ;; *) continue ;; esac # mut:receipt-author
    [[ "$rcre" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || continue
    # created >= ran also bounds the receipt below by the delegation itself: the verifier enforces delegation created <= ran
    [[ "$rcre" < "$ran" ]] && continue # mut:receipt-before-ran
    [[ "$rcre" > "$now" ]] && continue # mut:receipt-future
    [[ "$rcre" > "${vexp}T23:59:59Z" ]] && continue # mut:receipt-expiry
    [[ "$rupd" == "$rcre" ]] || continue # mut:receipt-edited
    [[ "$rtyp" == User ]] || continue # mut:receipt-bot
    okrec=1; CONSUMED="$CONSUMED $n:$rk"; break
  done < "$work_dir/rcpt.$n.tsv"
  if (( okrec )); then RC_REASON=ok; elif (( nrec > 0 )); then RC_REASON=receipt-mismatch; else RC_REASON=receipt-missing; fi
}

# check_delegation_row <line> <class> <ruling>: DR=0 pass, 1 a finding was printed, 2 could not verify (printed).
# Runs with nocasematch OFF: the phrase, the class and the link are matched exactly.
check_delegation_row() {
  local had=0
  shopt -q nocasematch && had=1
  shopt -u nocasematch # mut:case-off
  check_delegation_row_inner "$@"
  (( had )) && shopt -s nocasematch
  return 0
}
check_delegation_row_inner() {
  local ln="$1" cls="$2" ruling="$3" durl repo epic dpath dran reason why dv_rc dv_line key n sha vcre vexp now
  DR=0
  [[ "$cls" == "operator (production-mutating)" ]] || { printf '[FAIL] %s:%s: bad-ruling-shape - a delegation can authorize only an operator (production-mutating) act, not "%s"\n' "$shown" "$ln" "$cls" >&2; DR=1; return; } # mut:deleg-class
  [[ "$ruling" =~ $DELEG_RE ]] || { printf '[FAIL] %s:%s: bad-ruling-shape - a delegation ruling must read: Authorized by delegation <comment-url>, envelope <path>[, ran <time as 2026-01-31T09:30:00Z>] (standing-delegation.md)\n' "$shown" "$ln" >&2; DR=1; return; }
  durl="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"; epic="${BASH_REMATCH[4]}"; dpath="${BASH_REMATCH[5]}"; dran="${BASH_REMATCH[7]:-}"
  [[ -n "${TRG_EXEC_LOG:-}" ]] && echo "delegation $shown:$ln" >> "${TRG_EXEC_LOG:?}" # mut:deleg-log
  if (( SHAPE_ONLY )); then SHAPE_ROWS=$((SHAPE_ROWS + 1)); DR=0; return; fi
  (( HAVE_TO )) || { printf '[FAIL] %s:%s: delegation-unverifiable - no time limit tool (timeout or gtimeout) is installed, so the delegation was not checked, which is never a pass\n' "$shown" "$ln" >&2; DR=2; return; } # mut:need-timeout
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -n "$dran" && "$dran" > "$now" ]] && { printf '[FAIL] %s:%s: delegation-invalid - the row says the act ran at %s, which is in the future, so it cannot have run yet (reason: ran-in-future)\n' "$shown" "$ln" "$dran" >&2; DR=1; return; } # mut:ran-future
  [[ -f "$VERIFIER" ]] || { printf '[FAIL] %s:%s: delegation-unverifiable - the delegation checker was not found next to this gate, so the row was not examined\n' "$shown" "$ln" >&2; DR=2; return; }
  key="$durl|$dpath|$dran"
  n="$(memo_find "$work_dir/dv.keys" "$key")"
  if [[ -z "$n" ]]; then
    echo "$key" >> "$work_dir/dv.keys"; n="$(wc -l < "$work_dir/dv.keys" | tr -d ' ')"
    if [[ -z "$dran" ]]; then
      ${TOV[@]+"${TOV[@]}"} bash "$VERIFIER" verify --delegation "$durl" --envelope "$dpath" </dev/null >"$work_dir/dv.$n.out" 2>"$work_dir/dv.$n.err"; dv_rc=$? # mut:deleg-call
    else
      ${TOV[@]+"${TOV[@]}"} bash "$VERIFIER" verify --delegation "$durl" --envelope "$dpath" --audit --at "$dran" </dev/null >"$work_dir/dv.$n.out" 2>"$work_dir/dv.$n.err"; dv_rc=$? # mut:deleg-audit
    fi
    echo "$dv_rc" > "$work_dir/dv.$n.rc"
  fi
  dv_rc="$(cat "$work_dir/dv.$n.rc")"
  dv_line="$(head -1 "$work_dir/dv.$n.out")"
  reason="$(printf '%s\n' "$dv_line" | sed -n 's/^delegation: [a-z]* reason=\(.*\)$/\1/p' | soleur_ctx_sanitize | cut -c1-60)"
  why="$(head -1 "$work_dir/dv.$n.err" | soleur_ctx_sanitize | cut -c1-200)"
  if (( dv_rc == 0 )) && [[ "$dv_line" != "delegation: valid reason="* ]]; then dv_rc=2; reason="verifier-error"; why="the delegation checker exited cleanly without saying valid"; fi # mut:deleg-line
  (( dv_rc == 1 )) && { printf '[FAIL] %s:%s: delegation-invalid - %s (reason: %s)\n' "$shown" "$ln" "$why" "$reason" >&2; DR=1; return; }
  (( dv_rc == 0 )) || { printf '[FAIL] %s:%s: delegation-unverifiable - %s (reason: %s); the row was not examined, which is never a pass\n' "$shown" "$ln" "$why" "${reason:-none}" >&2; DR=2; return; } # mut:deleg-unv
  if [[ -n "$dran" ]]; then
    sha="$(sed -n 's/^verified-envelope-sha256: \([0-9a-f]\{64\}\)$/\1/p' "$work_dir/dv.$n.out" | head -1)"
    if [[ -z "$sha" ]]; then
      printf '[FAIL] %s:%s: receipt-unreadable - the delegation checker did not report the runbook fingerprint, so the execution receipt cannot be matched; the row was not examined, which is never a pass\n' "$shown" "$ln" >&2; DR=2; return
    fi
    vcre="$(sed -n 's/^verified-created-at: \([0-9T:Z-]*\)$/\1/p' "$work_dir/dv.$n.out" | head -1)"
    vexp="$(sed -n 's/^verified-expiry: \([0-9-]*\)$/\1/p' "$work_dir/dv.$n.out" | head -1)"
    if [[ ! "$vcre" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ || ! "$vexp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      printf '[FAIL] %s:%s: receipt-unreadable - the delegation checker did not report when the delegation was recorded and when it ends, so the receipt window cannot be checked; the row was not examined, which is never a pass\n' "$shown" "$ln" >&2; DR=2; return
    fi
    receipt_check "$durl" "$repo" "$epic" "$dpath" "$sha" "$vcre" "$vexp" "$dran"
    case "$RC_REASON" in
      ok) ;;
      receipt-missing) printf '[FAIL] %s:%s: receipt-missing - no execution receipt for this delegation is on epic #%s; the CTO writes one comment per delegated act (standing-delegation.md section 8) before this row may say the act ran\n' "$shown" "$ln" "$epic" >&2; DR=2; return ;;
      receipt-mismatch) printf '[FAIL] %s:%s: receipt-mismatch - epic #%s has a receipt for this delegation but none names this envelope path and its verified fingerprint with result ok or rolled-back, written by an owner, member or collaborator\n' "$shown" "$ln" "$epic" >&2; DR=2; return ;;
      *) printf '[FAIL] %s:%s: receipt-unreadable - the comments on epic #%s could not be read, so the execution receipt was not checked, which is never a pass\n' "$shown" "$ln" "$epic" >&2; DR=2; return ;;
    esac
  fi
  echo 'SOLEUR_RULE_APPLIED rule=hr-menu-option-ack-not-prod-write-auth note=delegation-verified'
}

check_artifact() { # <file> <display-path>
  local file="$1" shown="$2" idx=0 fails=0 unv=0 tables=0 ln row inner pipes c2 c3
  [[ -e "$file" ]] || die2 "$shown: no such file"
  [[ -f "$file" && -r "$file" ]] || die2 "$shown: not a readable regular file"
  grep -q '[^[:space:]]' "$file" || die2 "$shown: the artifact is EMPTY; nothing was examined"
  work_dir="$(mktemp -d -t trg.XXXXXXXX)" || die2 "mktemp failed"
  table_rows "$file" > "$work_dir/raw"
  grep -qxF '@UNCLOSED' "$work_dir/raw" && die2 "$shown: a code fence is never closed, so the rest of the file was not examined (close it)"
  grep -qxF '@BADHEADER' "$work_dir/raw" && die2 "$shown: a table header names Item, Class and Ruling but is not exactly '| Item | Class | Ruling |' (fix the header; the rows were not examined)"
  grep -qxF '@STRAY' "$work_dir/raw" && die2 "$shown: a row with Class technical sits outside any '| Item | Class | Ruling |' table (a row after a blank line, or a table without the header); put it in the table or add the header and separator"
  grep -qxF '@EMPTY' "$work_dir/raw" && die2 "$shown: Decision Classes table has 0 rows examined (a header without data rows, or without its separator line)"
  tables="$(grep -cxF '@TABLE' "$work_dir/raw" || true)"
  grep -v '^@' "$work_dir/raw" > "$work_dir/rows" || true
  while IFS=$'\t' read -r ln row; do
    idx=$((idx + 1)) # mut:count
    [[ -n "${TRG_EXEC_LOG:-}" ]] && echo "row $shown:$idx" >> "${TRG_EXEC_LOG:?}"
    inner="${row#|}"; inner="${inner%|}"
    inner="${inner//\\|/$'\001'}"
    pipes="${inner//[^|]/}"
    if [[ ${#pipes} -ne 2 ]]; then
      printf '[FAIL] %s:%s: bad-class - the row must have exactly three cells: Item | Class | Ruling (write a literal pipe as \\|)\n' "$shown" "$ln" >&2
      fails=$((fails + 1)); continue
    fi
    IFS='|' read -r _ c2 c3 _ <<<"$inner"
    c2="${c2#"${c2%%[![:space:]]*}"}"; c2="${c2%"${c2##*[![:space:]]}"}"
    c3="${c3#"${c3%%[![:space:]]*}"}"; c3="${c3%"${c3##*[![:space:]]}"}"
    c2="${c2//$'\001'/|}"; c3="${c3//$'\001'/|}"
    if [[ "$c3" == "Authorized by delegation"* ]]; then check_delegation_row "$ln" "$c2" "$c3"; case "$DR" in 0) ;; 1) fails=$((fails + 1)) ;; *) unv=$((unv + 1)) ;; esac; continue; fi # mut:deleg-all
    if [[ "$c2" == technical ]]; then
      if [[ "$c3" == "pending - assumed"* ]]; then
        : # reported once, with its line, by the file-wide pending lint below
      elif is_unruled "$c3"; then
        printf '[FAIL] %s:%s: unruled-technical - the row is technical with no ruling: %s\n' "$shown" "$ln" "$CTO_REMEDY" >&2
        fails=$((fails + 1))
      elif ! shape_ok "$c3"; then
        printf '[FAIL] %s:%s: bad-ruling-shape - a technical ruling must start: Ruled by CTO agent, <date>: <decision> - <rationale> (anything else, a bare "pending" included, is not a ruling)\n' "$shown" "$ln" >&2
        fails=$((fails + 1))
      fi
    elif [[ "$c2" == taste ]]; then
      : # user-legible Taste: auto-decided with a recommendation, rendered under Model Dissents, no ruling cell
    elif [[ "$c2" =~ ^operator\ \(([a-z-]+)\)$ ]]; then
      if ! cat_ok "${BASH_REMATCH[1]}"; then
        printf '[FAIL] %s:%s: bad-category - category "%s" is not in the closed list (%s)\n' "$shown" "$ln" "${BASH_REMATCH[1]}" "$CATEGORIES" >&2
        fails=$((fails + 1))
      elif [[ -z "$c3" ]]; then
        printf '[FAIL] %s:%s: bad-ruling-shape - an operator row must name the ACTION being authorised in its Ruling cell\n' "$shown" "$ln" >&2
        fails=$((fails + 1))
      fi
    elif [[ "$c2" == operator ]]; then
      printf '[FAIL] %s:%s: bad-category - a bare "operator" is invalid; write operator (<category>) with a category from the closed list (%s)\n' "$shown" "$ln" "$CATEGORIES" >&2
      fails=$((fails + 1))
    else
      printf '[FAIL] %s:%s: bad-class - Class must be "technical", "taste" or "operator (<category>)", got "%s"\n' "$shown" "$ln" "$c2" >&2
      fails=$((fails + 1))
    fi
  done < "$work_dir/rows"
  check_pending "$file" "$shown"; fails=$((fails + $?))
  check_labels "$file" "$shown"; fails=$((fails + $?))
  if (( fails > 0 )); then return 1; fi
  if (( unv > 0 )); then return 2; fi
  if (( tables == 0 )); then
    printf '[WARN] %s: no "| Item | Class | Ruling |" table outside a fenced block; label and pending lints ran, rows were not examined (add the table: technical-ruling-delegation.md section 6)\n' "$shown"
    return 0
  fi
  if (( SHAPE_ROWS > 0 )); then
    printf '[PASS] %s: %s rows examined (archived: %s delegation rows were checked for shape only and were NOT verified)\n' "$shown" "$idx" "$SHAPE_ROWS"
  else
    printf '[PASS] %s: %s rows examined\n' "$shown" "$idx"
  fi
  return 0
}

if [[ -n "${TRG_SPECS_ROOT:-}${TRG_BRANCH:-}${TRG_EXEC_LOG:-}${TRG_VERIFY_TIMEOUT:-}" ]]; then
  printf '[NOTE] test seam active (TRG_SPECS_ROOT=%s TRG_BRANCH=%s): this is not the live repository lookup\n' "${TRG_SPECS_ROOT:-}" "${TRG_BRANCH:-}" >&2
fi

mode="${1:-}"
case "$mode" in
  --pr-body)
    f="${2:-}"; [[ -n "$f" ]] || die2 "usage: --pr-body <file>"
    [[ -f "$f" && -r "$f" ]] || die2 "$f: not a readable regular file"
    if ! { [[ -s "$f" ]] && grep -q '[^[:space:]]' "$f"; }; then
      die2 "$f: the PR body is EMPTY (the fetch that wrote it most likely failed); nothing was examined"
    fi
    fails=0
    check_pending "$f" "$f"; fails=$((fails + $?))
    check_labels "$f" "$f"; fails=$((fails + $?))
    (( UNCLOSED_SEEN )) && die2 "$f: a code fence in the PR body is never closed, so the rest of it was not examined (close it)"
    if (( fails > 0 )); then exit 1; fi
    printf '[PASS] %s: no unscoped owner-decision label and no pending placeholder\n' "$f"
    exit 0 ;;
  --branch)
    branch="${TRG_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null)}"
    [ -n "$branch" ] && [ "$branch" != HEAD ] || die2 "cannot resolve the branch (detached HEAD or no git)"
    if [[ -n "${TRG_SPECS_ROOT:-}" ]]; then
      root="$TRG_SPECS_ROOT"
    else
      top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
      [[ -n "$top" ]] || die2 "not inside a git repository, so the specs directory cannot be located"
      root="$top/knowledge-base/project/specs"
    fi
    safe="${branch//\//-}"; slug="$safe"
    slug="${slug#feature-}"; slug="${slug#feat-}"; slug="${slug#fix-}"
    matches=()
    add_match() { local m; for m in ${matches[@]+"${matches[@]}"}; do [[ "$m" == "$1" ]] && return 0; done; matches+=("$1"); }
    [[ -f "$root/$safe/decision-challenges.md" ]] && add_match "$root/$safe/decision-challenges.md"
    [[ -f "$root/archive/$safe/decision-challenges.md" ]] && add_match "$root/archive/$safe/decision-challenges.md"
    # archive directories are `<date>-<name>`, `<date>-<time>-<name>` or `<date>-<name>`: anchor the whole prefix
    # so a short slug never suffix-matches another feature's longer name.
    for pre in '????-??-??' '????????-??????' '????????'; do
      for nm in "$slug" "$safe"; do
        for cand in "$root"/archive/$pre-"$nm"/decision-challenges.md; do
          [[ -f "$cand" ]] && add_match "$cand"
        done
      done
    done
    if (( ${#matches[@]} == 0 )); then
      printf '[PASS] no decision-challenges artifact for %s\n' "$branch"
      exit 0
    fi
    (( ${#matches[@]} == 1 )) || die2 "ambiguous: ${#matches[@]} decision-challenges.md files match branch $branch (${matches[*]}); examine the right one by path"
    case "${matches[0]}" in */archive/*) SHAPE_ONLY=1; printf '[NOTE] archived artifact: delegation rows are checked for shape only and are NOT verified (no network)\n' >&2 ;; esac
    check_artifact "${matches[0]}" "${matches[0]}"; exit $? ;;
  ""|-h|--help)
    die2 "usage: $(basename "$0") <path> | --branch | --pr-body <file>" ;;
  -*) die2 "unknown option: $mode" ;;
  *)
    check_artifact "$mode" "$mode"; exit $? ;;
esac
