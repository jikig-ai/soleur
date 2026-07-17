#!/usr/bin/env bash
# sentry-create-gate.sh — is every planned CREATE explained by a resource block
# this PR actually added? (#6589)
#
# Usage: sentry-create-gate.sh <created-addresses-file> <added-resource-blocks-file>
#   <created-addresses-file>     newline list of `type.name` the plan will create
#                                (pure creates only — see the filter's header)
#   <added-resource-blocks-file> the `+` side of the PR's diff over
#                                apps/web-platform/infra/sentry/*.tf
#   exit 0: every create is matched by an added block (the normal add-a-monitor flow)
#   exit 1: at least one create has no added block -> report it
#
# ── WHY ────────────────────────────────────────────────────────────────────
# The delete direction was guarded and the create direction was not. Once the
# `-target=` allow-list is gone (#6589), the 4 formerly-untargeted import-only
# alerts come into scope and the plan universe is `state UNION config`. In that
# world an unreviewed CREATE is the same billing leak as an unreviewed delete,
# in mirror image: a monitor deleted in the Sentry UI (outside Terraform) or a
# failed import shows up as a create nobody asked for, and silently re-bills.
#
# The gate is DIFF-MATCHED, not a blanket acknowledgement. Adding a monitor —
# the common, correct flow — passes silently, because the plan's create is
# explained by the `resource` block the PR added. Only an UNEXPLAINED create
# fails. That distinction is the whole design: a blanket [ack-create] would fire
# on every add-a-monitor PR, train ack-blindness, and erode [ack-destroy] with
# it — the same reasoning that rejects a permanently-red destroy gate.
#
# Rationale for gating rather than documenting: this incident's etiology is
# literally "a known hole documented in prose in the workflow's own comment that
# nobody re-checked, for two months". Accepting a documented create-hole repeats
# that pattern one line lower.
#
# Behaviour is unit-tested by tests/scripts/test-sentry-create-gate.sh.
set -euo pipefail

created_file="${1:?usage: sentry-create-gate.sh <created-addresses-file> <added-blocks-file>}"
added_file="${2:?usage: sentry-create-gate.sh <created-addresses-file> <added-blocks-file>}"

for f in "$created_file" "$added_file"; do
  [[ -f "$f" ]] || { echo "[FAIL] no such file: $f" >&2; exit 1; }
done

unmatched=()
while IFS= read -r addr; do
  [[ -n "$addr" ]] || continue
  type="${addr%%.*}"
  name="${addr#*.}"
  # Anchor on the DECLARATION construct on an ADDED (`+`) diff line — never a
  # bare name. The .tf files carry resource names in comments, and a diff hunk
  # carries context lines; a bare-name grep would match the comment that
  # mentions the monitor, or an unchanged neighbouring line, and pass vacuously
  # while the unexplained create sails through. The `+` prefix is what makes
  # this "the PR added it" rather than "it exists somewhere".
  if ! grep -qE "^\+[[:space:]]*resource[[:space:]]+\"${type}\"[[:space:]]+\"${name}\"" "$added_file"; then
    unmatched+=("$addr")
  fi
done < "$created_file"

if [[ ${#unmatched[@]} -eq 0 ]]; then
  exit 0
fi

echo "::error::this PR's plan CREATES ${#unmatched[@]} Sentry resource(s) that no added resource block explains:" >&2
printf '::error::  %s\n' "${unmatched[@]}" >&2
echo "::error::A create with no matching added block means the plan and live Sentry have diverged — typically a monitor or rule deleted in the Sentry UI outside Terraform, or a failed import. Terraform will re-create it, and it will bill again. Investigate the divergence rather than acknowledging it; if the re-create is genuinely intended, add the resource block to a .tf file so the create is explained by the diff." >&2
exit 1
