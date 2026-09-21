#!/usr/bin/env bash
# Follow-through verification for #7985 — sentry Phase 3.4.
#
# `auth_per_user_loop` and `sandbox_startup_failure` cannot carry a native trigger
# because their `event_unique_user_frequency_count` trigger is absent from
# `sentry_alert.trigger_conditions` at the pinned provider version. (Until #8451
# they sat on the deprecated `sentry_issue_alert`; they are now frozen
# `sentry_alert` blocks — see below.)
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
# PASS MEANS CONVERTED, NOT RELEASED (#8451). Since #8451 the two rules are
# adopted as `sentry_alert` and FROZEN (`legacy_trigger_conditions` +
# `ignore_changes = all`). A release that contains the fix is the moment the work
# becomes POSSIBLE, not the moment it is done — if this probe passed then, the
# sweeper would close #7985 and the freeze would have no remaining owner. So the
# repo's own state is checked FIRST, and a release alone reports FAIL "unblocked".
#
# Exit semantics (per sweep-followthroughs.sh contract):
#   0 = PASS       (both rules' blocks declare a native trigger, with no
#                   legacy_trigger_conditions and no `ignore_changes = all`;
#                   sweeper closes #7985)
#   1 = FAIL       (not converted: either no fixed release yet, or one exists and
#                   the conversion is owed; sweeper comments, leaves open)
#   * = TRANSIENT  (GitHub API unreachable / rate-limited; retry next sweep)
#
# Required env: GH_TOKEN (the sweeper provides it). No Sentry credential is
# needed — this reads a public upstream repository only.

set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Tracing echoes commands after expansion,
# so any token in an argv would be printed the moment it is used. This probe
# passes no secret on a command line, but the guard is cheap and the convention
# is repo-wide.
#
# THIRD-PARTY CONTENT NOTE (hr-third-party-content-grep-on-undertaking). This is the second
# probe whose stdout republishes bytes controlled by a THIRD PARTY -- upstream tag names from
# jianyuan/terraform-provider-sentry -- into a PUBLIC issue comment. The containment is the
# sweeper's `sanitize_probe_output`, which neutralises `<!--`, collapses five-or-more backtick
# runs, and defuses the `### Sweeper run:` / `### Sweeper reopen:` heading prefixes. That is
# load-bearing here and not incidental: a crafted upstream tag reaching the comment verbatim
# could otherwise forge a PASS heading the closed-set readback accepts. Do not print upstream
# bytes through any path that bypasses it.
case "$-" in
  *x*) echo "REFUSING: shell xtrace is enabled; re-run without -x" >&2; exit 2 ;;
esac

UPSTREAM="jianyuan/terraform-provider-sentry"
PINNED="0.15.7"                                    # versions.tf at time of filing
FIX_SHA="0deba790"                                 # PR #953, the fix commit
FIX_SUBJECT="event unique user frequency count"    # corroborating subject match

api () { gh api "$@" 2>/dev/null; }

# --- converted? (checked first: after the bump PINNED is stale, so the release
# comparison below is no longer meaningful) -------------------------------------
# Checked BY ADDRESS across every .tf in the root, not by grepping one file: a
# frozen block moved to another file, or deleted outright, must not read as
# "converted" (the sweeper would close #7985 with the freeze still standing, or
# with a paging rule gone).
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/apps/web-platform/infra/sentry"
shopt -s nullglob
TF_FILES=("$ROOT_DIR"/*.tf)
shopt -u nullglob
if [[ ${#TF_FILES[@]} -eq 0 ]]; then
  echo "FAIL: no .tf files under ${ROOT_DIR}; cannot judge the conversion (the Sentry root moved or the checkout is incomplete)."
  exit 1
fi
FROZEN=(auth_per_user_loop sandbox_startup_failure)
block_of() { # $1=label -> that sentry_alert block's body across all .tf files
  awk -v hdr="resource \"sentry_alert\" \"$1\" {" '
    index($0, hdr) == 1 { on = 1 }
    on { print }
    on && /^}$/ { on = 0 }
  ' "${TF_FILES[@]}"
}
missing=(); still_frozen=()
for label in "${FROZEN[@]}"; do
  body=$(block_of "$label")
  if [[ -z "$body" ]]; then missing+=("$label"); continue; fi
  if grep -qE '^[[:space:]]*legacy_trigger_conditions[[:space:]]*=' <<<"$body" \
     || grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*all([^[:alnum:]_]|$)' <<<"$body" \
     || ! grep -qE 'event_unique_user_frequency_count[[:space:]]*=' <<<"$body"; then
    still_frozen+=("$label")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "FAIL: no resource \"sentry_alert\" block for ${missing[*]} in ${ROOT_DIR}/*.tf. That is not a conversion: the paging rule was deleted, renamed, or moved out of this root. Resolve before closing #7985."
  exit 1
fi
if [[ ${#still_frozen[@]} -eq 0 ]]; then
  echo "PASS: converted — both rules declare a native event_unique_user_frequency_count trigger, with no legacy_trigger_conditions and no ignore_changes = all."
  exit 0
fi

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
    echo "FAIL: ACTION REQUIRED — unblocked: provider v${v} contains ${FIX_SHA}; bump versions.tf, convert auth_per_user_loop and sandbox_startup_failure to native trigger_conditions, drop legacy_trigger_conditions and ignore_changes = all (the plan must show 0 changes). See #7985's exit checklist."
    exit 1
  fi
done

echo "FAIL: releases newer than v${PINNED} exist ($(printf '%s' "$NEWER" | tr '\n' ' ')) but none contains ${FIX_SHA}. A version bump alone does not unblock the migration."
exit 1
