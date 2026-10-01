#!/usr/bin/env bash
# Sweep-completeness gate (#5269): fail a PR that changes a sibling-set's
# trigger file but leaves a registered dependent unchanged. Closes the
# cross-file-drift class (2026-06-11) and the missed-sibling-test class
# (2026-06-13 session error #6) mechanically, so the prose rule
# hr-write-boundary-sentinel-sweep-all-write-sites no longer relies on a
# reviewer re-catching it every time.
#
# Reads .github/enforcement-contracts.json (sibling_sets[]) and the PR's
# changed-file list, then enforces, per set:
#   FAIL iff (any trigger in changeset) AND (any dependent NOT in changeset).
# Editing a dependent alone is allowed (no false positive on a lone fix).
#
# Repo convention: `set -uo pipefail` (NO -e) so the script enumerates ALL
# violations before exiting, instead of aborting on the first.
#
# Usage:
#   check-sweep-completeness.sh [REGISTRY] [CHANGESET]
#     REGISTRY   enforcement-contracts.json (default: .github/enforcement-contracts.json)
#     CHANGESET  file of newline-separated changed paths, or "-" for stdin.
#                If omitted, derived from `gh pr diff "$PR_NUMBER" --name-only`.

set -uo pipefail

REGISTRY="${1:-.github/enforcement-contracts.json}"
CHANGESET_SRC="${2:-}"

# --- Registry parse (fail-closed on missing / malformed) ---
if [[ ! -f "$REGISTRY" ]]; then
  echo "::error::sweep-completeness: registry not found: $REGISTRY"
  exit 1
fi
if ! jq empty "$REGISTRY" 2>/dev/null; then
  echo "::error::sweep-completeness: malformed registry JSON: $REGISTRY"
  exit 1
fi

# --- Resolve changeset (fail-closed when unobtainable) ---
changed=""
if [[ -n "$CHANGESET_SRC" ]]; then
  if [[ "$CHANGESET_SRC" == "-" ]]; then
    changed=$(cat)
  elif [[ ! -f "$CHANGESET_SRC" ]]; then
    # A missing/unreadable changeset file is unprovable, not "0 changes" —
    # fail closed (an explicitly empty-but-present file stays a legit exit 0).
    echo "::error::sweep-completeness: changeset file not found: $CHANGESET_SRC — fail-closed"
    exit 1
  else
    changed=$(cat "$CHANGESET_SRC")
  fi
else
  if [[ -z "${PR_NUMBER:-}" ]]; then
    echo "::error::sweep-completeness: no changeset source (arg 2 unset and PR_NUMBER unset) — cannot prove the invariant; fail-closed"
    exit 1
  fi
  # `gh pr diff --name-only` reads the PR *diff* endpoint, which GitHub caps at 300
  # files: past that it returns HTTP 406 "the diff exceeded the maximum number of
  # files (300)" and this guard failed closed on every large PR — unpassable by the
  # author, since the only remedy was to make the PR smaller. GitHub's own 406 body
  # names the fix ("Consider using 'List pull requests files' API"), so try the
  # paginated files endpoint FIRST and keep the diff call only as a fallback for
  # environments where the API path is unavailable.
  #
  # Fail-closed is preserved: an empty result from BOTH paths still exits 1. Only the
  # could-not-measure case changes, and it changes from "always red above 300 files"
  # to "actually measured".
  # GATE ON EXIT STATUS, NOT ON EMPTINESS. On a 404 `gh api` writes the JSON error
  # body to STDOUT and exits non-zero, so a `$(... || echo "")` capture yields a
  # NON-EMPTY string and an emptiness test reads it as a valid changeset -- the
  # could-not-measure/measured-clean collapse, which made a bogus PR number report
  # "no violations" instead of failing closed. Measured while writing this fix.
  changed=""
  if api_out=$(gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/files" --paginate \
                 --jq '.[].filename' 2>/dev/null); then
    changed="$api_out"
  fi
  if [[ -z "$changed" ]]; then
    if diff_out=$(gh pr diff "$PR_NUMBER" --name-only 2>/dev/null); then
      changed="$diff_out"
    fi
  fi
  # A path that still looks like an API error body is not a changeset. Belt-and-braces
  # against a future `gh` that exits 0 on a structured error.
  if printf '%s\n' "$changed" | grep -qE '^\{"message":'; then
    echo "::error::sweep-completeness: changeset derivation returned an API error body, not filenames — fail-closed"
    exit 1
  fi
  if [[ -z "$changed" ]]; then
    echo "::error::sweep-completeness: could not derive changeset for PR $PR_NUMBER from either the files API or 'gh pr diff --name-only' — fail-closed"
    exit 1
  fi
fi
# Normalize: strip CR, drop blank lines.
changed=$(printf '%s\n' "$changed" | tr -d '\r' | grep -v '^[[:space:]]*$' || true)

# --- Pass 1: registry self-consistency (anti-rot) ---
integrity_errors=()
checked=0
while IFS= read -r set; do
  [[ -z "$set" ]] && continue
  checked=$((checked + 1))
  name=$(jq -r '.name // "(unnamed)"' <<<"$set")
  mapfile -t triggers < <(jq -r '.trigger[]? // empty' <<<"$set")
  mapfile -t deps < <(jq -r '.dependents[]? // empty' <<<"$set")
  for p in "${triggers[@]}" "${deps[@]}"; do
    [[ -f "$p" ]] || integrity_errors+=("set '$name' references missing path: $p")
  done
  if [[ "${#triggers[@]}" -eq 0 ]]; then
    integrity_errors+=("set '$name' has no triggers (a set with no trigger can never fire)")
  fi
  if [[ "${#deps[@]}" -eq 0 ]]; then
    integrity_errors+=("set '$name' has no dependents (remove the set or add dependents)")
  fi
done < <(jq -c '.sibling_sets[]? // empty' "$REGISTRY")

if [[ "${#integrity_errors[@]}" -gt 0 ]]; then
  echo "::error::sweep-completeness: registry is inconsistent with the working tree:"
  printf '  - %s\n' "${integrity_errors[@]}"
  echo "Update $REGISTRY so every trigger/dependent path exists and every set has dependents."
  exit 1
fi

# --- Pass 2: evaluate each set against the changeset ---
in_changed() { grep -Fxq "$1" <<<"$changed"; }

violations=()
while IFS= read -r set; do
  [[ -z "$set" ]] && continue
  name=$(jq -r '.name // "(unnamed)"' <<<"$set")
  reason=$(jq -r '.reason // ""' <<<"$set")
  mapfile -t triggers < <(jq -r '.trigger[]? // empty' <<<"$set")
  mapfile -t deps < <(jq -r '.dependents[]? // empty' <<<"$set")

  triggered=0
  for t in "${triggers[@]}"; do
    if in_changed "$t"; then triggered=1; break; fi
  done
  [[ "$triggered" -eq 0 ]] && continue

  missing=()
  for d in "${deps[@]}"; do
    in_changed "$d" || missing+=("$d")
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    violations+=("$name")
    echo "::error::sweep-completeness: set '$name' — trigger changed but these dependents were not:"
    printf '  - %s\n' "${missing[@]}"
    [[ -n "$reason" ]] && echo "  reason: $reason"
  else
    echo "[ok] sweep-completeness: set '$name' — trigger changed, all ${#deps[@]} dependent(s) present"
  fi
done < <(jq -c '.sibling_sets[]? // empty' "$REGISTRY")

if [[ "${#violations[@]}" -gt 0 ]]; then
  echo "::error::sweep-completeness: ${#violations[@]} sibling set(s) incomplete: ${violations[*]}"
  exit 1
fi

echo "[ok] sweep-completeness: $checked sibling set(s) checked, no violations"
exit 0
