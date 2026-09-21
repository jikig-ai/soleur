#!/usr/bin/env bash
# Lint: no CI-skip directive may reach the SQUASH commit message.
#
# GitHub honours `[skip ci]` and its siblings anywhere in a commit message, and it
# suppresses every `push`/`pull_request`-triggered workflow for that commit. On a
# squash merge the squash commit's message is assembled from the PR title, the PR
# body and the BRANCH COMMIT MESSAGES, so a token written in any of those three
# places becomes a live directive at merge time even though no individual commit
# looked wrong.
#
# WHY THIS IS NOT COVERED BY lint-bot-synthetic-statuses.sh: that lint reads
# `.github/workflows/*` for a token inside a `gh pr create` call — a bot authoring
# a PR. This one reads the human-authored prose that becomes a commit message. The
# token is the same; the surface is entirely different.
#
# WHY A PER-COMMIT CHECK CANNOT SEE IT: the failure is a property of the
# CONCATENATION. #8405's 30 commit messages were individually harmless; the squash
# message was 67,884 bytes and carried `[skip ci]` at line 658 — inside prose that
# was RULING OUT skip-ci as the cause of an earlier CI outage. Post-merge `ci.yml`,
# `version-bump-and-release.yml` (no GitHub Release) and `web-platform-release.yml`
# (no build/publish, and its deploy arm triggers on CI completing so it could never
# fire) were all skipped. The runs were ABSENT rather than queued, and the
# `dynamic`-event runs fired normally, which is the signature: a skip directive
# suppresses push/pull_request events only.
#
# This is the CI-directive twin of the auto-close-keyword scanner in
# ship/SKILL.md Phase 6, which already documents that GitHub's parser reads branch
# commit messages on a squash merge (#5463, closed twice by that same gap). Same
# mechanism, same surface, never generalised to CI directives until #8405 proved it.
#
# Quoting a directive in a post-mortem is legitimate and must stay possible, so the
# remedy is escaping, never silence — see the REMEDY block below.
#
# Usage:
#   lint-squash-ci-directives.sh                 # PR title+body for the current branch's PR, plus its commits
#   lint-squash-ci-directives.sh --base <ref>    # commits in <ref>..HEAD (default origin/main)
#   lint-squash-ci-directives.sh --text-file F   # scan F only (used by the test battery)
#   lint-squash-ci-directives.sh --pr N          # scan PR N's title+body and its commits
set -uo pipefail

# Canonical token set. Kept byte-identical to scripts/lint-bot-synthetic-statuses.sh
# so the two lints cannot drift on what GitHub actually honours; the test battery
# asserts that equality rather than trusting this comment.
DIRECTIVE_RE='\[(skip ci|ci skip|no ci|skip actions|actions skip)\]|\*\*\*NO_CI\*\*\*'

BASE="origin/main"
TEXT_FILE=""
PR_NUM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)      BASE="${2:?--base needs a ref}"; shift 2 ;;
    --text-file) TEXT_FILE="${2:?--text-file needs a path}"; shift 2 ;;
    --pr)        PR_NUM="${2:?--pr needs a number}"; shift 2 ;;
    -h|--help)   sed -n '1,40p' "$0"; exit 0 ;;
    *)           printf 'lint-squash-ci-directives: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

findings=0
scanned=0

# Report every hit with its surface and line so the author can find it in a
# 60,000-byte message. `grep -n` over a here-string keeps the line numbers
# relative to the surface being reported, which is what the author can act on.
scan_surface() {
  local label="$1" text="$2"
  scanned=$((scanned + 1))
  [[ -z "$text" ]] && return 0
  local hits
  hits="$(printf '%s\n' "$text" | grep -nEo ".{0,40}(${DIRECTIVE_RE}).{0,40}" || true)"
  [[ -z "$hits" ]] && return 0
  while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    printf 'FAIL [%s] %s\n' "$label" "$h"
    findings=$((findings + 1))
  done <<< "$hits"
}

if [[ -n "$TEXT_FILE" ]]; then
  if [[ ! -r "$TEXT_FILE" ]]; then
    printf 'lint-squash-ci-directives: cannot read --text-file %s\n' "$TEXT_FILE" >&2
    exit 2
  fi
  scan_surface "text-file:${TEXT_FILE}" "$(cat "$TEXT_FILE")"
else
  # PR title + body. A missing PR is not a failure: the gate also runs pre-PR,
  # where the commit messages are the only surface that exists yet.
  if [[ -z "$PR_NUM" ]]; then
    PR_NUM="$(gh pr view --json number --jq .number 2>/dev/null || true)"
  fi
  if [[ -n "$PR_NUM" ]]; then
    pr_json="$(gh pr view "$PR_NUM" --json title,body 2>/dev/null || true)"
    if [[ -n "$pr_json" ]]; then
      scan_surface "pr#${PR_NUM} title" "$(printf '%s' "$pr_json" | jq -r '.title // ""')"
      scan_surface "pr#${PR_NUM} body"  "$(printf '%s' "$pr_json" | jq -r '.body  // ""')"
    fi
  fi

  # Branch commit messages — the surface that made #8405 invisible. Each is scanned
  # under its own sha so the author knows which commit to reword.
  if git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
    while IFS= read -r sha; do
      [[ -z "$sha" ]] && continue
      scan_surface "commit ${sha:0:9}" "$(git log -1 --format=%B "$sha")"
    done < <(git rev-list "${BASE}..HEAD" 2>/dev/null || true)
  else
    printf 'lint-squash-ci-directives: base ref %s not found — commit surface NOT scanned\n' "$BASE" >&2
    printf '  Fetch it first (git fetch origin main); a partial scan is not a pass.\n' >&2
    exit 2
  fi
fi

# ADR-193 anti-vacuity floor: a scan that examined no surface must not report a
# pass. Printed to stderr and exited directly, never through a verdict helper.
#
# This fires on a branch with no PR and no commits since the base — which is a
# legitimate state, not a defect, so the message says which inputs were empty
# rather than implying the tree is broken. It still exits non-zero: "there was
# nothing to look at" and "I looked and it was clean" are different claims, and a
# caller that cannot tell them apart is the failure mode this floor exists for.
if [[ "$scanned" -lt 1 ]]; then
  printf 'lint-squash-ci-directives: ANTI-VACUITY — examined 0 surfaces, so there is no verdict to give.\n' >&2
  printf '  No PR was found for this branch (or --pr was not passed), AND %s..HEAD is empty.\n' "$BASE" >&2
  printf '  This is not a pass. Commit the work, or open the PR, then re-run.\n' >&2
  exit 1
fi

if [[ "$findings" -gt 0 ]]; then
  cat >&2 <<'REMEDY'

A CI-skip directive would reach the squash commit message.

GitHub honours these tokens ANYWHERE in a commit message and suppresses every
push/pull_request-triggered workflow for that commit — post-merge CI, the version
bump and GitHub Release, and the build/publish + deploy chain. The runs are never
created, so the failure looks like nothing happened rather than like an error.

Writing about a directive is legitimate; letting the literal token through is not.
Escape it instead of deleting the sentence:

  [skip<zero-width-space>ci]   ->  renders the same, is not the token
  `skip-ci`                    ->  hyphenated, never matched
  "the skip-ci family"         ->  name the class, not an instance

Then reword the offending commit (git rebase -i / git commit --amend) or edit the
PR title/body, and re-run this lint.
REMEDY
  printf '\n%s finding(s) across %s scanned surface(s).\n' "$findings" "$scanned" >&2
  exit 1
fi

printf 'lint-squash-ci-directives: OK — %s surface(s) scanned, no CI-skip directive.\n' "$scanned"
exit 0
