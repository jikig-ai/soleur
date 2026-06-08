#!/usr/bin/env bash
# tweet-eligibility.sh <pr-number>
#
# Deterministic, fail-closed eligibility filter for ship-tweet drafting (#5021).
# Decides whether a merged PR may be converted into a *draft* short-form X post.
# It is the brand-critical floor: a forbidden PR (security/infra/internal/
# non-product) must never reach the operator's approval queue.
#
# Eligible (exit 0, prints "eligible") ONLY when ALL hold:
#   - PR title starts with a conventional-commit feature prefix (`feat(`,
#     `feat:`, or `feat!`) — the real "this is a user-facing feature" signal at
#     merge time (the repo does not apply a `type/feature`/`user-facing` label
#     to PRs; verified against live labels at /work, #5021).
#   - PR carries the `app:web-platform` label — it touches the product users see.
#   - PR carries NONE of the deny labels.
#   - PR touches NO deny-path glob.
#
# Excluded (exit 1, prints "excluded: <reason>" on stderr) on ANY of: a deny
# label, a deny path, a missing allow signal, a `gh` error, or empty metadata.
# Deny checks short-circuit to excluded REGARDLESS of the allow-set (a
# feat()+app:web-platform+type/security PR is excluded). Read-only; never writes
# or posts. Any uncertainty fails closed.
#
# Labels/paths via `gh pr diff <n> --name-only` (non-truncating, matches
# postmerge) and `gh pr view <n> --json labels,title,url`.
set -euo pipefail

PR="${1:-}"
if [[ -z "$PR" || ! "$PR" =~ ^[0-9]+$ ]]; then
  echo "excluded: missing or non-numeric PR number" >&2
  exit 1
fi

# --- Deny sets (single source of truth) -------------------------------------
# Real repo labels (verified live at #5021). The plan's `infra`/`internal`/
# `dark-launch`/`security` names do not exist here; these are the live mappings.
DENY_LABELS=(type/security security/leak-suspected infra-drift no-auto-ship)

# Deny path globs as extended-regex fragments matched against each changed path.
# Cover auth, migrations, secrets/credentials, and CI/infra surfaces.
DENY_PATH_RES=(
  '(^|/)migrations/'          # DB migrations (any app)
  '(^|/)\(auth\)/'            # Next.js (auth) route group
  '(^|/)auth([./_-]|$)'       # auth dir or auth.* file (not "oauth"/"author")
  '(^|/)\.env'                # .env / .env.example
  '(^|/)\.github/'            # CI workflows
  '(^|/)infra/'               # infrastructure-as-code dirs
  '\.tf$'                     # terraform files
  '(^|/)cloud-init'           # cloud-init configs
  '(^|/)Dockerfile'           # container build
  '(secret|credential|doppler)' # secrets / credential helpers
)

# --- Fetch metadata (fail-closed on any gh error / empty) -------------------
meta=$(gh pr view "$PR" --json labels,title,url 2>/dev/null) || {
  echo "excluded: gh pr view failed for #$PR" >&2
  exit 1
}
[[ -n "$meta" ]] || { echo "excluded: empty gh metadata for #$PR" >&2; exit 1; }

title=$(jq -r '.title // ""' <<<"$meta")
labels=$(jq -r '.labels[]?.name // empty' <<<"$meta")

paths=$(gh pr diff "$PR" --name-only 2>/dev/null) || {
  echo "excluded: gh pr diff failed for #$PR" >&2
  exit 1
}

[[ -n "$title" ]] || { echo "excluded: empty PR title for #$PR" >&2; exit 1; }

# --- Deny labels (short-circuit, regardless of allow-set) -------------------
while IFS= read -r lbl; do
  [[ -z "$lbl" ]] && continue
  for d in "${DENY_LABELS[@]}"; do
    if [[ "$lbl" == "$d" ]]; then
      echo "excluded: deny label '$lbl' on #$PR" >&2
      exit 1
    fi
  done
done <<<"$labels"

# --- Deny paths (short-circuit) ---------------------------------------------
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  for re in "${DENY_PATH_RES[@]}"; do
    if [[ "$p" =~ $re ]]; then
      echo "excluded: deny path '$p' on #$PR (matched /$re/)" >&2
      exit 1
    fi
  done
done <<<"$paths"

# --- Require allow-set: feat( title AND app:web-platform --------------------
feat_re='^feat(\(|!|:)'
if [[ ! "$title" =~ $feat_re ]]; then
  echo "excluded: not a feature — title must start with 'feat(' (#$PR: '$title')" >&2
  exit 1
fi
if ! grep -qx 'app:web-platform' <<<"$labels"; then
  echo "excluded: missing 'app:web-platform' label on #$PR (not a product surface)" >&2
  exit 1
fi

echo "eligible"
exit 0
