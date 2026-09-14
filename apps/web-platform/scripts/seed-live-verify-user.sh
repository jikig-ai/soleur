#!/usr/bin/env bash
# Seed the dedicated synthetic PROD principal for the live-verification harness
# (#5452, FR1/FR2/TR5). The harness (apps/web-platform/scripts/live-verify/run.ts)
# signs in as this user against the DEPLOYED app to catch the realtime/
# server-commit-timing bug class mock e2e structurally cannot (#5391/#5421/#5436).
#
# Usage: run LOCALLY, or automatically before live-verify on a triggering
# release (web-platform-release.yml, #7969 — operator-approved).
#
# SUPERSEDES the original "NEVER wired into CI; keeps prod service-role out of
# GitHub Actions" note. That claim was already inaccurate when written: the
# sibling live-verify harness step runs under `doppler run -c prd`, which
# injects the whole prd config — SUPABASE_SERVICE_ROLE_KEY included — into an
# Actions process. Wiring this in does not widen what a compromised
# DOPPLER_TOKEN_PRD reaches; it makes an already-present capability routine,
# which is why the masking below is not optional.
#
#   doppler run -p soleur -c prd -- bash apps/web-platform/scripts/seed-live-verify-user.sh
#
# Idempotent: re-runs upsert the password to LIVE_VERIFY_USER_PASSWORD (set by
# Terraform random_password → doppler_secret, infra/live-verify.tf) and reset the
# full middleware ladder to canonical state, so rotation is just
# `terraform apply -replace=random_password.live_verify_user` then re-run.
#
# Ladder (per CTO ruling 2026-06-17, ADR live-verify): the synthetic user must
# clear EVERY middleware gate the real rail sits behind, AND `createConversation`
# (server/ws-handler.ts) aborts if `workspaces.repo_url` is null — so this seeds:
#   - auth user (email_confirm:true) → handle_new_user trigger (mig 053, ADR-038)
#     auto-provisions a solo workspace whose id == user.id + owner membership
#   - public.users ladder: workspace_status + repo_status (consent is recorded
#     separately via the public.accept_terms RPC, which also writes the ledger),
#     NOTE: workspace_path was DROPPED from public.users by migration 112
#     (112_drop_legacy_users_repo_columns.sql). PATCHing it returns 42703 and
#     aborted every run — measured against prd.
#   - workspaces row: repo_status=ready AND repo_url=<synthetic sentinel> (the
#     seed-qa-user.sh gap; getCurrentRepoUrl reads workspaces.repo_url, not
#     users.repo_url — server/current-repo-url.ts:58-62)
#   - user_session_state row: current_workspace_id=<solo workspace> +
#     current_organization_id (#5501). createConversation resolves
#     conversations.workspace_id via the fail-loud resolveUserWorkspaceBinding,
#     which THROWS on an absent binding (agent-session-registry.ts:316) — without
#     this row a chat send never persists a conversation and the harness emits
#     CANT-RUN:forURL. handle_new_user (mig 053) does not seed this row.
#   - a dummy (decrypt-poisoned) anthropic api_keys row (has-key gate)
#   - DELIBERATELY NO scope_grants row: with zero grants the agent's Send route
#     403s before write-action-send.ts, so the harness can never create a WORM
#     action_sends row (I-action-send-free, by construction).
#
# Triple-defense before any Supabase write (mirrors seed-dev-users.sh, but PRD):
#   1. DOPPLER_CONFIG === "prd"                          (Doppler injects)
#   2. SUPABASE_SERVICE_ROLE_KEY JWT role === service_role + ref derived from JWT
#   3. NEXT_PUBLIC_SUPABASE_URL is in PROD_ALLOWED_HOSTS (api.soleur.ai) OR the
#      canonical 20-char ref shape; on the canonical shape we cross-check the
#      JWT ref against the URL host (validate-url.ts / validate-anon-key.ts
#      custom-domain handling: trust the JWT ref when the host is the custom
#      domain, since it carries no 20-char label).
#
# Secret discipline (AC8): no `set -x`; the password is only ever interpolated
# into a jq-built request body passed straight to curl -d — never echoed, never
# logged. No response body that could carry a token is printed.

set -euo pipefail

case "$-" in
  *x*)
    if [ -n "${LIVE_VERIFY_USER_PASSWORD:+x}${NEXT_PUBLIC_SUPABASE_ANON_KEY:+x}${SUPABASE_SERVICE_ROLE_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

# --- Pre-flight ----------------------------------------------------------

if [[ "${DOPPLER_CONFIG:-}" != "prd" ]]; then
  echo "::error::Refusing to run: DOPPLER_CONFIG=\"${DOPPLER_CONFIG:-<unset>}\" — must be \"prd\""
  echo "::error::Re-run via: doppler run -p soleur -c prd -- bash $0"
  exit 1
fi

: "${NEXT_PUBLIC_SUPABASE_URL:?NEXT_PUBLIC_SUPABASE_URL not set (use doppler run)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY not set (use doppler run)}"
: "${NEXT_PUBLIC_SUPABASE_ANON_KEY:?NEXT_PUBLIC_SUPABASE_ANON_KEY not set (use doppler run)}"
: "${LIVE_VERIFY_USER_PASSWORD:?LIVE_VERIFY_USER_PASSWORD not set — run terraform apply for infra/live-verify.tf first}"

# Strip CR/LF defensively (mirrors verify-required-secrets.sh).
SRK="${SUPABASE_SERVICE_ROLE_KEY//$'\r'/}"
SRK="${SRK//$'\n'/}"
SB_URL="${NEXT_PUBLIC_SUPABASE_URL//$'\r'/}"
SB_URL="${SB_URL//$'\n'/}"
ANON="${NEXT_PUBLIC_SUPABASE_ANON_KEY//$'\r'/}"
ANON="${ANON//$'\n'/}"

# Allowed prod hosts (mirror lib/supabase/validate-url.ts PROD_ALLOWED_HOSTS).
CANONICAL_RE='^https://[a-z0-9]{20}\.supabase\.co$'
url_host="${SB_URL#https://}"
url_host="${url_host%%/*}"

is_custom_domain=0
if [[ "$url_host" == "api.soleur.ai" ]]; then
  is_custom_domain=1
elif [[ "$DOPPLER_CONFIG" == "prd" && -n "${GITHUB_ACTIONS:-}" ]]; then
  # IDENTITY, not internal consistency (#7969 review). The other gates prove the
  # config is NAMED prd, the URL has a valid SHAPE, and the key admins whatever
  # project that URL names — a coherent-but-wrong set (a dev URL + its own key,
  # under any Doppler project carrying a config called `prd`) satisfies all
  # three and would seed the wrong database. hr-dev-prd-distinct-supabase-projects
  # is a hard rule, and automation is what promotes this from theoretical:
  # an operator would notice a wrong ref in the pre-flight notice, a release job
  # will not. So the refusal is scoped to UNATTENDED runs: locally the canonical
  # path still works, which is what it was designed for and what the JWT-branch
  # fixtures exercise.
  echo "::error::DOPPLER_CONFIG=prd but NEXT_PUBLIC_SUPABASE_URL host is \"$url_host\","
  echo "::error::not the prod custom domain (api.soleur.ai) — refusing to seed."
  exit 1
elif [[ ! "$SB_URL" =~ $CANONICAL_RE ]]; then
  echo "::error::NEXT_PUBLIC_SUPABASE_URL=\"$SB_URL\" is neither the prod custom domain"
  echo "::error::(api.soleur.ai) nor the canonical 20-char ref shape — refusing to seed."
  exit 1
fi

# MASK BEFORE FIRST USE (#7969 review). Actions masks `secrets.*` only, so
# everything `doppler run` injects is unmasked in a PUBLIC log. redact-stdin.ts
# is the primary control and these are defence in depth — a directive survives
# that pipe unchanged, and GHA parses workflow commands from step stdout.
# Emitted only under Actions so a local run is unaffected.
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  printf '::add-mask::%s\n' "$SRK"
  [[ -n "${LIVE_VERIFY_USER_PASSWORD:-}" ]] && printf '::add-mask::%s\n' "$LIVE_VERIFY_USER_PASSWORD"
fi

# Assert the key grants service-role ON THIS PROJECT.
#
# Two key formats exist and only one can be decoded:
#   * legacy  — a 3-segment JWT carrying `role` and `ref` claims
#   * current — an opaque `sb_secret_…` secret key (Supabase's newer format)
#
# The prd key is the OPAQUE form, and this block used to require a JWT
# unconditionally. That is why the seed had been unrunnable in prd since the
# key rotated: it exited 1 at the segment count before writing anything, so the
# synthetic principal silently stopped being refreshed and drifted behind the
# T&C gate — the root cause of #7969. The literal `TC_VERSION` was a symptom;
# this was the disease.
#
# The two properties the JWT decode bought are preserved, and one is
# strengthened. A JWT's `role` is a SELF-ASSERTED claim this script never
# verified against the server; an authenticated probe is the server's own
# verdict, and it proves BOTH properties at once:
#   P1 the key really grants service-role  — /auth/v1/admin/* is 401 for anon
#   P2 the key belongs to the project the URL resolves to — the probe targets
#      $SB_URL, so a key for another project cannot answer 200 here
ref=""
if [[ "$(printf '%s' "$SRK" | tr -cd '.' | wc -c)" -eq 2 ]]; then
  # Legacy JWT: keep the decode, which additionally yields the ref for the
  # canonical-host cross-check below.
  payload=$(printf '%s' "$SRK" | cut -d. -f2)
  pad=$(( (4 - ${#payload} % 4) % 4 ))
  if [[ $pad -gt 0 ]]; then
    padded="$payload$(printf '=%.0s' $(seq 1 $pad))"
  else
    padded="$payload"
  fi
  json=$(printf '%s' "$padded" | tr '_-' '/+' | base64 -d 2>/dev/null) || {
    echo "::error::SUPABASE_SERVICE_ROLE_KEY payload is not valid base64url"
    exit 1
  }
  ref=$(printf '%s' "$json" | jq -r '.ref // ""')
  role=$(printf '%s' "$json" | jq -r '.role // ""')
  if [[ "$role" != "service_role" ]]; then
    echo "::error::SUPABASE_SERVICE_ROLE_KEY role=\"$role\", expected \"service_role\""
    exit 1
  fi
  if [[ -z "$ref" ]]; then
    echo "::error::SUPABASE_SERVICE_ROLE_KEY carries no ref claim — cannot bind project"
    exit 1
  fi
  key_form="jwt"
else
  # Opaque key. Refuse anything that is not recognisably a SECRET key before
  # sending it anywhere — `sb_publishable_…` is the anon-equivalent and must
  # never reach a seeding path.
  case "$SRK" in
    sb_secret_*) ;;
    sb_publishable_*)
      echo "::error::SUPABASE_SERVICE_ROLE_KEY is a PUBLISHABLE key (sb_publishable_…), not a secret key"
      exit 1 ;;
    *)
      echo "::error::SUPABASE_SERVICE_ROLE_KEY is neither a 3-segment JWT nor an sb_secret_… key"
      exit 1 ;;
  esac
  key_form="opaque"
fi

# Retained from the original preflight, NOT dropped as a side effect of the
# compat fix: on a canonical 20-char URL the host's first label IS the ref, so
# a JWT whose ref disagrees is refused before any probe. The probe below
# subsumes this (a foreign key cannot answer 200 against this URL), but a
# security check should not disappear because an unrelated bug was fixed.
# Only reachable on the JWT path; an opaque key carries no ref to compare.
if [[ -n "$ref" && "$is_custom_domain" -eq 0 ]]; then
  url_ref="${url_host%%.*}"
  if [[ "$ref" != "$url_ref" ]]; then
    echo "::error::JWT ref=\"$ref\" does not match URL canonical ref=\"$url_ref\""
    echo "::error::Refusing to seed — this would write to a different Supabase project."
    exit 1
  fi
fi

# Behavioural proof, run for BOTH formats: a JWT's role claim is self-asserted,
# so the probe is what actually establishes the privilege. Read-only.
probe_code=$(curl --disable --noproxy '*' --proto '=https' -g -sS -o /dev/null \
  -w '%{http_code}' --max-time 20 \
  -H "Authorization: Bearer $SRK" -H "apikey: $SRK" \
  "$SB_URL/auth/v1/admin/users?per_page=1" || echo "000")
if [[ "$probe_code" != "200" ]]; then
  echo "::error::service-role probe against $url_host returned HTTP $probe_code (expected 200)."
  echo "::error::The key does not grant admin access to THIS project — refusing to seed."
  exit 1
fi

echo "::notice::Pre-flight OK (DOPPLER_CONFIG=prd, key=$key_form, admin-probe=200, ref=${ref:-<opaque>}, host=$url_host)"

# --- Seed ----------------------------------------------------------------

header_auth="Authorization: Bearer $SRK"
header_api="apikey: $SRK"
header_json="Content-Type: application/json"

# DERIVED from lib/legal/tc-version.ts, never restated. A hand-kept literal
# with a "keep this in sync" comment is the drift shape this repo documents
# repeatedly, and it drifted here: the principal sat at 2.3.0 against a gate
# requiring 2.5.1, so `live-verify` redirected to /accept-terms and timed out
# on a page that could never contain the composer (#7969). The literal was
# CORRECT at the time — what broke was that nothing re-derived it after the
# bump. Extraction failure is fatal: a silently-empty version would PATCH the
# gate column to "" and re-break the harness in the same way.
_seed_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TC_SRC="$_seed_dir/../lib/legal/tc-version.ts"
[[ -f "$TC_SRC" ]] || { echo "::error::tc-version.ts not found at $TC_SRC"; exit 1; }
TC_VERSION="$(sed -n 's/^export const TC_VERSION = "\([^"]*\)";$/\1/p' "$TC_SRC")"
# Anchored on the DECLARATION, not on "a 64-hex literal somewhere in the file",
# and ambiguity is a REFUSAL rather than `head -1`. A second 64-hex constant
# (a TC_PREVIOUS_DOCUMENT_SHA, a formatter reorder) would otherwise yield a
# wrong-but-valid sha256 that the shape check below CANNOT reject — and
# accept_terms writes it into tc_acceptances.document_sha, which is WORM:
# UPDATE is refused outright and the re-run is an ON CONFLICT no-op, so the
# false attestation would be permanent and uncorrectable.
_sha_matches="$(sed -n '/^export const TC_DOCUMENT_SHA/,/;/p' "$TC_SRC" \
  | sed -n 's/.*"\([0-9a-f]\{64\}\)".*/\1/p')"
_sha_count="$(printf '%s\n' "$_sha_matches" | grep -c . || true)"
if [[ "$_sha_count" -ne 1 ]]; then
  echo "::error::TC_DOCUMENT_SHA extraction matched $_sha_count literals, expected exactly 1 —"
  echo "::error::refusing rather than guessing: a wrong SHA lands in a WORM consent ledger."
  exit 1
fi
TC_DOCUMENT_SHA="$_sha_matches"
[[ "$TC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "::error::derived TC_VERSION '\''$TC_VERSION'\'' is not a semver — the extraction is broken"; exit 1; }
[[ "$TC_DOCUMENT_SHA" =~ ^[0-9a-f]{64}$ ]] \
  || { echo "::error::derived TC_DOCUMENT_SHA is not a sha256 — the extraction is broken"; exit 1; }

EMAIL="live-verify@soleur.ai"
# Synthetic, non-resolvable sentinel repo URL. Never cloned/fetched — the app
# only stores the string into conversations.repo_url for Command Center scoping
# (CTO ruling Q3). A real repo would add a GitHub dependency + leak surface for
# zero benefit.
SENTINEL_REPO_URL="https://github.com/soleur-synthetic/verify-harness-sentinel"

# The `email=` query parameter is IGNORED by this endpoint — measured against
# prd: `?email=<addr>&per_page=1` returns byte-identical results to `?per_page=1`
# (the first user overall, not the match). The filtering was therefore happening
# CLIENT-side over a ONE-ITEM page, so the lookup found the principal only when
# it happened to sort first and otherwise reported "not found" — at which point
# the caller below tries to CREATE it. With 17 users in prd that is a ~1-in-17
# chance of working, and the failure mode is an attempted duplicate of a
# production principal, stopped only by the server rejecting it.
#
# So: page through the whole set and match client-side, which is what the code
# already believed it was doing. `x-total-count` bounds the walk, and a set
# larger than the walk is a REFUSAL rather than a silent miss — "not found"
# must never be reachable by looking at only part of the list.
find_user_by_email() {
  local email="$1" per_page=200 page=1 total id
  total=$(curl --disable --noproxy '*' -sfD - -o /dev/null \
    "$SB_URL/auth/v1/admin/users?per_page=1" -H "$header_auth" -H "$header_api" \
    | tr -d '\r' | sed -n 's/^[Xx]-[Tt]otal-[Cc]ount: *//p' | head -1)
  [[ "$total" =~ ^[0-9]+$ ]] || {
    echo "::error::admin users listing returned no x-total-count — cannot bound the search" >&2
    return 1
  }
  local pages=$(( (total + per_page - 1) / per_page ))
  while (( page <= pages )); do
    id=$(curl --disable --noproxy '*' -sf \
      "$SB_URL/auth/v1/admin/users?per_page=$per_page&page=$page" \
      -H "$header_auth" -H "$header_api" \
      | jq -r --arg e "$email" '(.users // []) | map(select(.email == $e)) | .[0].id // ""')
    [[ -n "$id" ]] && { printf '%s' "$id"; return 0; }
    page=$(( page + 1 ))
  done
  printf ''
}

user_id=$(find_user_by_email "$EMAIL")

if [[ -z "$user_id" ]]; then
  echo "Creating $EMAIL..."
  create_response=$(curl --disable --noproxy '*' -sf "$SB_URL/auth/v1/admin/users" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -d "$(jq -nc --arg email "$EMAIL" --arg password "$LIVE_VERIFY_USER_PASSWORD" \
      '{email: $email, password: $password, email_confirm: true}')")
  user_id=$(printf '%s' "$create_response" | jq -r '.id // ""')
  if [[ -z "$user_id" ]]; then
    # Do NOT echo create_response — it can carry tokens/identity payloads.
    echo "::error::Create failed for $EMAIL (admin API returned no id)"
    exit 1
  fi
  echo "  Created."
else
  echo "Refreshing password for $EMAIL..."
  curl --disable --noproxy '*' -sf "$SB_URL/auth/v1/admin/users/$user_id" \
    -X PUT -H "$header_auth" -H "$header_api" -H "$header_json" \
    -d "$(jq -nc --arg password "$LIVE_VERIFY_USER_PASSWORD" \
      '{password: $password, email_confirm: true}')" \
    > /dev/null
  echo "  Updated."
fi

# public.users ladder — clears /setup-key + workspace middleware gates.
# NOTE: tc_accepted_version is deliberately NOT set here. Consent goes through
# public.accept_terms below, the same RPC /api/accept-terms calls, because that
# is what also writes the public.tc_acceptances ledger row. PATCHing the column
# directly records consent with no audit row — measured in prod on the synthetic
# principal: tc_accepted_version set since 2026-06-17, ledger EMPTY (#7969).
echo "  Provisioning public.users row..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/users?id=eq.$user_id" \
  -X PATCH -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: return=minimal" \
  -d "$(jq -nc \
    '{workspace_status: "ready", repo_status: "ready"}')" \
  > /dev/null

# Consent via the RPC the application uses. Idempotent in SQL: the users UPDATE
# is a no-op when the version already matches, and the ledger INSERT is
# ON CONFLICT (user_id, version) DO NOTHING.
echo "  Recording T&C acceptance (v$TC_VERSION) via public.accept_terms..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/rpc/accept_terms" \
  -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
  -d "$(jq -nc --arg uid "$user_id" --arg v "$TC_VERSION" --arg sha "$TC_DOCUMENT_SHA" \
    '{p_user_id: $uid, p_version: $v, p_doc_sha: $sha}')" \
  > /dev/null

# Resolve the solo workspace (handle_new_user trigger sets id == user.id; the
# owner membership row is the authoritative lookup).
workspace_id=$(curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/workspace_members?user_id=eq.$user_id&role=eq.owner&select=workspace_id&limit=1" \
  -H "$header_auth" -H "$header_api" \
  | jq -r '.[0].workspace_id // ""')
if [[ -z "$workspace_id" ]]; then
  echo "::error::No owned workspace membership for $user_id (handle_new_user trigger did not fire?)"
  exit 1
fi

# Mirror repo readiness AND set repo_url on the WORKSPACE row. getCurrentRepoUrl
# (server/current-repo-url.ts) reads workspaces.repo_url; without it,
# createConversation aborts "No connected repository" and the rail check can
# never materialize a conversation (CTO ruling Q3 — the seed-qa-user.sh gap).
echo "  Provisioning workspaces row (repo_url sentinel + repo_status=ready)..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/workspaces?id=eq.$workspace_id" \
  -X PATCH -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: return=minimal" \
  -d "$(jq -nc --arg url "$SENTINEL_REPO_URL" \
    '{repo_status: "ready", repo_url: $url}')" \
  > /dev/null

# Active-workspace binding (#5501). The deployed createConversation
# (server/ws-handler.ts:851) resolves conversations.workspace_id via the
# fail-loud resolveUserWorkspaceBinding (server/agent-session-registry.ts:288),
# which reads user_session_state.current_workspace_id and THROWS when no row
# exists (:316-326) — aborting the INSERT before any conversation persists, so
# the harness can never navigate and emits CANT-RUN:forURL. handle_new_user
# (mig 053) does NOT seed user_session_state, so we must bind it here.
#
# Write the row DIRECTLY via the table endpoint (NOT the set_current_workspace_id
# RPC at mig 079:256: it derives the writer from auth.uid() and RAISEs 28000
# under a service-role caller, mig 079:267). The body mirrors the RPC's own write
# verbatim (INSERT … ON CONFLICT (user_id) DO UPDATE, mig 079:293-298). Service
# role bypasses the SELECT-only RLS (mig 060:41-43); the table has no
# insert/update trigger and no table-level REVOKE FROM service_role.
echo "  Resolving organization_id for the active-workspace binding..."
org_id=$(curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/workspaces?id=eq.$workspace_id&select=organization_id" \
  -H "$header_auth" -H "$header_api" \
  | jq -r '.[0].organization_id // ""')
if [[ -z "$org_id" ]]; then
  echo "::error::No organization_id on workspace $workspace_id (handle_new_user trigger did not provision an org?)"
  exit 1
fi

# POST upsert (NOT a bare PATCH: no row exists yet, so ?user_id=eq.X matches 0
# rows and silently no-ops, leaving the binding absent and the harness broken).
echo "  Binding active workspace (user_session_state upsert)..."
curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/user_session_state?on_conflict=user_id" \
  -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
  -H "Prefer: resolution=merge-duplicates,return=minimal" \
  -d "$(jq -nc \
    --arg uid "$user_id" \
    --arg wid "$workspace_id" \
    --arg oid "$org_id" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{user_id: $uid, current_workspace_id: $wid, current_organization_id: $oid, updated_at: $ts}')" \
  > /dev/null

# Dummy decrypt-poisoned anthropic api_keys row (has-key gate). iv/auth_tag are
# NOT NULL (mig 004); GCM verification can never succeed on these, so any real
# dispatch fails decryption — the row only drives the "key on file" UI state.
existing_key=$(curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/api_keys?user_id=eq.$user_id&provider=eq.anthropic&select=id" \
  -H "$header_auth" -H "$header_api" \
  | jq -r '.[0].id // ""')
if [[ -z "$existing_key" ]]; then
  curl --disable --noproxy '*' -sf "$SB_URL/rest/v1/api_keys" \
    -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
    -H "Prefer: return=minimal" \
    -d "$(jq -nc --arg uid "$user_id" \
      '{user_id: $uid, provider: "anthropic", encrypted_key: "live-verify-dummy-not-real", iv: "bGl2ZS12ZXJpZnktaXY=", auth_tag: "bGl2ZS12ZXJpZnktdGFn", is_valid: true}')" \
    > /dev/null
  echo "  Inserted dummy anthropic api_keys row."
else
  echo "  api_keys row already present."
fi

echo ""
echo "::notice::Synthetic prod principal provisioned (tc=$TC_VERSION, workspace=ready,"
echo "::notice::repo_url sentinel set, dummy anthropic key, NO scope_grants)."
# Only for a human at a terminal. Under Actions these publish the prod project
# ref and the principal UID to a PUBLIC log, and redact.ts has no rule for a
# 20-char ref; the custom domain is precisely what keeps that origin private.
if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
echo "::notice::Set these Doppler prd values for the harness allowlist code-gate:"
echo "::notice::  doppler secrets set LIVE_VERIFY_EXPECTED_UID=$user_id -p soleur -c prd"
echo "::notice::  doppler secrets set LIVE_VERIFY_EXPECTED_REF=$ref -p soleur -c prd"
fi
echo "LIVE_VERIFY_EXPECTED_UID=$user_id"
echo "LIVE_VERIFY_EXPECTED_REF=$ref"
