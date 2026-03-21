---
title: "Shell Script Defensive Patterns: Plausible Goals Provisioning"
date: 2026-03-13
category: prevention
tags: [shell-scripting, code-review, security, defensive-coding, api-scripts, plausible]
module: plugins/soleur/skills/analytics
---

# Learning: Shell Script Defensive Patterns

## Problem

During implementation of a Plausible Goals API provisioning script, five independent review agents found five distinct issues -- all rooted in patterns that are predictable at authoring time, not bugs that emerge from runtime behavior. The issues were:

1. `api_put` and `api_get` were copy-pasted with identical error handling (~45 duplicated lines)
2. Temp files created with `mktemp` had no `trap`-based cleanup
3. `PLAUSIBLE_BASE_URL` accepted non-HTTPS URLs, enabling credential exfiltration via SSRF
4. `PLAUSIBLE_SITE_ID` was interpolated into URLs without validation
5. `provision_goal` had no `else` clause for unknown goal types

All five were caught and fixed during review. But the cost of review-phase fixes is higher than authoring-phase prevention: each fix required a new review cycle, and the reviewers spent tokens re-scanning already-validated code.

## Prevention Strategies

These are not post-hoc fixes. They are authoring-time habits that eliminate the class of bug before the first commit.

### 1. One `api_request()` function, parameterized by HTTP method

**Anti-pattern:** Writing `api_get()` and `api_put()` as separate functions because "they're simple." They start identical, then diverge silently as one gets error handling improvements the other misses.

**Prevention:** Start every shell script that makes HTTP calls with a single `api_request()` function that takes the method as a parameter:

```bash
api_request() {
  local method="$1" endpoint="$2"
  shift 2
  local response status
  response=$(curl -s -w "\n%{http_code}" -X "$method" \
    -H "Authorization: Bearer ${API_KEY}" \
    "${BASE_URL}${endpoint}" "$@")
  status=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
    echo "ERROR: ${method} ${endpoint} returned ${status}" >&2
    echo "$body" >&2
    return 1
  fi
  echo "$body"
}
```

Callers become `api_request GET /api/v1/sites` and `api_request PUT /api/v1/goals -d '...'`. Error handling, auth headers, and response parsing live in exactly one place.

**Detection signal:** If you see two functions whose bodies differ only in `curl -X GET` vs `curl -X PUT`, merge them immediately.

### 2. `trap` cleanup immediately after `mktemp`, never scattered `rm -f`

**Anti-pattern:** Creating temp files with `mktemp`, then adding `rm -f "$tmpfile"` at each exit path. Paths multiply (early returns, error branches, signals), and at least one will be missed.

**Prevention:** Pair every `mktemp` with a `trap` on the next line:

```bash
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
```

If multiple temp files accumulate, use a temp directory:

```bash
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
```

The `EXIT` trap fires on normal exit, `errexit`, and signals (except `KILL`). No branch analysis required.

**Detection signal:** Any `rm -f "$tmpfile"` that is not inside a `trap` is a cleanup gap waiting to happen.

### 3. Validate HTTPS before sending credentials to configurable URLs

**Anti-pattern:** Accepting `PLAUSIBLE_BASE_URL` (or any configurable endpoint) and immediately sending `Authorization: Bearer` headers to it. An attacker who controls the environment variable (or a misconfigured `.env`) can redirect credentials to `http://evil.example.com`.

**Prevention:** Validate the URL scheme before the first request:

```bash
if [[ "$BASE_URL" != https://* ]]; then
  echo "ERROR: BASE_URL must use HTTPS (got: $BASE_URL)" >&2
  exit 1
fi
```

Place this check at script initialization, not inside the request function (fail fast, fail once).

**Scope:** This applies to any script that sends secrets (API keys, tokens, passwords) to a URL read from configuration. It does not apply to read-only GET requests with no auth headers.

**Detection signal:** `curl -H "Authorization:` combined with a variable URL that lacks a scheme check.

### 4. Validate parameters before URL interpolation

**Anti-pattern:** Interpolating `$SITE_ID` directly into `${BASE_URL}/api/v1/sites/${SITE_ID}/goals` without checking that `SITE_ID` is set and contains only safe characters. An empty `SITE_ID` produces a malformed URL; a `SITE_ID` containing `/` or `?` can alter the request path.

**Prevention:** Validate required parameters at script initialization:

```bash
: "${SITE_ID:?SITE_ID is required}"
if [[ ! "$SITE_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: SITE_ID contains invalid characters: $SITE_ID" >&2
  exit 1
fi
```

**Detection signal:** Any `${var}` inside a URL string where `var` comes from configuration and lacks a preceding validation check.

### 5. Always include an `else`/`default` case in dispatchers

**Anti-pattern:** A function that switches on a parameter value and handles only the currently known cases:

```bash
provision_goal() {
  local goal_type="$1"
  if [[ "$goal_type" == "pageview" ]]; then
    # ...
  elif [[ "$goal_type" == "event" ]]; then
    # ...
  fi
  # silent success for unknown types
}
```

A future caller passes `"custom_event"` and the function silently does nothing.

**Prevention:** Every `if/elif` chain and `case` statement that dispatches on a parameter must have a terminal catch-all that fails loudly:

```bash
else
  echo "ERROR: Unknown goal type: $goal_type" >&2
  return 1
fi
```

Or with `case`:

```bash
*)
  echo "ERROR: Unknown goal type: $goal_type" >&2
  return 1
  ;;
```

**Detection signal:** Any `if/elif` or `case` block where removing the last branch would not change the function's observable behavior for current callers. If the last branch is only there "for completeness" and could be removed without tests failing, the catch-all is missing.

## Key Insight

All five issues share one trait: they are invisible when the script works correctly with valid inputs. They only manifest on the error path (leaked temp files), the security path (HTTP credential theft), or the extension path (new goal types). Review agents found them because review agents systematically check these paths. But the cheaper fix is to internalize these as authoring-time checklists:

1. **Multiple HTTP verbs?** -> Single parameterized function.
2. **`mktemp` anywhere?** -> `trap` on the next line.
3. **Sending credentials to a variable URL?** -> HTTPS check at init.
4. **Interpolating config into URLs?** -> Validate characters at init.
5. **Dispatching on a parameter?** -> Catch-all `else`/`*` that fails.

These are not judgment calls. They are mechanical checks that can be applied without understanding the business logic of the script.

## Tags

category: prevention
module: plugins/soleur/skills/analytics
