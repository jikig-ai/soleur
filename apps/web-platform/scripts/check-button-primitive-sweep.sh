#!/usr/bin/env bash
# check-button-primitive-sweep.sh
#
# feat-ui-action-feedback (#8917) Guard 2 sentinel.
#
# Enumerates every native `<button>` under apps/web-platform/components +
# apps/web-platform/app (*.tsx). Every match outside the primitive file itself
# must carry `data-button-exempt="<non-empty reason>"` on the same tag — the
# DOM attribute is the chokepoint, because a doc-only exemption list drifts
# from the DOM on day one (plan arch #1). Exemptions are bounded by the ~15%
# budget documented in components/ui/README.md.
#
# Baseline ratchet: NATIVE_BUTTON_BASELINE is the checked-in count of native
# `<button>` sites and may only decrease; regenerate via the grep below. A new
# native button — exempt-marked or not — pushes the count over baseline and
# reds this gate until the constant is regenerated, which keeps the bump
# review-visible instead of silent.
#
# Exits non-zero with a readable diff on violation.

set -euo pipefail

# Anchored at the app root: pathspecs below are relative to
# apps/web-platform. (NB: git grep pathspecs resolve relative to cwd — the
# check-workspace-members-write-sites.sh pattern of cd-ing to REPO_ROOT only
# works if the pathspecs include the apps/web-platform prefix.)
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

PRIMITIVE_PATH="components/ui/button.tsx"

# may only decrease; regenerate via the grep below. Post-sweep corpus is 52
# exempt-marked native sites (51 + the #9534 web-egress role=switch, whose
# track/thumb composite cannot reduce to Button geometry) — the baseline must
# equal the SHIPPED count, not the pre-migration corpus, or the ratchet can
# never fire.
NATIVE_BUTTON_BASELINE="${BUTTON_SWEEP_BASELINE:-52}"

# Space-separated git pathspecs relative to apps/web-platform; overridable
# for scratch-fixture verification (BUTTON_SWEEP_PATHS="sweep-fixture/*.tsx").
SWEEP_PATHS="${BUTTON_SWEEP_PATHS:-components/*.tsx app/*.tsx hooks/*.tsx}"

# -----------------------------------------------------------------------------
# Discovery: enumerate every native <button> site
# -----------------------------------------------------------------------------

read -r -a PATHSPEC <<< "$SWEEP_PATHS"
MATCHES="$(git grep -nE '<button([[:space:]>]|$)' -- "${PATHSPEC[@]}" 2>/dev/null || true)"

unmarked=""
unmarked_count=0
empty_reason=""
empty_reason_count=0
exempt_count=0
total=0

while IFS= read -r site; do
  [[ -z "$site" ]] && continue
  filepath="${site%%:*}"
  rest="${site#*:}"
  lineno="${rest%%:*}"
  [[ "$filepath" == "$PRIMITIVE_PATH" ]] && continue
  total=$((total + 1))

  # Slice the tag body: from the `<button` line until the line whose `>`
  # closes it (arrow `=>` inside props stripped first), capped at 20 lines —
  # a `<button` tag with >20 attribute lines would read as unmarked; that
  # shape doesn't occur in the corpus and an exempt marker that far down the
  # tag is a readability problem in its own right.
  tag_text=""
  while IFS= read -r l; do
    tag_text+="$l"$'\n'
    stripped="${l//=>/}"
    [[ "$stripped" == *">"* ]] && break
  done < <(sed -n "${lineno},$((lineno + 20))p" "$filepath")

  if grep -qE 'data-button-exempt[[:space:]]*=[[:space:]]*\{?[[:space:]]*"[^"]+"' <<< "$tag_text" || \
     grep -qE "data-button-exempt[[:space:]]*=[[:space:]]*\\{?[[:space:]]*'[^']+'" <<< "$tag_text"; then
    exempt_count=$((exempt_count + 1))
  elif grep -q 'data-button-exempt' <<< "$tag_text"; then
    empty_reason+="  $site"$'\n'
    empty_reason_count=$((empty_reason_count + 1))
  else
    unmarked+="  $site"$'\n'
    unmarked_count=$((unmarked_count + 1))
  fi
done <<< "$MATCHES"

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

violations=0

if (( unmarked_count > 0 )); then
  violations=$((violations + unmarked_count))
fi
if (( empty_reason_count > 0 )); then
  violations=$((violations + empty_reason_count))
fi
if (( total > NATIVE_BUTTON_BASELINE )); then
  violations=$((violations + 1))
fi

if (( violations > 0 )); then
  echo "FAIL: button primitive sweep sentinel (#8917 Guard 2)" >&2
  if (( unmarked_count > 0 )); then
    echo "" >&2
    echo "Found $unmarked_count native <button> site(s) with no data-button-exempt marker:" >&2
    echo "$unmarked" >&2
  fi
  if (( empty_reason_count > 0 )); then
    echo "" >&2
    echo "Found $empty_reason_count site(s) with an EMPTY data-button-exempt reason:" >&2
    echo "$empty_reason" >&2
  fi
  if (( total > NATIVE_BUTTON_BASELINE )); then
    echo "" >&2
    echo "Native <button> count $total exceeds NATIVE_BUTTON_BASELINE=$NATIVE_BUTTON_BASELINE." >&2
    echo "A new native button landed during the migration window; migrate it to" >&2
    echo "<Button> or regenerate the baseline deliberately (it may only decrease)." >&2
  fi
  echo "" >&2
  echo "Resolution paths:" >&2
  echo "  1. Migrate the site to <Button> (components/ui/button.tsx) and wire" >&2
  echo "     loading={pending} via usePendingAction for mutation sites." >&2
  echo "  2. For genuinely bespoke markup (toggle groups, cmdk items, composite" >&2
  echo "     content), mark the tag data-button-exempt=\"<non-empty reason>\" —" >&2
  echo "     bounded by the ~15% exemption budget." >&2
  echo "" >&2
  echo "  See components/ui/README.md and the feat-ui-action-feedback plan." >&2
  exit 1
fi

echo "OK: button primitive sweep sentinel (#8917 Guard 2) — $total native site(s), $exempt_count exempt (baseline $NATIVE_BUTTON_BASELINE)."
exit 0
