#!/usr/bin/env bash
# End-to-end anon-reachability probes for the soleur-dev Inngest lockdown (0002).
# Invoked by .github/workflows/apply-inngest-rls-dev.yml AFTER the apply + catalog
# gate. Gives Phase 3 (T2/T3/T4.4) an executor — these are NOT hand-run steps.
#
# WHY HTTP AND NOT ONLY THE CATALOG GATE: the catalog gate proves the PRIVILEGES are
# gone. These probes prove the actual front door (PostgREST /rest/v1) — the one an
# anonymous browser caller reaches with the shipped anon key — is closed. The gate is
# the authoritative proof of the TRUNCATE vector (PostgREST has no TRUNCATE verb);
# these probes are the authoritative proof of the reachable read/write path.
#
# ⚠️ `200 []` IS THE BROKEN STATE, NOT THE FIXED ONE. A table with RLS on but the anon
# SELECT grant still present returns `200 []` — it looks locked and is not. A CORRECTLY
# locked table has NO anon SELECT privilege, so PostgREST returns 401/403 with SQLSTATE
# 42501. Asserting `200 []` would encode the bug as the expectation.
#
# ⚠️ THE 204 TRAP: anon DELETE against a zero-policy table returns 204, not 401 — the
# status code proves NOTHING (learning 2026-05-06-rls-zero-policies-anon-delete-204-
# semantic.md). Deny is proven ONLY by an owner read-back of unchanged state.
#
# Reads no repo secret: the anon key is vended by the Management API using the same
# SUPABASE_ACCESS_TOKEN the workflow already holds.
#
# Env: SUPABASE_ACCESS_TOKEN (required), PROJECT_REF (required).
set -uo pipefail

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${PROJECT_REF:?PROJECT_REF is required}"

API="https://api.supabase.com"   # pinned — NO env override (PAT-exfil-via-redirect seam)
REST="https://${PROJECT_REF}.supabase.co/rest/v1"

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

# Mirrors the sibling strip_log_injection in apply-inngest-rls-dev.yml /
# scheduled-inngest-health.yml: the C0/DEL strip alone leaves U+2028/U+2029 (line/
# paragraph separators), U+FEFF (BOM) and U+0085 (NEL) — all of which terminate a line
# in a log viewer. Not exploitable today (every body here comes from a hardcoded path),
# fixed for PARITY so the two scrubbers cannot diverge silently.
# Escape sequences only, never literal separators (cq-regex-unicode-separators-escape-only).
scrub() {
  printf '%s' "$1" \
    | sed -E 's/(eyJ|sbp_)[A-Za-z0-9._-]{10,}/REDACTED/g' \
    | LC_ALL=C tr -d '\000-\037\177' \
    | sed -E 's/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g; s/\xe2\x80\x8b//g; s/\xef\xbb\xbf//g; s/\xc2\x85//g'
}

# owner_query <sql> -> JSON. Runs as `postgres` via the Management API. This is the
# read-back oracle: strictly stronger than a service_role read (it is the table owner
# and bypasses RLS), so "unchanged" here is authoritative.
owner_query() {
  curl --silent --show-error --request POST \
    --url "$API/v1/projects/${PROJECT_REF}/database/query" \
    --header "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "$(jq -nc --arg q "$1" '{query:$q}')" --max-time 30 2>/dev/null
}

echo "anon-probe.sh — PostgREST anon reachability probes for ${PROJECT_REF}"

# --- Fetch the anon key (no new CI secret needed) -----------------------------
# `|| true` INSIDE the substitution: a non-zero curl must not abort the script
# before bad() can report it.
keys_resp="$(curl --silent --url "$API/v1/projects/${PROJECT_REF}/api-keys" \
  --header "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" --max-time 30 2>/dev/null || true)"
ANON_KEY="$(printf '%s' "$keys_resp" | jq -r '.[]? | select(.name=="anon") | .api_key' 2>/dev/null | head -1)"
if [[ -z "$ANON_KEY" || "$ANON_KEY" == "null" ]]; then
  echo "FAIL: could not vend the anon key for ${PROJECT_REF} — cannot probe the client path."
  exit 1
fi
echo "  (anon key vended via Management API; never logged)"

# anon_req <method> <path> [data] -> "<http_code>|<body>"
anon_req() {
  local method="$1" path="$2" data="${3:-}" out
  if [[ -n "$data" ]]; then
    out="$(curl --silent --request "$method" --url "${REST}${path}" \
      --header "apikey: ${ANON_KEY}" --header "Authorization: Bearer ${ANON_KEY}" \
      --header "Content-Type: application/json" --data "$data" \
      --max-time 30 -w $'\n%{http_code}' 2>/dev/null || true)"
  else
    out="$(curl --silent --request "$method" --url "${REST}${path}" \
      --header "apikey: ${ANON_KEY}" --header "Authorization: Bearer ${ANON_KEY}" \
      --max-time 30 -w $'\n%{http_code}' 2>/dev/null || true)"
  fi
  printf '%s|%s' "${out##*$'\n'}" "$(printf '%s' "${out%$'\n'*}" | tr '\n' ' ')"
}

# --- T2: anon READ must be permission-denied ---------------------------------
# Asserted ONLY on `apps` (1 row) and `goose_db_version` (6 rows). The other 12 are
# empty, so they return `200 []` whether locked or not — body inspection proves
# nothing there. Those 12 are proven by the workflow's catalog/grant gate instead.
t2_denied=1
for tbl in apps goose_db_version; do
  r="$(anon_req GET "/${tbl}?select=*&limit=1")"
  code="${r%%|*}"; body="${r#*|}"
  if [[ "$code" == "401" || "$code" == "403" ]] && printf '%s' "$body" | grep -qF '42501'; then
    ok "T2 anon GET /${tbl} -> HTTP ${code} + 42501 (permission denied)"
  elif [[ "$code" == "200" ]]; then
    t2_denied=0
    bad "T2 anon GET /${tbl} -> HTTP 200 — anon STILL READS. (If body is [], that is the BROKEN state: RLS on but the anon SELECT grant remains.) body=$(scrub "$(printf '%s' "$body" | head -c 120)")"
  else
    t2_denied=0
    bad "T2 anon GET /${tbl} -> unexpected HTTP ${code} (expected 401/403 + 42501). body=$(scrub "$(printf '%s' "$body" | head -c 120)")"
  fi
done

# --- T3: anon WRITE must be closed, proven by owner read-back ----------------
# SAFETY INTERLOCK: the write probes below target a REAL row (version_id=0) on
# purpose — a probe against a guaranteed-absent row would leave state unchanged even
# with the grant WIDE OPEN, i.e. it would test curl rather than the lockdown. The
# corollary is that these probes are only safe once anon is provably denied, so T2
# gates them. If T2 did not prove denial we fail loudly WITHOUT attempting a write.
if [[ "$t2_denied" -ne 1 ]]; then
  bad "T3 SKIPPED — anon read was not provably denied; refusing to fire a destructive write probe at a possibly-open table"
else
  base="$(owner_query "select count(*) as n from public.goose_db_version" | jq -r '.[0].n // "err"' 2>/dev/null)"
  base_v0="$(owner_query "select count(*) as n from public.goose_db_version where version_id = 0" | jq -r '.[0].n // "err"' 2>/dev/null)"
  if [[ "$base" == "err" || -z "$base" ]]; then
    bad "T3 could not read the owner baseline for goose_db_version"
  else
    # Minimum-cardinality guard: a zero-row baseline makes "unchanged" vacuous.
    if [[ "$base" -lt 1 || "$base_v0" -lt 1 ]]; then
      bad "T3 baseline is vacuous (count=${base}, version_id=0 rows=${base_v0}) — the probe cannot prove a write was blocked against an empty target"
    else
      ok "T3 owner baseline recorded: goose_db_version count=${base}, version_id=0 present (asserting against the live baseline, not a literal)"

      d="$(anon_req DELETE "/goose_db_version?version_id=eq.0")"
      echo "       (anon DELETE returned HTTP ${d%%|*} — deliberately NOT an assertion: 204 is expected even when denied)"
      i="$(anon_req POST "/goose_db_version" '{"version_id":999999,"is_applied":true}')"
      i_code="${i%%|*}"; i_body="${i#*|}"
      echo "       (anon INSERT returned HTTP ${i_code})"

      after="$(owner_query "select count(*) as n from public.goose_db_version" | jq -r '.[0].n // "err"' 2>/dev/null)"
      after_v0="$(owner_query "select count(*) as n from public.goose_db_version where version_id = 0" | jq -r '.[0].n // "err"' 2>/dev/null)"
      bogus="$(owner_query "select count(*) as n from public.goose_db_version where version_id = 999999" | jq -r '.[0].n // "err"' 2>/dev/null)"

      if [[ "$after" == "$base" && "$after_v0" == "$base_v0" ]]; then
        ok "T3 anon DELETE had NO effect (owner read-back: count ${base}->${after}, version_id=0 rows ${base_v0}->${after_v0}) — this read-back IS the assertion, not the status code"
      else
        bad "T3 anon DELETE MUTATED STATE: count ${base}->${after}, version_id=0 rows ${base_v0}->${after_v0} — anon write is OPEN"
      fi
      if [[ "$bogus" == "0" ]]; then
        ok "T3 anon INSERT had NO effect (owner read-back: no version_id=999999 row)"
      else
        bad "T3 anon INSERT MUTATED STATE: ${bogus} row(s) with version_id=999999 — anon write is OPEN"
      fi
      # WHY the status IS asserted for INSERT but deliberately NOT for DELETE (the 204
      # trap above): `bogus == 0` proves the row is ABSENT, not that anon was DENIED.
      # PostgREST validates the PAYLOAD before the grant gate, so the day goose adds a
      # NOT NULL column to goose_db_version this hardcoded body becomes invalid and the
      # INSERT is rejected 400/422 — the row is absent for the WRONG reason and the
      # read-back passes while proving nothing about anon's privileges. A GRANT denial
      # is 401/403. Asserting that is what makes this a lockdown probe rather than a
      # payload-shape probe. (Unlike DELETE, whose 204-on-deny makes its status
      # meaningless, INSERT's status is a sound discriminator.)
      if [[ "$i_code" == "401" || "$i_code" == "403" ]]; then
        ok "T3 anon INSERT was GRANT-denied (HTTP ${i_code}) — the missing row is proven to be a privilege denial, not a payload rejection"
      else
        bad "T3 anon INSERT returned HTTP ${i_code}, expected 401/403 (grant denial). 400/422 = PostgREST rejected the payload BEFORE the grant gate (has goose_db_version gained a NOT NULL column?) — the absent row then proves nothing. body=$(scrub "$(printf '%s' "$i_body" | head -c 120)")"
      fi
    fi
  fi
fi

# --- T4.4: negative control via the client path ------------------------------
r="$(anon_req GET "/function_runs?select=*&limit=1")"
code="${r%%|*}"; body="${r#*|}"
if [[ "$code" == "401" || "$code" == "403" ]] && printf '%s' "$body" | grep -qF '42501'; then
  ok "T4.4 negative control: anon GET /function_runs -> HTTP ${code} + 42501"
else
  bad "T4.4 negative control: anon GET /function_runs -> HTTP ${code} (expected 401/403 + 42501). body=$(scrub "$(printf '%s' "$body" | head -c 120)")"
fi

echo "---"
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]] || exit 1
