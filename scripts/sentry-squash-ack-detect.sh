#!/usr/bin/env bash
# sentry-squash-ack-detect.sh — will a pre-staged [ack-destroy] survive into the
# squash commit? (#6589)
#
# Usage: sentry-squash-ack-detect.sh < <newline-json-array-of-commit-messages>
#   stdin: a JSON array of the PR's branch commit messages, oldest first —
#          exactly `gh api repos/:owner/:repo/pulls/N/commits --jq '[.[].commit.message]'`
#   exit 0: the composed squash body carries a line-anchored [ack-destroy]
#   exit 1: it does not
#
# ── WHY THIS EXISTS ────────────────────────────────────────────────────────
# The apply-side destroy gate reads the MERGE COMMIT message. The PR-side gate
# runs before that commit exists, so it must answer a prediction: "if this PR is
# squash-merged now, will the resulting commit message satisfy the apply gate?"
# Answering it by grepping the raw commit messages is WRONG in a way that would
# green this gate and red the apply — #6074 with extra steps.
#
# GitHub composes a squash body (under squash_merge_commit_message=COMMIT_MESSAGES)
# by taking each branch commit, prefixing its SUBJECT with "* ", carrying its BODY
# lines verbatim, and joining commits with a blank line. Consequences:
#
#   [ack-destroy] as a commit BODY line  -> stays at line-start in the squash
#                                           body -> MATCHES the anchored regex
#   [ack-destroy] as a commit SUBJECT    -> becomes "* [ack-destroy]" -> does
#                                           NOT match (the anchor is destroyed
#                                           by the bullet GitHub adds)
#
# So we reconstruct the body and test the artifact, rather than testing the
# inputs and hoping. The caller is responsible for verifying that the repo's
# squash_merge_commit_message is actually COMMIT_MESSAGES — this script's
# emulation is only valid under that setting.
#
# The regex below is the canonical [ack-destroy] literal, byte-identical to the
# three apply-* workflows and the three destroy-guard counter tests. It is pinned
# here as the 7th site by tests/scripts/test-destroy-guard-regex-parity.sh —
# drift between this file and the apply gate is the #6074 reintroduction path,
# so it is checked mechanically rather than by review.
#
# Behaviour is unit-tested by tests/scripts/test-sentry-squash-ack-detect.sh.
set -euo pipefail

messages_json=$(cat)

# Reconstruct GitHub's squash body. `.[0]` is the subject; `.[1:]` are body lines
# carried verbatim. Commits joined by a blank line, mirroring the UI prefill.
squash_body=$(printf '%s' "$messages_json" | jq -r '
  [ .[]
    | split("\n")
    | "* " + .[0] + (if length > 1 then "\n" + (.[1:] | join("\n")) else "" end)
  ] | join("\n\n")
')

# Canonical [ack-destroy] regex (see header).
if [[ "$squash_body" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
  exit 0
fi
exit 1
