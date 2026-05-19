#!/usr/bin/env bash
# parse-override.sh — detect and validate skill-security override artifacts.
#
# Scans `git diff <base>...<head> --diff-filter=A` for newly-added files
# matching `^knowledge-base/security/skill-overrides/\d{4}-\d{2}-\d{2}-.+\.md$`,
# validates each artifact's frontmatter against override-artifact-schema.json,
# checks rule_pack_sha256 freshness against current manifest, validates the
# slug regex.
#
# Stdout: JSON {matched, invalid_schema, stale_findings}.
# Exit 0 if all matched artifacts validate; exit 1 otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$SKILL_DIR/references/rules/manifest.yaml"
SCHEMA="$SKILL_DIR/references/override-artifact-schema.json"

BASE="main"
HEAD="HEAD"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Path regex: YYYY-MM-DD-<slug>.md under the override directory.
path_re='^knowledge-base/security/skill-overrides/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]*\.md$'
slug_re='^[a-z][a-z0-9-]*$'

# Compute current manifest SHA for freshness check.
current_manifest_sha="$(sha256sum "$MANIFEST" 2>/dev/null | cut -d' ' -f1 || echo "")"

matched='[]'
invalid='[]'
stale='[]'

# Enumerate added files in the diff.
if ! mapfile -t added < <(git diff "$BASE...$HEAD" --name-only --diff-filter=A 2>/dev/null); then
  added=()
fi

for path in "${added[@]}"; do
  [ -z "$path" ] && continue
  if ! [[ "$path" =~ $path_re ]]; then
    continue
  fi
  # Extract slug from filename (date-prefix stripped).
  base="$(basename "$path" .md)"
  slug="${base#????-??-??-}"
  if ! [[ "$slug" =~ $slug_re ]]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "slug regex violation" '. + [{path: $p, reason: $r}]')"
    continue
  fi

  # Read frontmatter (between leading --- and second ---).
  if [ ! -f "$path" ]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "file not found in working tree" '. + [{path: $p, reason: $r}]')"
    continue
  fi
  fm="$(awk '
    BEGIN { phase = "pre" }
    phase == "pre" && /^---[[:space:]]*$/ { phase = "fm"; next }
    phase == "fm"  && /^---[[:space:]]*$/ { phase = "done"; exit }
    phase == "fm"  { print }
  ' "$path")"

  required_fields=(skill source findings_json justification approver scanner_version rule_pack_sha256 verdict timestamp)
  missing=""
  for f in "${required_fields[@]}"; do
    if ! echo "$fm" | grep -qE "^${f}:[[:space:]]"; then
      missing+="$f "
    fi
  done
  if [ -n "$missing" ]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "missing fields: ${missing}" '. + [{path: $p, reason: $r}]')"
    continue
  fi

  # Verdict must be HIGH-RISK or REVIEW.
  verdict="$(echo "$fm" | awk -F: '/^verdict:/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/"|'"'"'/, "", $2); print $2; exit }')"
  case "$verdict" in
    HIGH-RISK|REVIEW) ;;
    *)
      invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "verdict must be HIGH-RISK or REVIEW (got: $verdict)" '. + [{path: $p, reason: $r}]')"
      continue
      ;;
  esac

  # Schema enforcement: approver must be email-shaped, scanner_version semver,
  # timestamp ISO-8601 (data-integrity review F1). The JSON schema declares
  # these `format:` constraints but no validator ran — enforce them here.
  field_value() {
    echo "$fm" | awk -v fld="$1" '
      $0 ~ "^"fld":" {
        # Capture everything after the first colon (preserve embedded :).
        sub("^"fld":[[:space:]]*", "")
        gsub(/^["'"'"']|["'"'"']$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        print
        exit
      }'
  }
  approver="$(field_value approver)"
  scanner_version="$(field_value scanner_version)"
  timestamp="$(field_value timestamp)"
  if ! [[ "$approver" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "approver must be email-shaped (got: $approver)" '. + [{path: $p, reason: $r}]')"
    continue
  fi
  if ! [[ "$scanner_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "scanner_version must be semver (got: $scanner_version)" '. + [{path: $p, reason: $r}]')"
    continue
  fi
  if ! [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:?[0-9]{2})$ ]]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "timestamp must be ISO-8601 (got: $timestamp)" '. + [{path: $p, reason: $r}]')"
    continue
  fi

  # PII guard (data-integrity F3): reject artifacts whose frontmatter or body
  # contain a raw email pattern OUTSIDE the approver field (PR author
  # copy-pasted from unredacted stdout instead of using the path-form).
  # Filter the approver line at any line position; only THAT field is
  # allowed to contain a literal email.
  artifact_text="$(awk -v approver_line="approver:" '
    index($0, approver_line) == 1 { next }
    /^[[:space:]]*approver:/      { next }
    { print }
  ' "$path")"
  if echo "$artifact_text" | grep -qE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "artifact contains raw email pattern outside approver field — use path-form findings_json (point to redacted .scan-meta.json) instead of inline" '. + [{path: $p, reason: $r}]')"
    continue
  fi

  # Freshness: rule_pack_sha256 prefix must match current manifest sha (≥8 chars).
  artifact_sha="$(echo "$fm" | awk -F: '/^rule_pack_sha256:/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/"|'"'"'/, "", $2); print $2; exit }')"
  prefix_len="${#artifact_sha}"
  if [ "$prefix_len" -lt 8 ]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "rule_pack_sha256 prefix too short (need >=8 chars)" '. + [{path: $p, reason: $r}]')"
    continue
  fi
  if [ "${current_manifest_sha:0:$prefix_len}" != "$artifact_sha" ]; then
    stale="$(echo "$stale" | jq --arg p "$path" --arg art "$artifact_sha" --arg cur "${current_manifest_sha:0:$prefix_len}" \
      '. + [{path: $p, artifact_sha: $art, current_sha: $cur}]')"
    continue
  fi

  # Extract the `skill:` frontmatter field — this is the slug the artifact CLAIMS
  # to authorize. Per-skill binding requires that the file-name slug AND the
  # frontmatter slug match each other (defense-in-depth against template-copy
  # mistakes), AND that consumers (CI gate, PreToolUse hook) verify the slug
  # binds to the specific HIGH-RISK skill being installed.
  artifact_skill="$(echo "$fm" | awk -F: '/^skill:/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); gsub(/"|'"'"'/, "", $2); print $2; exit }')"
  if [ -z "$artifact_skill" ] || ! [[ "$artifact_skill" =~ $slug_re ]]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "skill: field invalid (got: $artifact_skill)" '. + [{path: $p, reason: $r}]')"
    continue
  fi
  if [ "$artifact_skill" != "$slug" ]; then
    invalid="$(echo "$invalid" | jq --arg p "$path" --arg r "skill: field ($artifact_skill) does not match filename slug ($slug)" '. + [{path: $p, reason: $r}]')"
    continue
  fi

  matched="$(echo "$matched" | jq --arg p "$path" --arg s "$slug" --arg sk "$artifact_skill" --arg v "$verdict" '. + [{path: $p, slug: $s, skill: $sk, verdict: $v}]')"
done

result="$(jq -n --argjson m "$matched" --argjson i "$invalid" --argjson s "$stale" \
  '{matched: $m, invalid_schema: $i, stale_findings: $s}')"
echo "$result"

n_invalid="$(echo "$result" | jq '.invalid_schema | length')"
n_stale="$(echo "$result" | jq '.stale_findings | length')"
if [ "$n_invalid" -gt 0 ] || [ "$n_stale" -gt 0 ]; then
  exit 1
fi
exit 0
