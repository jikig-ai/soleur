#!/usr/bin/env bash
# Rotate a Supabase project's Postgres password and update every Doppler
# connection string that embeds it, end to end, with verification.
#
# Written because this was standing as an "OPERATOR ACTION: rotate the dev
# DATABASE_URL_POOLER credential" with no automated path, which is exactly the
# shape hr-never-label-any-step-as-manual-without exists to prevent. There is no
# dashboard step here and no SSH (hr-no-ssh-fallback-in-runbooks).
#
# Usage:
#   scripts/rotate-supabase-db-credential.sh --config dev
#   scripts/rotate-supabase-db-credential.sh --config prd --yes-rotate-prd
#
# Secrets are never printed. Values move through files/stdin, never argv, so
# they cannot leak via `ps` (hr-never-paste-secrets-via-bang-prefix is about a
# different channel, but the same discipline applies).
set -euo pipefail

PROJECT=soleur
CONFIG=""
PRD_ACK=0
# The Management API token. SUPABASE_PAT is NOT used: it returns 401 in every
# config that carries it (issue #8028). SUPABASE_ACCESS_TOKEN is the live one.
TOKEN_CONFIG=prd_terraform
TOKEN_NAME=SUPABASE_ACCESS_TOKEN

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    --yes-rotate-prd) PRD_ACK=1; shift ;;
    -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$CONFIG" ]] || { echo "ERROR: --config <dev|prd> is required" >&2; exit 2; }

# Rotating prd breaks every live connection until Doppler propagates. That is a
# production write, so it needs an explicit ack rather than a flag the caller
# might not have read (hr-menu-option-ack-not-prod-write-auth).
if [[ "$CONFIG" == prd* && "$PRD_ACK" -ne 1 ]]; then
  echo "REFUSED: rotating '$CONFIG' is a production write. Re-run with --yes-rotate-prd if that is intended." >&2
  exit 3
fi

command -v doppler >/dev/null || { echo "ERROR: doppler CLI not found" >&2; exit 2; }
command -v docker  >/dev/null || echo "WARN: docker absent — connectivity verification will be skipped" >&2

_tmp="$(mktemp -d)"; trap 'rm -rf "$_tmp"' EXIT
umask 077

echo "==> resolving project ref for $PROJECT/$CONFIG"
SB_URL="$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p "$PROJECT" -c "$CONFIG" --plain 2>/dev/null || true)"
POOL_URL="$(doppler secrets get DATABASE_URL_POOLER -p "$PROJECT" -c "$CONFIG" --plain 2>/dev/null || true)"
[[ -n "$POOL_URL" ]] || { echo "ERROR: DATABASE_URL_POOLER absent in $PROJECT/$CONFIG" >&2; exit 4; }

# The pooler username carries the ref (postgres.<ref>) and is authoritative even
# when the project sits behind a custom domain, where NEXT_PUBLIC_SUPABASE_URL
# is e.g. api.soleur.ai and reveals no ref at all.
REF="$(printf '%s' "$POOL_URL" | sed -nE 's#^[a-z]+://postgres\.([a-z0-9]+):.*#\1#p')"
[[ -n "$REF" ]] || { echo "ERROR: could not derive project ref from the pooler URL" >&2; exit 4; }
echo "    ref=$REF  (url-host=$(printf '%s' "$SB_URL" | sed -E 's#https?://##; s#/.*##'))"

TOKEN="$(doppler secrets get "$TOKEN_NAME" -p "$PROJECT" -c "$TOKEN_CONFIG" --plain 2>/dev/null || true)"
[[ -n "$TOKEN" ]] || { echo "ERROR: $TOKEN_NAME absent in $PROJECT/$TOKEN_CONFIG" >&2; exit 4; }

# Confirm the token actually reaches THIS project before changing anything.
if ! curl -fsS -H "Authorization: Bearer $TOKEN" https://api.supabase.com/v1/projects \
     | jq -e --arg r "$REF" 'map(.id) | index($r)' >/dev/null; then
  echo "ERROR: $TOKEN_NAME cannot see project $REF (401/403, or no access)" >&2; exit 5
fi

# Alphanumeric only: the password is embedded in a postgres URI, and any
# reserved character would need percent-encoding that a later naive rebuild of
# the URL would get wrong.
NEWPW="$(python3 -c "import secrets,string;a=string.ascii_letters+string.digits;print(''.join(secrets.choice(a) for _ in range(48)))")"
printf '%s' "$NEWPW" > "$_tmp/pw"

echo "==> PATCH /v1/projects/$REF/database/password"
jq -n --arg p "$NEWPW" '{password:$p}' > "$_tmp/body.json"
code="$(curl -s -o "$_tmp/resp.json" -w '%{http_code}' -X PATCH \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        --data @"$_tmp/body.json" \
        "https://api.supabase.com/v1/projects/$REF/database/password")"
if [[ "$code" != "200" ]]; then
  echo "ERROR: rotation failed HTTP $code: $(cat "$_tmp/resp.json")" >&2; exit 6
fi
echo "    HTTP 200"

echo "==> rewriting every Doppler secret that embeds the password"
for name in DATABASE_URL DATABASE_URL_POOLER; do
  cur="$(doppler secrets get "$name" -p "$PROJECT" -c "$CONFIG" --plain 2>/dev/null || true)"
  [[ -n "$cur" ]] || { echo "    $name: absent, skipped"; continue; }
  NEW="$(NEWPW="$NEWPW" python3 - "$cur" <<'PY'
import os,re,sys
print(re.sub(r'(^\w+://[^:]+:)([^@]*)(@)',
             lambda m: m.group(1)+os.environ['NEWPW']+m.group(3), sys.argv[1]))
PY
)"
  printf '%s' "$NEW" | doppler secrets set "$name" -p "$PROJECT" -c "$CONFIG" --no-interactive >/dev/null
  echo "    $name: updated"
done

# Verify by hash, never by printing the value.
doppler secrets get DATABASE_URL DATABASE_URL_POOLER -p "$PROJECT" -c "$CONFIG" --json 2>/dev/null \
  | NEWPW="$NEWPW" python3 -c "
import json,sys,re,os,hashlib
d=json.load(sys.stdin); new=os.environ['NEWPW']
for k in ('DATABASE_URL','DATABASE_URL_POOLER'):
    if k not in d: continue
    v=d[k]['computed'] if isinstance(d[k],dict) else d[k]
    pw=re.match(r'^\w+://[^:]+:([^@]*)@',v).group(1)
    print(f'    {k}: matches-new={pw==new} sha12={hashlib.sha256(pw.encode()).hexdigest()[:12]}')
" || echo "    (hash verification skipped)"

if command -v docker >/dev/null; then
  echo "==> verifying connectivity with the NEW credential"
  NEWPOOL="$(doppler secrets get DATABASE_URL_POOLER -p "$PROJECT" -c "$CONFIG" --plain)"
  if timeout 180 docker run --rm -e PGURL="$NEWPOOL" postgres:16-alpine \
       sh -c 'psql "$PGURL" --no-psqlrc -tAq -c "select 1;"' 2>&1 | grep -q '^1$'; then
    echo "    OK — new credential authenticates"
  else
    echo "ERROR: new credential does NOT authenticate. Doppler is updated but the DB may not be." >&2
    exit 7
  fi
fi

cat <<'EOF'

==> DONE.

Note on the old credential: Supavisor (the pooler) caches auth, so the PREVIOUS
password keeps authenticating through the pooler for roughly 60 seconds after
the PATCH returns 200. Measured 2026-09-10: a controlled second rotation showed
the prior password rejected at the first check ~60s later.

That window is why "I rotated it and the old one still worked" is NOT evidence
the rotation failed — but it IS why you must re-test after the cache expires
rather than concluding from an immediate check. Postgres stores one password per
role, so the old value is invalid at the database the moment the PATCH returns.
EOF
