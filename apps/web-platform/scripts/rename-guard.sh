#!/usr/bin/env bash
# rename-guard.sh — block `git mv` into gitleaks-allowlisted paths (#3160).
#
# gitleaks v8.24.2 evaluates path allowlists against the rename DESTINATION
# and does NOT re-scan the diff content against the source path. A
# `git mv server/X.ts test/__synthesized__/Y.ts` slips a real secret past
# the gate. This script blocks that pattern unless the operator opts in.
#
# Inputs (env):
#   BASE_SHA       — base of the diff range (REQUIRED)
#   HEAD_SHA       — head of the diff range (REQUIRED)
#   PR_LABELS      — JSON array of label names (default: '[]')
#   GITLEAKS_TOML  — path to the gitleaks config (default: .gitleaks.toml)
#
# Override paths (operator opts in to a rename-into-allowlist):
#   1. Add label `secret-scan-allow-rename` to the PR.
#   2. Include `Rename-Allowed-By: <name>` trailer in any commit in range.
#
# Exit codes:
#   0 — no renames into allowlist OR an override is present
#   1 — at least one rename into an allowlisted path with no override
#   2 — required input missing OR allowlist parser failed
#
# Trailer key is case-sensitive in `git log --format='%(trailers:key=…)'` so
# `Rename-Allowed-By` must be capitalized exactly that way (matches the
# Co-Authored-By convention).
set -euo pipefail

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
PR_LABELS="${PR_LABELS:-[]}"
GITLEAKS_TOML="${GITLEAKS_TOML:-.gitleaks.toml}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PARSER="${REPO_ROOT}/apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"

# Hoisted constants — keep in sync with the runbook
# (knowledge-base/engineering/operations/secret-scanning.md §Rename-laundering).
readonly OVERRIDE_LABEL="secret-scan-allow-rename"
readonly TRAILER_KEY="Rename-Allowed-By"

if [[ ! -f "${PARSER}" ]]; then
  echo "rename-guard: parser not found at ${PARSER}" >&2
  exit 2
fi

# Run the parser into a tmpfile so its exit code (3 = malformed, 4 = v8.25+
# schema) propagates instead of being swallowed by `mapfile < <(...)` process
# substitution. Without this, a parser failure produces ALLOW_RES=() and the
# guard silently exits 0 — disabling the whole gate.
TMP_PATHS="$(mktemp)"
trap 'rm -f "${TMP_PATHS}"' EXIT
if ! node "${PARSER}" "${GITLEAKS_TOML}" | jq -r '.[]' > "${TMP_PATHS}"; then
  echo "rename-guard: parser failed for ${GITLEAKS_TOML}" >&2
  exit 2
fi
mapfile -t ALLOW_RES < "${TMP_PATHS}"
# An EMPTY allowlist is a parser/config fault, not a clean bill of health: it
# disarms the entire gate while reporting success. The parser can return [] at
# exit 0 (e.g. if .gitleaks.toml ever moves to double-quoted TOML literals,
# which it does not read), so absence must fail CLOSED like a parser crash.
if [[ ${#ALLOW_RES[@]} -eq 0 ]]; then
  echo "rename-guard: allowlist parsed to ZERO paths — refusing to run blind." >&2
  echo "rename-guard: check parse-gitleaks-allowlists.mjs against .gitleaks.toml." >&2
  exit 2
fi

# `git diff BASE..HEAD --diff-filter=R` only sees a rename if both
# source-deleted and target-added survive across the WHOLE range. When the
# rename happened in a middle commit and surrounding commits are unrelated,
# the file appears as a plain add at HEAD and the rename is missed. Use
# `git log --diff-filter=R --name-status` to scan EACH commit's renames.
# `--no-renames` is OFF by default; `-M` rename detection is on by default
# for log/diff in modern git.
# Four things here are load-bearing, each closing a measured evasion:
#
#  -c core.quotePath=false — git QUOTES non-ASCII paths by default, emitting
#    "knowledge-base/project/plans/caf\303\251.md" (with the quotes). The
#    trailing quote defeats every `$`-anchored allowlist regex, so the target
#    reads as un-allowlisted and the pair is skipped entirely.
#
#  --diff-merges=first-parent — `git log --name-status` prints NO diff for a
#    merge commit by default, so a rename introduced during conflict resolution
#    (or by `commit --amend` on a merge) is invisible to the scan.
#
#  --find-renames=5% --find-copies=5% — at git's default ~50% similarity a
#    rename PLUS a content edit in the same commit is reported as D+A rather
#    than R, so appending one screen of text to the destination took the pair
#    out of scope. A low threshold keeps it classified as a rename.
#
#  --diff-filter=RC + /^[RC]/ — with copy detection on, the same laundering
#    shows up as C (copy) when the source survives; both must be scanned.
#
# `git log` (per commit) rather than `git diff BASE..HEAD` is deliberate and
# unchanged: it is what makes a multi-commit chain (outside -> allowlisted ->
# allowlisted) fire on its first hop.
renames=$(git -c core.quotePath=false log --diff-merges=first-parent \
  --diff-filter=RC \
  --find-renames=5% --find-copies=5% `# MUT:renamethresh` \
  --name-status --pretty=format: "${BASE_SHA}..${HEAD_SHA}" \
  | awk -F'\t' 'NF>=3 && $1 ~ /^[RC]/ { print }' || true)
if [[ -z "${renames}" ]]; then
  echo "rename-guard: no renames in PR; nothing to guard."
  exit 0
fi

# matched_allow_res <path> — prints EVERY allowlist regex matching <path>, one
# per line (empty output = the path is not allowlisted at all).
#
# Printing the whole matching SET, not just the first hit, is the correction for
# the defect this guard shipped with. "Allowlisted" is not a boolean in gitleaks:
# .gitleaks.toml carries ONE global `[allowlist]` (applying to every rule,
# including the inherited default pack) and EIGHTEEN per-rule
# `[[rules.allowlists]]` blocks (applying to one rule each), and
# parse-gitleaks-allowlists.mjs flattens all of them into a single deduped union
# with no rule provenance.
#
# So a file under `knowledge-base/project/learnings/` is exempt from exactly two
# rules and is genuinely SCANNED by every other one — measured: a synthesized
# GitHub PAT there is flagged, and the same token under `knowledge-base/plans/`
# is not. A boolean "is the source allowlisted?" test therefore treats a
# genuinely-scanned source as unscanned and exempts a real laundering rename.
#
# SOURCE and TARGET resolve through THIS ONE function against THIS ONE array —
# two separately-derived sets would be two assemblies and could drift.
matched_allow_res() {
  local path="$1" re
  for re in "${ALLOW_RES[@]}"; do
    if printf '%s' "${path}" | grep -qP "${re}"; then
      printf '%s\n' "${re}"
    fi
  done
}

violations=""
while IFS=$'\t' read -r status source target; do
  [[ -z "${target:-}" ]] && continue

  # Not landing in an allowlisted path — nothing to launder.
  dst_res="$(matched_allow_res "${target}")"
  [[ -z "${dst_res}" ]] && continue
  src_res="$(matched_allow_res "${source}")"

  # EXEMPT iff the destination's exemption scope is a SUBSET of the source's —
  # every rule the destination is exempt from, the source was already exempt
  # from too. Only then does the rename create no newly-unscanned surface.
  #
  # This is the archive-kb shape: compound `git mv`s plans/specs into their own
  # `archive/` subdirectory on every one-shot run and BOTH sides match the same
  # regex set, so the subset holds and the rename is exempt. Without it the
  # guard fires on a class that cannot be a laundering vector, which is why
  # `secret-scan-allow-rename` had become effectively mandatory rather than an
  # exceptional operator opt-in (#5095, #5097). Pre-applying that label would
  # instead disarm the guard for the WHOLE PR; this is per rename pair.
  #
  # The DIRECTION is the correction. A source exempt from two rules moving to a
  # path exempt from all of them WIDENS the exemption — that is laundering, and
  # the boolean "is the source allowlisted?" test this replaces passed it.
  subset=1                                                            # MUT:scopesubset
  while IFS= read -r dre; do                                          # MUT:scopesubset
    [[ -z "${dre}" ]] && continue                                     # MUT:scopesubset
    grep -qxF -- "${dre}" <<<"${src_res}" || { subset=0; break; }     # MUT:scopesubset
  done <<<"${dst_res}"                                                # MUT:scopesubset
  if [[ "${subset}" -eq 1 ]]; then                                    # MUT:scopesubset
    continue                                                          # MUT:scopesubset
  fi                                                                  # MUT:scopesubset

  matched_re="$(printf '%s' "${dst_res}" | head -1)"
  violations+="${source} -> ${target} (matches /${matched_re}/)"$'\n'
done <<<"${renames}"

if [[ -z "${violations}" ]]; then
  echo "rename-guard: OK — no renames target allowlisted paths."
  exit 0
fi

# Override 1: PR has the label.
if printf '%s' "${PR_LABELS}" | jq -e --arg label "${OVERRIDE_LABEL}" 'index($label)' >/dev/null 2>&1; then
  echo "::notice::rename-guard suppressed by '${OVERRIDE_LABEL}' label."
  printf 'Renames into allowlisted paths (label-suppressed):\n%s' "${violations}"
  exit 0
fi

# Override 2: any commit in range carries the trailer.  # MUT:trailer
trailers=$(git log --format="%(trailers:key=${TRAILER_KEY},valueonly)" "${BASE_SHA}..${HEAD_SHA}" | tr -d '\r')  # MUT:trailer
trailers_clean=$(printf '%s' "${trailers}" | grep -v '^[[:space:]]*$' || true)  # MUT:trailer
if [[ -n "${trailers_clean}" ]]; then  # MUT:trailer
  # Strip CR/LF before echoing into annotations (log-injection guard).  # MUT:trailer
  safe="${trailers_clean//[$'\n\r']/, }"  # MUT:trailer
  echo "::notice::rename-guard suppressed by ${TRAILER_KEY} trailer: ${safe}"  # MUT:trailer
  printf 'Renames into allowlisted paths (trailer-suppressed):\n%s' "${violations}"  # MUT:trailer
  exit 0  # MUT:trailer
fi  # MUT:trailer

echo "::error::Rename(s) into gitleaks-allowlisted paths require either the '${OVERRIDE_LABEL}' label OR a '${TRAILER_KEY}: <name>' commit trailer." >&2
printf '%s' "${violations}" >&2
exit 1
