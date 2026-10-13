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
# token). One call per DISTINCT author, memoized WITHIN ONE VIEW INVOCATION
# (`trusted_verdict_bodies` or `trusted_verdict_comments`) — every consumer calls a view
# under command substitution, so the memo dies with that subshell and does not carry
# across calls (measured; the upside is that a login-keyed, repo-unaware table cannot
# leak a permission between repos). So a thread with many comments from one author
# costs one request.
#
# TWO VIEWS OF ONE CORE. `_trusted_verdict_core` is the only place a comment read
# becomes trusted text; the public functions are projections of it:
#   trusted_verdict_bodies    the trusted bodies, one per comment (`RESULT:` probes)
#   trusted_verdict_comments  one compact JSON object `{t, b}` per trusted comment, `t`
#                             the comment's `createdAt` (marker probes that order
#                             markers by time, such as the S3 soak probe)
# Both return 2 on any unreadable trust decision, with EMPTY stdout. The probes map
# rc 2 to their own exit (the soak probes: 3 via `fail_api`; concierge: 2).
#
# SOURCED, never executed: no top-level `exit` (a sourced `exit` terminates the
# SOURCING parent), no `set -e`. Callers keep their own exit semantics.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/trusted-verdict.sh"
#   if ! bodies="$(trusted_verdict_bodies 5733)"; then exit 2; fi   # 2 = TRANSIENT
#   if ! json="$(trusted_verdict_comments 9818)"; then exit 3; fi   # {t,b} per trusted comment
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

# Memo table: login -> permission string. Declared once; `declare -gA` so it
# survives being sourced from inside a function.
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
  local login="$1" repo="${2:-jikig-ai/soleur}" perm
  if [[ -z "$login" ]]; then return 2; fi
  if [[ -n "${_TRUSTED_VERDICT_PERM[$login]:-}" ]]; then
    printf '%s' "${_TRUSTED_VERDICT_PERM[$login]}"
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
  _TRUSTED_VERDICT_PERM[$login]="$perm"
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

# _trusted_verdict_strip_fences   (stdin -> stdout)
#   Drops fenced blocks so a quoted template cannot arm a probe. Both fence spellings:
#   CommonMark allows ``` and ~~~, and stripping only one left the other as a live
#   channel for a quoted template to arm a probe.
_trusted_verdict_strip_fences() {
  awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f { print }'
}

# _trusted_verdict_core <issue-number> <repo>
#   THE chokepoint: the only place a comment read becomes trusted text. One
#   `gh issue view --json comments` read (all pages), every distinct author resolved
#   through `_trusted_verdict_permission` BEFORE anything is emitted, then one JSON
#   object `{t, b}` per trusted comment, API order: `t` = `createdAt` verbatim (empty
#   when absent), `b` = the body with fenced blocks stripped.
#   rc 0 = the read succeeded (empty stdout = no trusted comment)
#   rc 2 = TRANSIENT: the comment read or a permission read failed; stdout is EMPTY
#          (output is accumulated and printed once, so a failure never leaves a prefix)
#   The core does NOT validate `t`: the bodies view does not use it. Call it inside
#   `$(...)` — the memo lives for the one call, which is all a single read needs.
_trusted_verdict_core() {
  local issue="$1" repo="$2" raw logins login perm out=""
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
  logins="$(printf '%s\n' "$raw" | while IFS= read -r b64; do
      [[ -n "$b64" ]] || continue
      printf '%s' "$b64" | base64 -d | jq -r '.[0]'
    done | sort -u)"
  while IFS= read -r login; do
    [[ -n "$login" ]] || continue
    # `>/dev/null`, NOT `perm="$(...)"` — see the note on the resolver above.
    if ! _trusted_verdict_permission "$login" "$repo" >/dev/null; then
      return 2
    fi
  done <<<"$logins"

  while IFS= read -r b64; do
    [[ -n "$b64" ]] || continue
    local row author body created
    row="$(printf '%s' "$b64" | base64 -d)"
    author="$(printf '%s' "$row" | jq -r '.[0]')"
    body="$(printf '%s' "$row" | jq -r '.[1]')"
    created="$(printf '%s' "$row" | jq -r '.[2]')"
    perm="${_TRUSTED_VERDICT_PERM[$author]:-}"
    # An ABSENT memo entry is not a negative answer. Loop 1 above resolves exactly
    # this author set and returns 2 on any failure, so this is unreachable today —
    # which is precisely why it is worth pinning: `*) continue ;;` alone silently
    # merged "resolved as untrusted" with "never resolved at all", the collapse
    # this lib's own header forbids ("an unresolvable permission is not a negative
    # answer"), at the one place the header did not assert it. A future edit that
    # makes loop 1 partial — batching, caching, a per-author skip — would turn a
    # silent drop back on, and a dropped verdict is invisible by construction.
    if [[ -z "$perm" ]]; then
      echo "trusted-verdict: no memoized permission for '${author}' — the resolver did not run for this author. TRANSIENT, not untrusted." >&2
      return 2
    fi
    _trusted_verdict_is_trusted_perm "$perm" || continue
    body="$(printf '%s\n' "$body" | _trusted_verdict_strip_fences)"
    out="${out}$(jq -nc --arg t "$created" --arg b "$body" '{t: $t, b: $b}')"$'\n'
  done <<<"$raw"

  printf '%s' "$out"
  return 0
}

# trusted_verdict_bodies <issue-number> [repo]
#   stdout: the bodies of comments whose author is trusted, oldest-first, with
#           fenced code blocks stripped so a quoted template cannot arm a probe.
#   rc 0   = the read succeeded (an EMPTY result means "no trusted verdict yet",
#            which is a legitimate answer)
#   rc 2   = TRANSIENT: the comment read or a permission read failed. NOT evidence
#            of absence.
trusted_verdict_bodies() {
  local issue="$1" repo="${2:-jikig-ai/soleur}" records
  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  jq -r '.b' <<<"$records" || return 2
  return 0
}

# trusted_verdict_comments <issue-number> [repo]
#   stdout: one compact JSON object per trusted comment, oldest-first: {"t": <createdAt>, "b": <body, fences stripped>}.
#           Project with `jq -r '.b'` (the same text `trusted_verdict_bodies` returns) or sort on `.t`.
#   rc 0   = the read succeeded (empty stdout = no trusted comment yet, a legitimate answer)
#   rc 2   = TRANSIENT: the comment read or a permission read failed, OR a trusted comment's
#            `createdAt` is missing or not `YYYY-MM-DDTHH:MM:SSZ` (a caller sorts `t`
#            lexicographically and may hand it to `date -d`, which accepts natural
#            language). Never a default timestamp. stdout is EMPTY on rc 2.
trusted_verdict_comments() {
  local issue="$1" repo="${2:-jikig-ai/soleur}" records
  records="$(_trusted_verdict_core "$issue" "$repo")" || return 2
  [[ -n "$records" ]] || return 0
  if ! jq -e -s 'all(.[]; .t | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z"))' <<<"$records" >/dev/null 2>&1; then
    echo "trusted-verdict: a trusted comment on #${issue} has a missing or non-ISO createdAt. TRANSIENT, not a default timestamp." >&2
    return 2
  fi
  printf '%s\n' "$records"
  return 0
}
