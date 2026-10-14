#!/usr/bin/env bash
# Trusted-verdict filter for follow-through probes.
#
# THE PROPERTY. A `RESULT: PASS|FAIL` line may change a probe's exit code only when
# its AUTHOR holds `admin`, `maintain` or `write` on this repository, resolved with
# the token the probe is actually running under. A permission read that fails yields
# TRANSIENT — never PASS.
#
# WHY NOT `authorAssociation`. Every probe used to filter on
# `authorAssociation in (OWNER, MEMBER, COLLABORATOR)`, which #7448 added to stop a
# forged `RESULT: PASS` from any authenticated GitHub user on this PUBLIC repo. The
# threat model is right; the mechanism is not. `authorAssociation` is computed
# against the READING token's visibility, so under the sweeper's `GITHUB_TOKEN` an
# org member whose membership is PRIVATE renders as `CONTRIBUTOR` and the filter
# drops their verdict silently. Measured on #6617: the operator posted
# `RESULT: PASS` on 2026-07-20, `GET orgs/jikig-ai/public_members/deruelle` is 404
# (private membership), and the nightly sweeper reported FAIL every night for two
# months against an issue whose verdict was already recorded.
#
# `GET /repos/{owner}/{repo}/collaborators/{login}/permission` resolves EFFECTIVE
# permission and does not depend on membership visibility (measured 2026-09-19:
# `admin` for the operator, `none` for `github-actions[bot]`, under the operator
# token). One call per DISTINCT author (logins are case-insensitive on GitHub,
# so the memo key is the lower-cased login), and ONLY for authors with a candidate comment: at
# least one line that, after the fence/HTML strip, starts `RESULT:` or `S<n>-<UPPERCASE-WORD>:`
# (a superset of every consumer's own marker pattern). Every other author is dropped with no
# request, so a drive-by commenter whose permission read fails cannot wedge the tracker (rc 2); an
# author who IS a candidate and whose read fails still is rc 2. This decides WHICH authors are
# resolved and never what a resolved trusted author contributes: all of their comments come through.
# The memo lives for ONE view invocation
# (`trusted_verdict_bodies` or `trusted_verdict_comments`): the shared core runs under
# command substitution (`$(...)`), so its memo dies with that subshell and nothing carries
# across view calls, which also means a login-keyed table that knows no repository cannot
# leak a permission from one repository to another. A thread with many comments from one
# author still costs one request.
#
# TWO VIEWS OF ONE CORE. `_trusted_verdict_core` is the only place a comment read
# becomes trusted text; the public functions are projections of it:
#   trusted_verdict_bodies    the trusted bodies, one per comment of a candidate author (`RESULT:` probes, and any
#                             probe that never reads the comment's time)
#   trusted_verdict_comments  one compact JSON object `{t, b}` per trusted comment, `t`
#                             the comment's `createdAt` (probes that order markers by time,
#                             such as the S3 soak probe)
# Rule of thumb: need the comment's created time -> the comments view, else the bodies view.
#
# RC 2 (TRANSIENT) is the ONE list below, and it is the only copy: every other comment, runbook,
# stub and probe label points here. rc 2 always leaves stdout EMPTY, and the probes map it to
# their own exit. Exit-code contract: probes written after this lib (the soak probes, and the stub
# template for new probes) exit 3 on rc 2, which the sweeper renders CANNOT ESTABLISH; the three
# `RESULT:` probes that predate the rule (concierge-strand-754ee124-5733.sh,
# cpx22-invoice-reconcile-7431.sh, inngest-zot-client-authz-6500.sh) exit 2 on rc 2, which the
# sweeper renders NOT YET: still non-closing, so nothing closes on a failed read either way.
#   1. the comment read (`gh issue view`) failed;
#   2. a permission read failed (anything but a 2xx or a 404, which means "not a user");
#   3. a stage AFTER the comment read failed (stderr names it: `stage '<name>' failed`, or the
#      author for the absent-memo guard): the row split lost or gained a row (rowcount), the
#      base64 decode, a row-field extraction (author, body, created), the distinct-login count
#      (logincount), the marker-line grep (candidate), a candidate author with no memoized permission, a trusted body that holds a NUL byte
#      (that one is deterministic: it will not clear on retry, edit the comment), the fence
#      strip, the record build, or the bodies view's `jq -r .b` projection;
#   4. the comments view ONLY: a trusted comment whose `createdAt` is missing or not ISO.
# Every stage after the comment read is all-or-nothing: each substitution is checked, and two
# counts (rows collected vs rows in the input, distinct logins collected vs distinct logins in
# the memo, which now counts candidates only) catch what a status cannot see. The NUL guard is defence in depth: real `gh`
# rewrites control characters in its JSON output (U+0000 arrives as the two characters `^@`),
# so a NUL cannot reach this lib in production; the suite drives it synthetically (its fake
# `gh` runs the system jq). Fenced blocks are stripped by CommonMark-style
# rules (backtick/tilde fences, the length rule, the info-string rule) and HTML comments
# (`<!-- -->`, one-line or multi-line; an unclosed one strips to the end of the body) in the same
# pass; `<pre>` blocks are NOT handled. The details are on `_trusted_verdict_strip_hidden`.
#
# SOURCED, never executed: no top-level `exit` (a sourced `exit` terminates the
# SOURCING parent), no `set -e`. Callers keep their own exit semantics.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/trusted-verdict.sh"
#   if ! bodies="$(trusted_verdict_bodies 9512)"; then exit 3; fi    # 2 = rc 2 above; the caller picks its exit
#   if ! json="$(trusted_verdict_comments 9728)"; then exit 3; fi    # {t,b} per trusted comment, where `t` is needed
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

# Memo table: lower-cased login -> permission string. Declared once; `declare -gA` so it
# survives being sourced from inside a function.
# `unset` first: an inherited EXPORTED scalar of the same name would otherwise be converted by
# `declare -gA` into an array whose key `0` holds its value, and a login `0` (it passes the
# shape guard) would then read as pre-resolved.
if ! unset _TRUSTED_VERDICT_PERM 2>/dev/null; then
  # a READONLY variable of that name: `declare -gA` would fail too and print the refusal below, which would be false
  echo "trusted-verdict: cannot reset the memo table _TRUSTED_VERDICT_PERM (it is readonly in this shell). REFUSING rather than reusing a table this lib did not build." >&2
  return 2 2>/dev/null || exit 2
fi
if ! declare -gA _TRUSTED_VERDICT_PERM 2>/dev/null; then
  # REFUSE, never degrade. Without associative arrays (bash 3.2 — stock macOS
  # /bin/bash), `_TRUSTED_VERDICT_PERM[$login]=` creates an INDEXED array whose
  # subscript is evaluated ARITHMETICALLY, so every login collapses to index 0:
  # the first resolved permission would then apply to every author, and one
  # trusted commenter in the thread would authorise a stranger's verdict. That is
  # a silent authorization bypass, i.e. exactly the #7448 forgery this lib exists
  # to close, reached from the other side. CI runs bash 5, so this is a guard for
  # an operator running the probe by hand, not a path the merge gate takes.
  echo "trusted-verdict: this shell has no associative arrays (bash >= 4 required; found ${BASH_VERSION:-unknown}). REFUSING rather than degrading — an indexed-array fallback would authorise every author with the first resolved permission." >&2
  return 2 2>/dev/null || exit 2
fi

# _trusted_verdict_permission <login> [repo]
#   Resolves once and MEMOIZES into _TRUSTED_VERDICT_PERM[$login].
#   stdout: the permission string (admin|maintain|write|triage|read|none)
#   rc 0   = resolved
#   rc 2   = could not resolve (network, 403, 404, malformed) — the caller must
#            treat this as TRANSIENT and must NOT fall through to "untrusted".
#
# CALL IT WITHOUT COMMAND SUBSTITUTION when you want the memo. `x="$(_trusted_...)"`
# runs the function in a SUBSHELL, so the memo write is discarded and every author
# then reads as untrusted — measured here on 2026-09-19: rows 2, 3 and 7 of the
# matrix all reported "no verdict" for an `admin` author while row 1 (untrusted)
# passed, which is indistinguishable from the filter working. Use
# `_trusted_verdict_permission "$l" "$r" >/dev/null` — a redirect, not a subshell.
_trusted_verdict_permission() {
  local login="$1" repo="${2:-jikig-ai/soleur}" perm key
  if [[ -z "$login" ]]; then return 2; fi
  key="${login,,}"   # GitHub logins are case-insensitive: `Admin1` and `admin1` are one user, one lookup
  if [[ -n "${_TRUSTED_VERDICT_PERM[$key]:-}" ]]; then
    printf '%s' "${_TRUSTED_VERDICT_PERM[$key]}"
    return 0
  fi
  # `gh api` exits non-zero on ANY non-2xx, so the error arm must separate two
  # cases that would otherwise collapse:
  #
  #   HTTP 404 — DEFINITIVE. The login is not a user of this repository. Every
  #     thread here carries comments from `github-actions`, and GitHub answers
  #     `{"message":"github-actions is not a user", ... "status":"404"}` for it
  #     (measured 2026-09-19). Reading that as TRANSIENT makes EVERY tracker with
  #     a bot comment permanently unresolvable — the first build of this lib did
  #     exactly that and returned rc=2 on #6617, which is the same permanent-red
  #     outcome the lib exists to remove, arrived at from the other side. A 404 is
  #     only reachable here because the issue read above already succeeded against
  #     this repo, so repo visibility is established and 404 means the LOGIN.
  #
  #   anything else (403, 5xx, network, malformed) — TRANSIENT. The caller must
  #     NOT fall through to "untrusted": an unresolvable permission is not a
  #     negative answer.
  # lint-trap-ownership: ok sourced library — an EXIT trap here would REPLACE the caller's; every return path below rm -f's it, so the residual is one empty file per SIGKILL in a two-statement window (ADR-129; same reasoning as scripts/lib/git-data-boot-signal-poll.sh)
  local errf; errf="$(mktemp)"
  if ! perm="$(gh api "repos/${repo}/collaborators/${login}/permission" \
                 --jq '.permission // empty' 2>"$errf")"; then
    if grep -qE '\(HTTP 404\)|"status": *"404"' "$errf"; then
      perm="none"
    else
      rm -f "$errf"; return 2
    fi
  fi
  rm -f "$errf"
  if [[ -z "$perm" ]]; then return 2; fi
  _TRUSTED_VERDICT_PERM[$key]="$perm"
  printf '%s' "$perm"
  return 0
}

# _trusted_verdict_is_trusted_perm <permission>
#   rc 0 = the permission may speak for this repository (admin, maintain, write)
#   rc 1 = anything else (triage, read, none, ...). The ONE place the trust set is written.
_trusted_verdict_is_trusted_perm() {
  case "$1" in
    admin|maintain|write) return 0 ;;
    *) return 1 ;;
  esac
}

# _trusted_verdict_strip_hidden   (stdin -> stdout)
#   Drops what a reader never sees as a marker, so a quoted template or a hidden note cannot arm a
#   probe. Two things, one awk pass, one status (the caller checks it: stage `strip`).
#   FENCES: a CommonMark-style state machine, not a toggle on any fence-looking line: an opener is
#   up to 3 leading spaces plus 3 or more of ONE fence character (backtick or tilde; a backtick
#   opener whose info string holds a backtick is inline code, not a fence); a closer is the SAME
#   character, at least as long as the opener, with nothing but whitespace after it; 4 or more
#   leading spaces (or a tab) is indented code, not a fence. A fence still open at the end of the
#   body strips to the end of the body. The naive toggle let a 4-backtick fence wrapping a
#   3-backtick line, or a backtick fence "closed" by a tilde line, expose a quoted marker as live.
#   HTML COMMENTS: `<!-- ... -->`, one-line or spanning lines, is invisible when rendered but live to
#   a grep, so it is removed; the text before the opener and after the closer on the same line is
#   kept and joined (what a renderer shows). An UNCLOSED `<!--` strips to the end of the body: the
#   fail-safe direction is FEWER markers, never a hidden one counted (the cost: an unclosed `<!--`
#   quoted in inline code hides every marker after it). The two do not mix up: inside a fence a
#   `<!--` is fence content and opens nothing; inside a comment a fence-looking line is comment
#   content and opens nothing (fence rules win in a fence, comment rules win in a comment).
#   `<pre>` blocks are NOT handled. A line the comment consumed whole is dropped, not left blank.
_trusted_verdict_strip_hidden() {
  awk '
    function scrub(s,   out, p, q) {
      out = ""
      while ((p = index(s, "<!--")) > 0) {
        out = out substr(s, 1, p - 1)
        s = substr(s, p + 4)
        q = index(s, "-->")
        if (q == 0) { c = 1; return out }
        s = substr(s, q + 3)
      }
      return out s
    }
    {
      line = $0; ind = 0
      if (match(line, /^ */)) ind = RLENGTH
      tok = ""; ch = ""; n = 0; rest = ""
      if (ind <= 3) {
        t = substr(line, ind + 1)
        if (match(t, /^```+/) || match(t, /^~~~+/)) { tok = substr(t, 1, RLENGTH); ch = substr(tok, 1, 1); n = RLENGTH; rest = substr(t, RLENGTH + 1) }
      }
      if (ch == "`" && index(rest, "`") > 0) n = 0
      if (c) {
        p = index(line, "-->")
        if (p == 0) next
        c = 0
        out = scrub(substr(line, p + 3))
        if (out != "") print out
        next
      }
      if (f) {
        if (n > 0 && ch == fch && n >= fn && rest ~ /^[ \t\r]*$/) f = 0
        next
      }
      if (n > 0) { f = 1; fch = ch; fn = n; next }
      out = scrub(line)
      if (out == "" && line != "") next
      print out
    }'
}

# _trusted_verdict_stage_fail <stage> <issue> [detail]
#   The ONE exit for a failed stage after the comment read: names the stage on stderr (the
#   rows assert the stage name, so two guards that would both end in rc 2 stay distinguishable).
#   Without a detail the stage is a transient fault; a stage whose cause is deterministic
#   passes its own wording. The caller `return 2`s; this only speaks.
_trusted_verdict_stage_fail() {
  echo "trusted-verdict: stage '$1' failed on #$2. ${3:-TRANSIENT, not a dropped comment.}" >&2
}

# _trusted_verdict_core <issue-number> <repo>
#   THE chokepoint: the only place a comment read becomes trusted text. One
#   `gh issue view --json comments` read (gh returns every page of comments: measured
#   220 of 220 on #9777, gh 2.102.0, 2026-10-13; no suite pins it), every distinct CANDIDATE author resolved
#   through `_trusted_verdict_permission` BEFORE anything is emitted, then one JSON
#   object `{t, b}` per trusted comment, API order: `t` = `createdAt` verbatim (empty
#   when absent), `b` = the body with fenced blocks and HTML comments stripped.
#   rc 0 = the read succeeded (empty stdout = no trusted comment)
#   rc 2 = TRANSIENT, the causes are the header's rc 2 list; stdout is EMPTY (output is
#          accumulated and printed once, so a failure never leaves a prefix)
#   The core does NOT validate `t`: the bodies view does not use it. Call it inside
#   `$(...)`: the memo lives for the one call, which is all a single read needs.
#
#   ALL-OR-NOTHING AFTER THE COMMENT READ, enforced as an invariant and not stage by stage:
#   every command substitution below is checked (`x="$(cmd)" || fail`, never `local x=$(cmd)`),
#   and two CONSERVATION counts defeat the failures a status cannot see (a here-string that
#   loses lines): the rows the split loop collected must equal the rows the input holds
#   (counted a second way, from the newlines), and the distinct logins that ended up in the
#   memo must equal the distinct logins collected.
_trusted_verdict_core() {
  local issue="$1" repo="$2" raw b64 login row author body created perm rec nul out="" i n_in n_resolved=0 stripped_nl cand_rc
  local -a rows=() order=() authors=() bodies=()
  local -A seen=()
  # `.author.login`, `.body` and `.createdAt`, as one base64 JSON array per comment. A
  # comment with no author cannot be attributed and is dropped by the first `select`, so
  # it can never carry a verdict. The second `select` drops a login that is not a
  # GitHub login (`a/../b`, `x?y`, a newline, a leading `-`): the login is interpolated
  # into a URL path for the permission request, so a malformed one is UNTRUSTED with no
  # request at all, and must not become a permanent rc 2 for the whole thread either.
  if ! raw="$(gh issue view "$issue" --repo "$repo" --json comments --jq '
        .comments[]
        | select((.author.login // "") != "")
        | select(.author.login | test("\\A[A-Za-z0-9][A-Za-z0-9_-]{0,38}\\z"))
        | [(.author.login), (.body // ""), (.createdAt // "")]
        | @base64' 2>/dev/null)"; then
    return 2
  fi
  # base64 per comment: bodies are multi-line and contain tabs, newlines and
  # backticks, none of which survive a naive line-oriented split.
  # CONSERVATION 1: the split loop (a here-string) must collect exactly as many rows as the
  # input holds. The expected count comes from the newlines, a different mechanism.
  stripped_nl="${raw//$'\n'/}"
  if [[ -n "$raw" ]]; then n_in=$(( ${#raw} - ${#stripped_nl} + 1 )); else n_in=0; fi
  if [[ -n "$raw" ]]; then
    while IFS= read -r b64; do
      rows+=("$b64")
    done <<<"$raw"
  fi
  if (( ${#rows[@]} != n_in )); then _trusted_verdict_stage_fail rowcount "$issue"; return 2; fi

  # Pass 1: decode each row once, strip its body, and collect the DISTINCT CANDIDATE authors (first-seen
  # order): those with at least one line, after the fence/HTML strip, that starts a marker
  # (`RESULT:` or `S<n>-<UPPERCASE-WORD>:`, a superset of every consumer's own pattern). An author
  # with no such line contributes nothing a probe reads, so they are never looked up: a drive-by
  # commenter whose permission read fails (any non-404 error) would otherwise wedge the tracker (rc 2).
  for ((i = 0; i < ${#rows[@]}; i++)); do
    { row="$(printf '%s' "${rows[i]}" | base64 -d)" && [[ -n "$row" ]]; } || { _trusted_verdict_stage_fail decode "$issue"; return 2; }
    rows[i]="$row"
    { author="$(printf '%s' "$row" | jq -r '.[0]')" && [[ -n "$author" ]]; } || { _trusted_verdict_stage_fail author "$issue"; return 2; }
    authors[i]="$author"
    # A lone CR is a line ending in CommonMark; normalise it to LF so the strip sees the
    # same lines a renderer does (CRLF is left alone: the awk accepts a trailing CR). The `contains`
    # guard keeps CR-free bodies (almost all of them) off the regex: gsub is quadratic in the number of
    # lone CRs (measured 34 s for 65k of them on jq 1.8.2).
    body="$(printf '%s' "$row" | jq -r '.[1] | if contains("\r") then gsub("\r(?!\n)"; "\n") else . end')" || { _trusted_verdict_stage_fail body "$issue"; return 2; }
    body="$(printf '%s\n' "$body" | _trusted_verdict_strip_hidden)" || { _trusted_verdict_stage_fail strip "$issue"; return 2; }
    bodies[i]="$body"
    # grep rc 0 = a marker line, 1 = none, anything else = the grep itself failed (never read as "none")
    grep -aqE '^(RESULT|S[0-9]+-[A-Z][A-Z-]*):' <<<"$body"; cand_rc=$?
    if (( cand_rc > 1 )); then _trusted_verdict_stage_fail candidate "$issue"; return 2; fi
    if (( cand_rc == 0 )) && [[ -z "${seen[${author,,}]+x}" ]]; then seen[${author,,}]=1; order+=("$author"); fi
  done

  # Pass 2: resolve every distinct author BEFORE anything is emitted.
  for login in ${order[@]+"${order[@]}"}; do
    # `>/dev/null`, NOT `perm="$(...)"` — see the note on the resolver above.
    if ! _trusted_verdict_permission "$login" "$repo" >/dev/null; then
      return 2
    fi
  done
  # CONSERVATION 2: every DISTINCT login collected must have its permission in the memo.
  if (( ${#seen[@]} > 0 )); then
    for login in "${!seen[@]}"; do
      if [[ -n "${_TRUSTED_VERDICT_PERM[$login]:-}" ]]; then n_resolved=$((n_resolved + 1)); fi
    done
  fi
  if (( n_resolved != ${#seen[@]} )); then _trusted_verdict_stage_fail logincount "$issue"; return 2; fi

  # Pass 3: the trusted rows. An author who was never a candidate was never resolved and is dropped
  # here by construction (not an "unresolved" author: the absent-memo guard below is for the others).
  for ((i = 0; i < ${#rows[@]}; i++)); do
    author="${authors[i]}"
    [[ -n "${seen[${author,,}]+x}" ]] || continue
    perm="${_TRUSTED_VERDICT_PERM[${author,,}]:-}"
    # An ABSENT memo entry is not a negative answer. Pass 2 resolves exactly this author
    # set and returns 2 on any failure, so this is unreachable today: which is precisely
    # why it is worth pinning. `*) continue ;;` alone silently merged "resolved as
    # untrusted" with "never resolved at all", the collapse this lib's own header forbids
    # ("an unresolvable permission is not a negative answer"). A future edit that makes
    # pass 2 partial (batching, caching, a per-author skip) would turn a silent drop back
    # on, and a dropped verdict is invisible by construction.
    if [[ -z "$perm" ]]; then
      echo "trusted-verdict: no memoized permission for '${author}' — the resolver did not run for this author. TRANSIENT, not untrusted." >&2
      return 2
    fi
    _trusted_verdict_is_trusted_perm "$perm" || continue
    # A NUL byte cannot cross a bash command substitution: `$(...)` drops it silently, which
    # can JOIN `S2-ACTI<NUL>VATED` into a live marker. Refuse the trusted comment instead.
    nul="$(printf '%s' "${rows[i]}" | jq -r '.[1:][] | explode | any(. == 0)')" || { _trusted_verdict_stage_fail nulcheck "$issue"; return 2; }
    case "$nul" in *true*) _trusted_verdict_stage_fail nul "$issue" "A trusted comment contains a NUL byte; this will not clear on retry: edit that comment."; return 2 ;; esac
    created="$(printf '%s' "${rows[i]}" | jq -r '.[2]')" || { _trusted_verdict_stage_fail created "$issue"; return 2; }
    body="${bodies[i]}"
    # The body goes to jq on STDIN, never as an `--arg` (one argv string is capped near 128 KiB:
    # a longer trusted body failed `Argument list too long`, the failure went unchecked and the
    # comment vanished with rc 0, the same silent drop this lib exists to remove).
    if ! rec="$(printf '%s' "$body" | jq -Rsc --arg t "$created" '{t: $t, b: .}')" || [[ -z "$rec" ]]; then
      _trusted_verdict_stage_fail record "$issue"
      return 2
    fi
    out="${out}${rec}"$'\n'
  done

  printf '%s' "$out"
  return 0
}

# trusted_verdict_bodies <issue-number> [repo]
#   stdout: the bodies of comments whose author is trusted, oldest-first, with
#           fenced code blocks and HTML comments stripped so a quoted or hidden marker cannot arm a probe.
#   rc 0   = the read succeeded (an EMPTY result means "no trusted verdict yet",
#            which is a legitimate answer)
#   rc 2   = TRANSIENT, causes in the header's rc 2 list. NOT evidence of absence.
trusted_verdict_bodies() {
  local issue="$1" repo="${2:-jikig-ai/soleur}" records proj
  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  # captured, then printed on success only: a projection that dies half way must not leave a prefix on
  # stdout (the trailing `x` keeps the substitution from eating the last bodies' newlines)
  proj="$(printf '%s\n' "$records" | jq -r '.b' && printf x)" || return 2
  printf '%s' "${proj%x}"
  return 0
}

# trusted_verdict_comments <issue-number> [repo]
#   stdout: one compact JSON object per trusted comment, oldest-first: {"t": <createdAt>, "b": <body, fences stripped>}.
#           Project with `jq -r '.b'` (the same text `trusted_verdict_bodies` returns) or sort on `.t`.
#   rc 0   = the read succeeded (empty stdout = no trusted comment yet, a legitimate answer)
#   rc 2   = TRANSIENT, causes in the header's rc 2 list; cause 4 is this view's own: `t` must be
#            `YYYY-MM-DDTHH:MM:SSZ` (a caller sorts `t` lexicographically and may hand it to
#            `date -d`, which accepts natural language), never a default timestamp.
trusted_verdict_comments() {
  local issue="$1" repo="${2:-jikig-ai/soleur}" records
  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  if ! printf '%s\n' "$records" | jq -e -s 'all(.[]; .t | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z"))' >/dev/null 2>&1; then
    echo "trusted-verdict: a trusted comment on #${issue} has a missing or non-ISO createdAt. TRANSIENT, not a default timestamp." >&2
    return 2
  fi
  printf '%s\n' "$records"
  return 0
}
