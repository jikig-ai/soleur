#!/usr/bin/env bash
set -uo pipefail

# Assert every hand-maintained required NEXT_PUBLIC_* secret is exported in the
# current environment. Invoke via `doppler run -c prd -- bash <path>` so Doppler
# populates env before we read it.
#
# Drift policy: hand-maintained (brainstorm Decision #5). NEXT_PUBLIC_AGENT_COUNT
# is intentionally excluded — it is a build-time Docker ARG, not a Doppler secret.
#
# `-e` is deliberately NOT set: the loop must continue past each missing key so
# the output enumerates every missing secret in one run. `-u` is safe: `${!key:-}`
# uses an explicit default, which satisfies `-u` on bash 4.4+.

REQUIRED=(
  NEXT_PUBLIC_APP_URL
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  NEXT_PUBLIC_SENTRY_DSN
  NEXT_PUBLIC_VAPID_PUBLIC_KEY
  NEXT_PUBLIC_GITHUB_APP_SLUG
)

missing=0
shape_violations=0
SUPABASE_URL_RE='^https://([a-z0-9]{20}\.supabase\.co|api\.soleur\.ai)$'

for key in "${REQUIRED[@]}"; do
  value="${!key:-}"
  if [[ -z "$value" ]]; then
    echo "::error::Required secret missing from Doppler prd: $key"
    missing=$((missing + 1))
  else
    echo "ok $key"
  fi
done

# Canonical-shape assertion for NEXT_PUBLIC_SUPABASE_URL: catches the
# placeholder-leak class (e.g. operator pasting `https://test.supabase.co`
# during a credentials rotation). Mirrored regex sites (edit together):
#   - .github/workflows/reusable-release.yml step "Validate NEXT_PUBLIC_SUPABASE_URL build-arg"
#   - apps/web-platform/lib/supabase/validate-url.ts (CANONICAL_HOSTNAME + PROD_ALLOWED_HOSTS)
url_value="${NEXT_PUBLIC_SUPABASE_URL:-}"
if [[ -n "$url_value" ]]; then
  if [[ ! "$url_value" =~ $SUPABASE_URL_RE ]]; then
    echo "::error::NEXT_PUBLIC_SUPABASE_URL has non-canonical value (likely a placeholder leak)"
    echo "::error::Expected: https://<20-char-ref>.supabase.co or https://api.soleur.ai"
    shape_violations=$((shape_violations + 1))
  fi
fi

# JWT-claims assertion for NEXT_PUBLIC_SUPABASE_ANON_KEY: catches the
# placeholder/test-fixture leak class AND the service-role-key paste class
# (silent RLS bypass — strictly worse than test-fixture leak). Mirrored sites:
#   - .github/workflows/reusable-release.yml step "Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg"
#   - apps/web-platform/lib/supabase/validate-anon-key.ts (assertProdSupabaseAnonKey)
#   - plugins/soleur/skills/preflight/SKILL.md Check 5 Step 5.4
key_value="${NEXT_PUBLIC_SUPABASE_ANON_KEY:-}"
if [[ -n "$key_value" ]]; then
  # Strip CR/LF defensively (Doppler write paths that pass through CRLF tools).
  key_clean="${key_value//$'\r'/}"
  key_clean="${key_clean//$'\n'/}"
  dot_count=$(printf '%s' "$key_clean" | tr -cd '.' | wc -c)
  if [[ "$dot_count" -ne 2 ]]; then
    echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY is not a 3-segment JWT"
    shape_violations=$((shape_violations + 1))
  else
    payload=$(printf '%s' "$key_clean" | cut -d. -f2)
    pad=$(( (4 - ${#payload} % 4) % 4 ))
    if [[ $pad -gt 0 ]]; then
      padded="$payload$(printf '=%.0s' $(seq 1 $pad))"
    else
      padded="$payload"
    fi
    json=$(printf '%s' "$padded" | tr '_-' '/+' | base64 -d 2>/dev/null || true)
    if [[ -z "$json" ]]; then
      echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY payload is not valid base64url"
      shape_violations=$((shape_violations + 1))
    else
      iss=$(printf '%s' "$json" | jq -r '.iss // ""' 2>/dev/null || echo "")
      role=$(printf '%s' "$json" | jq -r '.role // ""' 2>/dev/null || echo "")
      ref=$(printf '%s' "$json" | jq -r '.ref // ""' 2>/dev/null || echo "")
      # Strip CR/LF before echo to defend against log injection via crafted claims.
      iss_safe="${iss//[$'\n\r']/}"
      role_safe="${role//[$'\n\r']/}"
      ref_safe="${ref//[$'\n\r']/}"
      if [[ "$iss" != "supabase" ]]; then
        echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY iss=\"$iss_safe\", expected \"supabase\""
        shape_violations=$((shape_violations + 1))
      fi
      if [[ "$role" != "anon" ]]; then
        echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY role=\"$role_safe\", expected \"anon\" (service_role in browser bundle = silent RLS bypass)"
        shape_violations=$((shape_violations + 1))
      fi
      if [[ ! "$ref" =~ ^[a-z0-9]{20}$ ]]; then
        echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY ref=\"$ref_safe\" does not match canonical 20-char shape"
        shape_violations=$((shape_violations + 1))
      else
        case "$ref" in
          test*|placeholder*|example*|service*|local*|dev*|stub*)
            echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY ref=\"$ref_safe\" is a placeholder/test-fixture value"
            shape_violations=$((shape_violations + 1))
            ;;
        esac
        # Cross-check ref against URL canonical first label (skipped for
        # custom-domain `api.soleur.ai` — CI's `dig +short CNAME` step is
        # load-bearing for that case; this Doppler-side gate trusts JWT ref).
        url_for_check="${NEXT_PUBLIC_SUPABASE_URL:-}"
        url_host=$(printf '%s' "$url_for_check" | sed -E 's#^https://##; s#/.*$##')
        if [[ "$url_host" =~ ^[a-z0-9]{20}\.supabase\.co$ ]]; then
          expected_ref="${url_host%%.*}"
          if [[ "$ref" != "$expected_ref" ]]; then
            echo "::error::NEXT_PUBLIC_SUPABASE_ANON_KEY ref=\"$ref_safe\" does not match URL canonical ref=\"$expected_ref\""
            shape_violations=$((shape_violations + 1))
          fi
        fi
      fi
    fi
  fi
fi

if [[ "$missing" -gt 0 ]]; then
  echo "::error::$missing required NEXT_PUBLIC_* secret(s) missing from Doppler prd"
  exit 1
fi

if [[ "$shape_violations" -gt 0 ]]; then
  echo "::error::$shape_violations NEXT_PUBLIC_* shape violation(s) in Doppler prd"
  exit 1
fi

echo "::notice::All ${#REQUIRED[@]} required NEXT_PUBLIC_* secrets present in Doppler prd"
