#!/usr/bin/env bash
# Follow-through verification for #7985 — sentry Phase 3.4.
#
# `auth_per_user_loop` and `sandbox_startup_failure` cannot leave the deprecated
# `sentry_issue_alert` resource because their `event_unique_user_frequency_count`
# trigger is absent from `sentry_alert.trigger_conditions` at the pinned provider
# version.
#
# Upstream jianyuan/terraform-provider-sentry#950 FIXED this on 2026-09-09
# (PR #953, commit 0deba790) — but SEVEN DAYS AFTER the most recent release,
# v0.15.7 (2026-09-02). Terraform consumes releases, not branches, so the closed
# issue does not unblock us. This probe answers the only question that does:
# **has a release shipped that actually contains the fix?**
#
# Deliberately NOT "is there a release newer than v0.15.7". A version bump alone
# proves nothing — the maintainer could cut v0.15.8 off a commit that predates
# the fix, and a tag-only check would then report unblocked and send someone to
# write Terraform against a condition the provider still cannot express. The
# commit-containment check is the claim; the tag is just how we find candidates.
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (a release containing the fix exists; sweeper closes #7985)
#   1 = FAIL       (no such release yet; sweeper comments, leaves open)
#   * = TRANSIENT  (GitHub API unreachable / rate-limited; retry next sweep)
#
# Required env: GH_TOKEN (the sweeper provides it). No Sentry credential is
# needed — this reads a public upstream repository only.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Tracing echoes commands after expansion,
# so any token in an argv would be printed the moment it is used. This probe
# passes no secret on a command line, but the guard is cheap and the convention
# is repo-wide.
case "$-" in
  *x*) echo "REFUSING: shell xtrace is enabled; re-run without -x" >&2; exit 2 ;;
esac

UPSTREAM="jianyuan/terraform-provider-sentry"
PINNED="0.15.7"                                    # versions.tf at time of filing
FIX_SHA="0deba790"                                 # PR #953, the fix commit
FIX_SUBJECT="event unique user frequency count"    # corroborating subject match

api () { gh api "$@" 2>/dev/null; }

# --- candidate releases -------------------------------------------------------
RELEASES=$(api "repos/${UPSTREAM}/releases?per_page=30" --jq '.[] | select(.draft==false and .prerelease==false) | .tag_name')
if [[ -z "$RELEASES" ]]; then
  echo "TRANSIENT: could not list releases for ${UPSTREAM} (API unreachable or rate-limited)"
  exit 2
fi

# Strictly-newer than the pinned version. `sort -V` then drop everything up to
# and including PINNED, so an equal tag is not treated as newer.
NEWER=$(printf '%s\n%s\n' "$RELEASES" "v${PINNED}" \
        | sed 's/^v//' | sort -V -u \
        | awk -v p="$PINNED" 'seen{print} $0==p{seen=1}')

if [[ -z "$NEWER" ]]; then
  echo "FAIL: no release newer than v${PINNED}; latest is $(printf '%s\n' "$RELEASES" | sed 's/^v//' | sort -V | tail -1). Upstream #950 is fixed on main but unreleased."
  exit 1
fi

# --- containment: does any newer release actually carry the fix? --------------
for v in $NEWER; do
  CMP=$(api "repos/${UPSTREAM}/compare/v${PINNED}...v${v}" --jq '[.commits[] | "\(.sha) \(.commit.message | split("\n")[0])"] | join("\n")')
  if [[ -z "$CMP" ]]; then
    echo "TRANSIENT: compare v${PINNED}...v${v} returned nothing (API unreachable or tag missing)"
    exit 2
  fi
  if printf '%s' "$CMP" | grep -qi -e "^${FIX_SHA}" -e "$FIX_SUBJECT"; then
    echo "PASS: provider v${v} contains the #950 fix (${FIX_SHA}). Bump versions.tf to v${v}, then migrate auth_per_user_loop and sandbox_startup_failure via removed{} + import{} (never destroy/recreate a live rule)."
    exit 0
  fi
done

echo "FAIL: releases newer than v${PINNED} exist ($(printf '%s' "$NEWER" | tr '\n' ' ')) but none contains ${FIX_SHA}. A version bump alone does not unblock the migration."
exit 1
