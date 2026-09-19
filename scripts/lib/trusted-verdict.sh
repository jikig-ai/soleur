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
# token). One call per DISTINCT author, memoized, so a thread with many comments
# from one author costs one request.
#
# SOURCED, never executed: no top-level `exit` (a sourced `exit` terminates the
# SOURCING parent), no `set -e`. Callers keep their own exit semantics.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/trusted-verdict.sh"
#   if ! bodies="$(trusted_verdict_bodies 5733)"; then exit 2; fi   # 2 = TRANSIENT
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

# Memo table: login -> permission string. Declared once; `declare -gA` so it
# survives being sourced from inside a function.
declare -gA _TRUSTED_VERDICT_PERM 2>/dev/null || true

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

# trusted_verdict_bodies <issue-number> [repo]
#   stdout: the bodies of comments whose author is trusted, oldest-first, with
#           fenced code blocks stripped so a quoted template cannot arm a probe.
#   rc 0   = the read succeeded (an EMPTY result means "no trusted verdict yet",
#            which is a legitimate answer)
#   rc 2   = TRANSIENT: the comment read or a permission read failed. NOT evidence
#            of absence.
trusted_verdict_bodies() {
  local issue="$1" repo="${2:-jikig-ai/soleur}" raw logins login perm out=""
  # `.author.login` AND `.body`, tab-joined. A comment with no author cannot be
  # attributed and is dropped by the `select`, so it can never carry a verdict.
  if ! raw="$(gh issue view "$issue" --repo "$repo" --json comments --jq '
        .comments[]
        | select((.author.login // "") != "")
        | [(.author.login), (.body // "")]
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
    local pair author body
    pair="$(printf '%s' "$b64" | base64 -d)"
    author="$(printf '%s' "$pair" | jq -r '.[0]')"
    body="$(printf '%s' "$pair" | jq -r '.[1]')"
    perm="${_TRUSTED_VERDICT_PERM[$author]:-}"
    case "$perm" in
      admin|maintain|write) ;;
      *) continue ;;
    esac
    # Drop fenced blocks so a quoted template cannot arm the probe.
    body="$(printf '%s\n' "$body" | awk '/^[[:space:]]*```/ { f = !f; next } !f { print }')"
    out="${out}${body}"$'\n'
  done <<<"$raw"

  printf '%s' "$out"
  return 0
}
