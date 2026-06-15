#!/usr/bin/env bash
# linkedin-community.sh -- LinkedIn API wrapper for community operations
#
# Usage: linkedin-community.sh <command> [args]
# Commands:
#   post-content --text "<text>" [--author "<urn>"]  - Post to LinkedIn (person or company page)
#   fetch-metrics                  - Fetch aggregate Company Page metrics (org read scopes)
#   fetch-activity                 - Fetch recent Company Page post metadata (org read scopes)
#
# fetch-metrics / fetch-activity history: implemented 2026-06-15. The prior
# "requires Marketing Developer Platform (MDP) partner approval" premise was
# incorrect — the org token already carries the read scopes
# (r_organization_social, rw_organization_admin, r_organization_followers).
# Collection is aggregate-only: share statistics + a single follower total +
# recent org-authored post metadata. NO per-member data, NO follower-list
# extraction, NO demographic facets.
#
# Environment variables (required):
#   LINKEDIN_ACCESS_TOKEN      - OAuth 2.0 Bearer token for personal posts (60-day TTL)
#   LINKEDIN_ORG_ACCESS_TOKEN  - OAuth 2.0 Bearer token for organization/company page
#                                operations. Required for fetch-metrics/fetch-activity
#                                (org read scopes: r_organization_social,
#                                rw_organization_admin) and for org posts
#                                (w_organization_social, --author urn:li:organization:*).
#   LINKEDIN_ORG_ID            - Numeric organization id. Required for
#                                fetch-metrics/fetch-activity (builds the org URN).
#   LINKEDIN_PERSON_URN    - Person URN for posting (urn:li:person:{id}), optional if --author provided
#   LINKEDIN_ALLOW_POST    - Set to "true" to enable posting (safety guard, default: disabled)
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Retryable error (rate limit exhaustion)
#
# Output: JSON to stdout
# Errors: Messages to stderr, exit 1

set -euo pipefail

LINKEDIN_API="https://api.linkedin.com"
LINKEDIN_API_VERSION="202602"
LINKEDIN_POST_MAX_LENGTH=3000

# --- Dependency checks ---

require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}

# --- Credential validation ---

require_credentials() {
  if [[ -z "${LINKEDIN_ACCESS_TOKEN:-}" ]]; then
    echo "Error: Missing LinkedIn credentials: LINKEDIN_ACCESS_TOKEN" >&2
    echo "" >&2
    echo "To configure:" >&2
    echo "  1. Run: linkedin-setup.sh generate-token" >&2
    echo "  2. Or set LINKEDIN_ACCESS_TOKEN manually" >&2
    echo "  3. Run: linkedin-setup.sh verify" >&2
    exit 1
  fi
}

# Require the organization read credentials for fetch-metrics/fetch-activity.
# Fails LOUD with `exit 1` (NOT `return 1`): the script runs `set -euo pipefail`,
# and a `return 1` consumed in a conditional/pipeline does NOT terminate, which
# would re-open the silent fall-through. Mirrors require_credentials (exit 1),
# NOT cmd_post_content's return-1 guard.
#
# NEVER silent-fallback to the personal LINKEDIN_ACCESS_TOKEN — that token is
# live in the cron spawn env and lacks the org read scopes; falling back yields
# an opaque 401/400 instead of a clear "missing org creds" error
# (learning 2026-04-26-linkedin-org-token-fallback-silent-400.md).
require_org_credentials() {
  local missing=()
  [[ -n "${LINKEDIN_ORG_ACCESS_TOKEN:-}" ]] || missing+=("LINKEDIN_ORG_ACCESS_TOKEN")
  # Fail-closed numeric check: a non-numeric (or unset) org id must never be
  # interpolated into the request URL. When unset/empty the message names the
  # bare var (matching the existing unset path); when set-but-non-numeric it
  # names the constraint so the operator can fix it.
  if [[ -z "${LINKEDIN_ORG_ID:-}" ]]; then
    missing+=("LINKEDIN_ORG_ID")
  elif [[ ! "${LINKEDIN_ORG_ID}" =~ ^[0-9]+$ ]]; then
    missing+=("LINKEDIN_ORG_ID (must be numeric)")
  fi
  if (( ${#missing[@]} > 0 )); then
    echo "Error: Missing LinkedIn organization credentials: ${missing[*]}" >&2
    echo "fetch-metrics/fetch-activity read the operator's own Company Page" >&2
    echo "aggregate insights and require the org token + org id." >&2
    echo "Set LINKEDIN_ORG_ACCESS_TOKEN (org read scopes) and LINKEDIN_ORG_ID." >&2
    exit 1
  fi
}

# --- Response handler ---

# Handle HTTP response status codes from LinkedIn API
# Arguments: http_code body endpoint depth retry_cmd...
# On 2xx: validates JSON, echoes body to stdout
# On 429: sleeps and invokes retry_cmd (caller with incremented depth)
# On error: prints diagnostic to stderr, exits 1 (or 2 for rate limit exhaustion)
handle_response() {
  local http_code="$1"
  local body="$2"
  local endpoint="$3"
  local depth="$4"
  shift 4
  local -a retry_cmd=("$@")

  case "$http_code" in
    2[0-9][0-9])
      # LinkedIn POST /rest/posts returns 201 with empty body -- that is valid
      if [[ -n "$body" ]] && ! echo "$body" | jq . >/dev/null 2>&1; then
        echo "Error: LinkedIn API returned malformed JSON for ${endpoint}" >&2
        exit 1
      fi
      echo "$body"
      ;;
    401)
      echo "Error: LinkedIn API returned 401 Unauthorized for ${endpoint}." >&2
      echo "Your access token may be expired (60-day TTL)." >&2
      echo "" >&2
      echo "To fix:" >&2
      echo "  1. Run: linkedin-setup.sh validate-credentials" >&2
      echo "  2. If expired, run: linkedin-setup.sh generate-token" >&2
      exit 1
      ;;
    403)
      local message
      message=$(echo "$body" | jq -r '.message // .code // "Access denied"' 2>/dev/null || echo "Access denied")
      echo "Error: LinkedIn API returned 403 Forbidden for ${endpoint}: ${message}" >&2
      exit 1
      ;;
    429)
      if (( depth >= 3 )); then
        echo "Error: LinkedIn API rate limit exceeded after 3 retries for ${endpoint}." >&2
        exit 2
      fi
      echo "Rate limited. Retrying after 5s (attempt $((depth + 1))/3)..." >&2
      sleep 5
      "${retry_cmd[@]}"
      ;;
    *)
      local message
      message=$(echo "$body" | jq -r '.message // .code // "Unknown error"' 2>/dev/null || echo "Unknown error")
      echo "Error: LinkedIn API returned HTTP ${http_code} for ${endpoint}: ${message}" >&2
      exit 1
      ;;
  esac
}

# --- GET request helper ---

# Make an authenticated GET request to the LinkedIn API
# Arguments: endpoint [depth] [extra_header]
#   extra_header - optional single "Name: value" header (e.g. the
#                  "X-RestLi-Method: FINDER" header the Posts author-finder
#                  requires). Forwarded on the 429-retry recursion so a retry
#                  never silently drops it.
# Retries on 429 up to 3 times
get_request() {
  local endpoint="$1"
  local depth="${2:-0}"
  local extra_header="${3:-}"

  if (( depth >= 3 )); then
    echo "Error: LinkedIn API rate limit exceeded after 3 retries for ${endpoint}." >&2
    exit 2
  fi

  local url="${LINKEDIN_API}${endpoint}"

  local -a header_args=()
  if [[ -n "$extra_header" ]]; then
    header_args=(-H "$extra_header")
  fi

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${LINKEDIN_ACCESS_TOKEN}" \
    -H "X-Restli-Protocol-Version: 2.0.0" \
    -H "LinkedIn-Version: ${LINKEDIN_API_VERSION}" \
    "${header_args[@]}" \
    "$url" 2>/dev/null); then
    echo "Error: Failed to connect to LinkedIn API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  handle_response "$http_code" "$body" "$endpoint" "$depth" \
    get_request "$endpoint" "$((depth + 1))" "$extra_header"
}

# --- POST request helper ---

# Make an authenticated POST request to the LinkedIn API
# Arguments: endpoint json_body [depth]
# Captures response headers via temp file to extract x-restli-id
# Only retries on 429 (POST is not idempotent)
post_request() {
  local endpoint="$1"
  local json_body="$2"
  local depth="${3:-0}"

  local url="${LINKEDIN_API}${endpoint}"

  local header_file
  header_file=$(mktemp) || { echo "Error: Failed to create temp file." >&2; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -f '$header_file'" EXIT

  local response http_code body
  if ! response=$(curl -s -w "\n%{http_code}" \
    -D "$header_file" \
    -H "Authorization: Bearer ${LINKEDIN_ACCESS_TOKEN}" \
    -H "X-Restli-Protocol-Version: 2.0.0" \
    -H "LinkedIn-Version: ${LINKEDIN_API_VERSION}" \
    -H "Content-Type: application/json" \
    -X POST -d "$json_body" \
    "$url" 2>/dev/null); then
    rm -f "$header_file"
    echo "Error: Failed to connect to LinkedIn API." >&2
    echo "Check your network connection and try again." >&2
    exit 1
  fi

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  # On 429, retry (rate limit returned before post is created)
  if [[ "$http_code" == "429" ]]; then
    rm -f "$header_file"
    handle_response "$http_code" "$body" "$endpoint" "$depth" \
      post_request "$endpoint" "$json_body" "$((depth + 1))"
    return
  fi

  # For non-429 errors on POST, fail immediately (non-idempotent)
  if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    rm -f "$header_file"
    handle_response "$http_code" "$body" "$endpoint" "$depth"
    return
  fi

  # Success: extract x-restli-id from response headers
  local restli_id=""
  if [[ -f "$header_file" ]]; then
    restli_id=$(grep -i '^x-restli-id:' "$header_file" | sed 's/^[^:]*: *//' | tr -d '\r' || true)
  fi
  rm -f "$header_file"

  # Return JSON with post URN
  if [[ -n "$restli_id" ]]; then
    jq -n --arg id "$restli_id" '{"post_urn": $id}'
  else
    echo '{"post_urn": null}' >&2
    echo "Warning: Post created but x-restli-id header not found in response." >&2
    # Still return valid JSON
    echo '{}'
  fi
}

# --- LinkedIn "Little Text Format" handling ---
#
# The Posts API commentary field is "Little Text Format": the characters
# \ | { } [ ] ( ) < > * ~ are reserved, and LinkedIn silently TRUNCATES the
# post at the first unescaped occurrence (observed 2026-06-10: nine org posts
# cut mid-sentence at the first "(", which also dropped the trailing article
# links). '#' and '@' stay unescaped so hashtags and mentions keep their
# linking behavior; '_' stays unescaped because escaping it corrupts URLs
# (utm_source=...) and it does not trigger the truncation failure class.

sanitize_commentary() {
  # Markdown-source artifacts that must not reach LinkedIn verbatim: strip
  # whole-line HTML comments (e.g. markdownlint directives), unwrap
  # <https://...> autolinks (angle brackets are reserved characters), and
  # drop trailing horizontal rules / blank lines.
  sed -e '/^[[:space:]]*<!--.*-->[[:space:]]*$/d' \
      -e 's/<\(https\{0,1\}:\/\/[^>]*\)>/\1/g' |
    awk '{ lines[++n] = $0 }
         END {
           while (n > 0 && (lines[n] ~ /^[[:space:]]*$/ || lines[n] ~ /^[[:space:]]*-{3,}[[:space:]]*$/)) n--
           for (i = 1; i <= n; i++) print lines[i]
         }'
}

escape_little_text() {
  local t="$1"
  t="${t//\\/\\\\}"
  t="${t//|/\\|}"
  t="${t//\{/\\\{}"
  t="${t//\}/\\\}}"
  t="${t//\[/\\[}"
  t="${t//\]/\\]}"
  t="${t//(/\\(}"
  t="${t//)/\\)}"
  t="${t//</\\<}"
  t="${t//>/\\>}"
  t="${t//\*/\\*}"
  t="${t//\~/\\~}"
  printf '%s' "$t"
}

# --- Commands ---

cmd_post_content() {
  # Guard: require explicit opt-in to post.
  if [[ "${LINKEDIN_ALLOW_POST:-}" != "true" ]]; then
    echo "Error: LINKEDIN_ALLOW_POST is not set to 'true'." >&2
    echo "Set LINKEDIN_ALLOW_POST=true to enable posting." >&2
    return 1
  fi

  local text=""
  local author_override=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text)
        text="${2:-}"
        if [[ -z "$text" ]]; then
          echo "Error: --text requires a non-empty value." >&2
          exit 1
        fi
        shift 2
        ;;
      --author)
        author_override="${2:-}"
        if [[ -z "$author_override" ]]; then
          echo "Error: --author requires a non-empty value." >&2
          exit 1
        fi
        shift 2
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        echo "Usage: linkedin-community.sh post-content --text \"<text>\" [--author \"<urn>\"]" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$text" ]]; then
    echo "Error: --text is required." >&2
    echo "Usage: linkedin-community.sh post-content --text \"<text>\"" >&2
    exit 1
  fi

  # Strip markdown-source artifacts before the length check (the limit
  # applies to visible characters; Little Text escape backslashes added
  # below do not count toward it).
  text=$(printf '%s\n' "$text" | sanitize_commentary)

  if (( ${#text} > LINKEDIN_POST_MAX_LENGTH )); then
    echo "Error: Post text is ${#text} characters, exceeds LinkedIn's ${LINKEDIN_POST_MAX_LENGTH}-character limit." >&2
    exit 1
  fi

  local escaped_text
  escaped_text=$(escape_little_text "$text")

  # Build request body (--author overrides default LINKEDIN_PERSON_URN)
  local author="${author_override:-${LINKEDIN_PERSON_URN:-}}"
  if [[ -z "$author" ]]; then
    echo "Error: No author specified. Provide --author or set LINKEDIN_PERSON_URN." >&2
    exit 1
  fi

  # Normalize bare person IDs: LinkedIn API requires full URN (urn:li:person:<id>).
  # LINKEDIN_PERSON_URN is often stored as just the ID portion without the prefix.
  if [[ "$author" != urn:* ]]; then
    author="urn:li:person:${author}"
  fi

  # Organization posts require w_organization_social scope -- use LINKEDIN_ORG_ACCESS_TOKEN.
  if [[ "$author" == urn:li:organization:* ]]; then
    if [[ -z "${LINKEDIN_ORG_ACCESS_TOKEN:-}" ]]; then
      echo "Error: LINKEDIN_ORG_ACCESS_TOKEN is required for organization posts (w_organization_social scope)." >&2
      echo "Set LINKEDIN_ORG_ACCESS_TOKEN to a token with w_organization_social scope." >&2
      exit 1
    fi
    LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"
  fi

  local json_body
  json_body=$(jq -n \
    --arg author "$author" \
    --arg text "$escaped_text" \
    '{
      author: $author,
      commentary: $text,
      visibility: "PUBLIC",
      distribution: {
        feedDistribution: "MAIN_FEED",
        targetEntities: [],
        thirdPartyDistributionChannels: []
      },
      lifecycleState: "PUBLISHED",
      isReshareDisabledByAuthor: false
    }')

  local result
  result=$(post_request "/rest/posts" "$json_body")

  echo "$result"
  echo "Post created successfully." >&2
}

# Fetch aggregate Company Page metrics: lifetime share statistics + a single
# follower total. Aggregate-only — no demographic facets, no per-member data.
cmd_fetch_metrics() {
  # Defense-in-depth: re-check org creds as the FIRST line (dispatch also checks).
  # The personal LINKEDIN_ACCESS_TOKEN is live in the spawn env, so a direct
  # call to this function must not be able to fall through to it.
  require_org_credentials

  # Scope the org token function-locally so get_request's Bearer header uses it
  # WITHOUT leaking into the personal path (safer than cmd_post_content's global
  # mutation at the org-post branch).
  local LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"

  local org_urn="urn%3Ali%3Aorganization%3A${LINKEDIN_ORG_ID}"

  # --- Aggregate share statistics (lifetime). ---
  local share_body
  share_body=$(get_request \
    "/rest/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity=${org_urn}")

  # Shape validation BEFORE any `// 0` fallbacks (silent-failure HIGH-1):
  # handle_response validated only JSON parseability, not shape. An empty
  # `.elements` (e.g. token lacks ADMINISTRATOR role) or a wrong shape must NOT
  # render as fake zeros — emit an explicit error and exit 1.
  if ! echo "$share_body" | jq -e '(.elements[0].totalShareStatistics | type) == "object"' >/dev/null 2>&1; then
    echo "Error: organizationalEntityShareStatistics returned no usable totalShareStatistics for org ${LINKEDIN_ORG_ID}." >&2
    echo "The org token may lack the ADMINISTRATOR role, or the response shape changed." >&2
    exit 1
  fi

  local share_statistics
  share_statistics=$(echo "$share_body" | jq '
    .elements[0].totalShareStatistics as $s |
    {
      impressions: ($s.impressionCount // 0),
      unique_impressions: ($s.uniqueImpressionsCount // 0),
      clicks: ($s.clickCount // 0),
      likes: ($s.likeCount // 0),
      comments: ($s.commentCount // 0),
      shares: ($s.shareCount // 0),
      engagement: ($s.engagement // 0)
    }')

  # --- Single follower total via networkSizes. ---
  # Partial-failure policy (silent-failure HIGH-2): the networkSizes call must
  # not abort the (more important) share-stats result. Run it in a subshell whose
  # non-zero exit is tolerated; on failure total_followers degrades to null with
  # a stderr warning rather than get_request's default `exit`.
  local total_followers="null"
  local network_body
  if network_body=$(get_request \
    "/rest/networkSizes/${org_urn}?edgeType=COMPANY_FOLLOWED_BY_MEMBER" 2>/dev/null); then
    local size
    size=$(echo "$network_body" | jq -r '.firstDegreeSize // empty' 2>/dev/null || true)
    if [[ "$size" =~ ^[0-9]+$ ]]; then
      # Only a clean non-negative integer is trusted: it is injected via
      # `--argjson total_followers` into the final emit, where a non-numeric
      # value would crash jq under set -e and defeat the degrade-to-null
      # contract. Anything else degrades to null (same path as a failed fetch).
      total_followers="$size"
    elif [[ -n "$size" ]]; then
      echo "Warning: networkSizes returned non-numeric firstDegreeSize ('${size}') for org ${LINKEDIN_ORG_ID}; total_followers=null." >&2
    else
      echo "Warning: networkSizes returned no firstDegreeSize for org ${LINKEDIN_ORG_ID}; total_followers=null." >&2
    fi
  else
    echo "Warning: networkSizes call failed for org ${LINKEDIN_ORG_ID}; total_followers=null." >&2
  fi

  jq -n \
    --arg org_id "$LINKEDIN_ORG_ID" \
    --argjson total_followers "$total_followers" \
    --argjson share_statistics "$share_statistics" \
    '{
      org_id: $org_id,
      total_followers: $total_followers,
      share_statistics: $share_statistics
    }'
}

# Fetch recent Company Page post metadata via the Posts author-finder.
# Aggregate-only — post metadata, no commenter/liker identities.
cmd_fetch_activity() {
  require_org_credentials

  local LINKEDIN_ACCESS_TOKEN="$LINKEDIN_ORG_ACCESS_TOKEN"

  local org_urn="urn%3Ali%3Aorganization%3A${LINKEDIN_ORG_ID}"

  # The Posts author-finder requires the X-RestLi-Method: FINDER header, threaded
  # through get_request's optional 3rd arg (forwarded on the 429 recursion).
  local posts_body
  posts_body=$(get_request \
    "/rest/posts?author=${org_urn}&q=author&count=10&sortBy=LAST_MODIFIED" \
    0 \
    "X-RestLi-Method: FINDER")

  # Shape validation BEFORE the `.elements[]` iteration: mirrors
  # cmd_fetch_metrics's guard. A missing/null `.elements` (e.g. token lacks the
  # required role, or the response shape changed) makes `.elements[]` crash jq
  # ("Cannot iterate over null", exit 5) under set -e — emit an explicit error
  # and exit 1 instead. A present-but-empty `elements: []` still succeeds and
  # yields `{"posts": []}`.
  if ! echo "$posts_body" | jq -e '(.elements | type) == "array"' >/dev/null 2>&1; then
    echo "Error: posts author-finder returned no usable elements array for org ${LINKEDIN_ORG_ID}." >&2
    echo "The org token may lack the required role, or the response shape changed." >&2
    exit 1
  fi

  # commentary is operator-authored Page-public post text. If a post @mentions a
  # member it flows to the digest, but the LIA's no-@mention posting TOM bounds
  # this — no inbound filter needed. Emit metadata only; no author/commenter/
  # liker identities. `//` fallbacks preserve each post even if a field is absent
  # (learning 2026-03-10-jq-generator-silent-data-loss.md).
  echo "$posts_body" | jq '
    {
      posts: [
        .elements[] | {
          id: .id,
          commentary: (.commentary // null),
          published_at: (.publishedAt // .createdAt // null),
          lifecycle_state: (.lifecycleState // null)
        }
      ]
    }'
}

# --- Main ---

main() {
  local command="${1:-}"
  shift || true

  if [[ -z "$command" ]]; then
    echo "Usage: linkedin-community.sh <command> [args]" >&2
    echo "" >&2
    echo "Commands:" >&2
    echo "  post-content --text \"<text>\" [--author \"<urn>\"]  - Post to LinkedIn" >&2
    echo "  fetch-metrics                 - Fetch aggregate Company Page metrics (org read scopes)" >&2
    echo "  fetch-activity                - Fetch recent Company Page post metadata (org read scopes)" >&2
    exit 1
  fi

  require_jq

  case "$command" in
    fetch-metrics)
      require_org_credentials
      cmd_fetch_metrics
      ;;
    fetch-activity)
      require_org_credentials
      cmd_fetch_activity
      ;;
    post-content)
      require_credentials
      cmd_post_content "$@"
      ;;
    *)
      echo "Error: Unknown command '${command}'" >&2
      echo "Run 'linkedin-community.sh' without arguments for usage." >&2
      exit 1
      ;;
  esac
}

# Guard: allow sourcing without executing main (for test harness)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
