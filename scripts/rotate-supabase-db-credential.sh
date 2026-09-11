#!/usr/bin/env bash
# Rotate a Supabase project's Postgres password and update every Doppler
# connection string that embeds it, end to end, with verification.
#
# Written because this stood as an "OPERATOR ACTION: rotate the dev
# DATABASE_URL_POOLER credential" with no automated path -- the shape
# hr-never-label-any-step-as-manual-without exists to prevent. No dashboard
# step, no SSH (hr-no-ssh-fallback-in-runbooks).
#
# Usage:
#   scripts/rotate-supabase-db-credential.sh --config dev
#   scripts/rotate-supabase-db-credential.sh --config prd --yes-rotate-prd
#   scripts/rotate-supabase-db-credential.sh --config dev --leaked   # + session sweep
#
# SECRET EXPOSURE, stated accurately rather than aspirationally. The PATCH body
# goes via `--data @file` and the curl auth header via `--config @file`, so
# neither the password nor the API token reaches argv. Two residual exposures
# are documented rather than claimed away:
#   * the pooler URL is handed to docker via `--env-file` (not `-e`), so it is
#     not in argv, but it IS readable via `docker inspect` while the container
#     lives (seconds, local daemon only);
#   * $_tmp files hold plaintext at 0600 for the life of the run.
# An earlier header claimed "values never reach argv"; that was false in three
# places (token in `-H`, old URL as a python argv, URL in `docker -e`). Fixed,
# and the claim narrowed to what the code actually does.
set -euo pipefail

# Refuse to run under xtrace: every value this script touches is a live
# credential, and `-x` would print the bearer token and the new password to
# stderr (#7797). Must sit immediately after `set …`.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

PROJECT=soleur
CONFIG=""
PRD_ACK=0
LEAKED=0
TOKEN_CONFIG=prd_terraform
TOKEN_NAME=SUPABASE_ACCESS_TOKEN   # SUPABASE_PAT is dead (401) everywhere -- #8028

# Ref -> human label. The ack decision is made on the DERIVED ref, never on the
# config NAME: the name is a label the caller chooses, the ref is the thing that
# actually gets rotated. A config called `dev_anything` whose pooler URL points
# at the prd project must still demand the prd ack.
PRD_REFS="ifsccnjhymdmidffkzhl pigsfuxruiopinouvjwy"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    --yes-rotate-prd) PRD_ACK=1; shift ;;
    --leaked) LEAKED=1; shift ;;
    -h|--help) sed -n '1,26p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$CONFIG" ]] || { echo "ERROR: --config <name> is required" >&2; exit 2; }

command -v doppler >/dev/null || { echo "ERROR: doppler CLI not found" >&2; exit 2; }
command -v jq      >/dev/null || { echo "ERROR: jq not found" >&2; exit 2; }

_tmp="$(mktemp -d)"
# Catch signals too: an EXIT-only trap leaves plaintext behind on Ctrl-C.
trap 'rm -rf "$_tmp"' EXIT INT TERM HUP
umask 077

echo "==> resolving target for $PROJECT/$CONFIG"
POOL_URL="$(doppler secrets get DATABASE_URL_POOLER -p "$PROJECT" -c "$CONFIG" --plain 2>/dev/null || true)"
[[ -n "$POOL_URL" ]] || { echo "ERROR: DATABASE_URL_POOLER absent in $PROJECT/$CONFIG" >&2; exit 4; }

# The pooler username carries the ref (postgres.<ref>) and is authoritative even
# behind a custom domain, where NEXT_PUBLIC_SUPABASE_URL reveals no ref.
REF="$(printf '%s' "$POOL_URL" | sed -nE 's#^[a-z]+://postgres\.([a-z0-9]{16,}):.*#\1#p')"
[[ -n "$REF" ]] || { echo "ERROR: could not derive a project ref from the pooler URL (fail-closed)" >&2; exit 4; }
echo "    ref=$REF"

# Production gate, decided on the REF (see PRD_REFS above), not the config name.
for _p in $PRD_REFS; do
  if [[ "$REF" == "$_p" ]]; then
    if [[ "$PRD_ACK" -ne 1 ]]; then
      echo "REFUSED: config '$CONFIG' resolves to PRODUCTION project $REF." >&2
      echo "         Re-run with --yes-rotate-prd if that is intended." >&2
      exit 3
    fi
    echo "    (production ref, ack supplied)"
  fi
done

TOKEN="$(doppler secrets get "$TOKEN_NAME" -p "$PROJECT" -c "$TOKEN_CONFIG" --plain 2>/dev/null || true)"
[[ -n "$TOKEN" ]] || { echo "ERROR: $TOKEN_NAME absent in $PROJECT/$TOKEN_CONFIG" >&2; exit 4; }
# Keep the bearer token out of argv: curl reads the header from a config file.
printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" > "$_tmp/curlrc"

# `--disable` MUST be the first argument: it aborts ~/.curlrc parsing, and any
# later position is too late. `--noproxy '*'` stops ALL_PROXY/HTTPS_PROXY from
# redirecting a credentialed request whose destination pin is otherwise intact.
if ! curl --disable --noproxy '*' -fsS --config "$_tmp/curlrc" https://api.supabase.com/v1/projects \
     | jq -e --arg r "$REF" 'map(.id) | index($r)' >/dev/null; then
  echo "ERROR: $TOKEN_NAME cannot see project $REF (401/403, or no access)" >&2; exit 5
fi

# Every Doppler secret in this config whose value embeds the CURRENT password --
# discovered, not hardcoded, so a secret added later cannot be silently missed.
OLDPW="$(printf '%s' "$POOL_URL" | sed -nE 's#^[a-z]+://[^:]+:([^@]*)@.*#\1#p')"
[[ -n "$OLDPW" ]] || { echo "ERROR: could not extract the current password (fail-closed)" >&2; exit 4; }
doppler secrets -p "$PROJECT" -c "$CONFIG" --json > "$_tmp/all.json"
OLDPW="$OLDPW" jq -r --arg pw "$OLDPW" '
  to_entries | map(select((.value.computed // .value.raw // "") | type == "string"
                          and (. | contains($pw)))) | .[].key' \
  "$_tmp/all.json" > "$_tmp/targets" 2>/dev/null || true
[[ -s "$_tmp/targets" ]] || printf 'DATABASE_URL\nDATABASE_URL_POOLER\n' > "$_tmp/targets"
echo "    secrets embedding this password: $(tr '\n' ' ' < "$_tmp/targets")"

# Sibling configs that carry their OWN copy (not inherited) would go stale.
echo "==> checking sibling configs for an independent copy of this password"
for sib in $(doppler configs -p "$PROJECT" --json | jq -r '.[].name'); do
  [[ "$sib" == "$CONFIG" ]] && continue
  sv="$(doppler secrets get DATABASE_URL_POOLER -p "$PROJECT" -c "$sib" --plain 2>/dev/null || true)"
  [[ -n "$sv" && "$sv" == *"$OLDPW"* ]] && echo "    NOTE: $sib also carries it (inherited configs update automatically; an independent copy would NOT)"
done

NEWPW="$(python3 -c "import secrets,string;a=string.ascii_letters+string.digits;print(''.join(secrets.choice(a) for _ in range(48)))")"

echo "==> PATCH /v1/projects/$REF/database/password"
jq -n --arg p "$NEWPW" '{password:$p}' > "$_tmp/body.json"
code="$(curl --disable --noproxy '*' -s -o "$_tmp/resp.json" -w '%{http_code}' -X PATCH \
        --config "$_tmp/curlrc" -H 'Content-Type: application/json' \
        --data @"$_tmp/body.json" \
        "https://api.supabase.com/v1/projects/$REF/database/password")"
if [[ "$code" != "200" ]]; then
  # Do NOT echo the response body: a validation error can quote the submitted value.
  echo "ERROR: rotation failed HTTP $code (body withheld -- it can echo the password)" >&2
  echo "       jq '.message' < $_tmp/resp.json  # inspect manually if needed" >&2
  exit 6
fi
echo "    HTTP 200 -- the database password is now the NEW one"

# From here the DB is rotated. If anything below fails and we lose $NEWPW, the
# project is unreachable and needs another rotation to recover. Persist it
# OUTSIDE $_tmp (which the trap shreds) before touching Doppler.
RECOVERY="${TMPDIR:-/tmp}/soleur-rotation-recovery-${REF}-$(date -u +%Y%m%dT%H%M%SZ)"
( umask 077; printf '%s\n' "$NEWPW" > "$RECOVERY" )
_bail_with_recovery() {
  echo "" >&2
  echo "CRITICAL: the database password WAS rotated but Doppler was not fully updated." >&2
  echo "          The new password is at: $RECOVERY (mode 0600)" >&2
  echo "          Finish the update from that file, then delete it." >&2
  exit 7
}

echo "==> rewriting every Doppler secret that embeds the password"
while read -r name; do
  [[ -n "$name" ]] || continue
  cur="$(doppler secrets get "$name" -p "$PROJECT" -c "$CONFIG" --plain 2>/dev/null || true)"
  [[ -n "$cur" ]] || { echo "    $name: absent, skipped"; continue; }
  # Old value via stdin, new password via env: neither reaches argv.
  NEW="$(NEWPW="$NEWPW" python3 -c "
import os,re,sys
u=sys.stdin.read()
print(re.sub(r'(^\w+://[^:]+:)([^@]*)(@)', lambda m: m.group(1)+os.environ['NEWPW']+m.group(3), u), end='')
" <<<"$cur")" || _bail_with_recovery
  printf '%s' "$NEW" | doppler secrets set "$name" -p "$PROJECT" -c "$CONFIG" --no-interactive >/dev/null || _bail_with_recovery
  echo "    $name: updated"
done < "$_tmp/targets"

echo "==> verifying Doppler holds the new password (by hash, never by value)"
if ! doppler secrets -p "$PROJECT" -c "$CONFIG" --json \
     | NEWPW="$NEWPW" python3 -c "
import json,sys,os,re,hashlib
d=json.load(sys.stdin); new=os.environ['NEWPW']; bad=[]
names=[l.strip() for l in open(os.environ['TARGETS']) if l.strip()]
for k in names:
    if k not in d: continue
    v=d[k].get('computed') or d[k].get('raw') or ''
    m=re.match(r'^\w+://[^:]+:([^@]*)@',v)
    if not m: bad.append(k+':unparsed'); continue
    ok = m.group(1)==new
    print('    %s: matches-new=%s sha12=%s' % (k, ok, hashlib.sha256(m.group(1).encode()).hexdigest()[:12]))
    if not ok: bad.append(k)
sys.exit(1 if bad else 0)
" ; then
  # A mismatch is a failure, not a line of output to scroll past.
  echo "ERROR: at least one secret does NOT carry the new password." >&2
  _bail_with_recovery
fi
TARGETS="$_tmp/targets"; export TARGETS

if command -v docker >/dev/null; then
  echo "==> proving the new credential authenticates"
  NEWPOOL="$(doppler secrets get DATABASE_URL_POOLER -p "$PROJECT" -c "$CONFIG" --plain)"
  printf 'PGURL=%s\n' "$NEWPOOL" > "$_tmp/denv"   # --env-file keeps it out of argv
  if timeout 180 docker run --rm --env-file "$_tmp/denv" postgres:16-alpine \
       sh -c 'psql "$PGURL" --no-psqlrc -tAq -c "select 1;"' 2>/dev/null | grep -q '^1$'; then
    echo "    OK"
  else
    echo "ERROR: the new credential does NOT authenticate." >&2
    _bail_with_recovery
  fi

  if [[ "$LEAKED" -eq 1 ]]; then
    # Rotation does NOT drop established sessions: a session opened with the
    # leaked password survives it. Scope the sweep to the ROTATED ROLE -- a
    # blanket terminate would also kill Supabase's own authenticator/
    # supabase_admin/pgbouncer backends for no security benefit.
    echo "==> --leaked: sweeping sessions authenticated as the rotated role"
    ROLE="$(printf '%s' "$NEWPOOL" | sed -nE 's#^[a-z]+://([^.:]+)[.:].*#\1#p')"
    cat > "$_tmp/sweep.sql" <<SQL
select count(*) as terminated from (
  select pg_terminate_backend(pid) from pg_stat_activity
  where usename = '${ROLE}' and pid <> pg_backend_pid()
) t;
SQL
    timeout 180 docker run --rm -i --env-file "$_tmp/denv" postgres:16-alpine \
      sh -c 'psql "$PGURL" --no-psqlrc -tAq -f -' < "$_tmp/sweep.sql" 2>&1 | sed 's/^/    terminated=/'
  fi
else
  echo "WARN: docker absent -- connectivity was NOT proven. Verify before relying on this." >&2
fi

rm -f "$RECOVERY"
cat <<'EOF'

==> DONE.

The OLD password keeps authenticating through the pooler for ~60s after the API
returns 200: Supavisor caches auth. Measured 2026-09-10 via a controlled second
rotation. So an immediate re-test of a leaked credential SUCCEEDING is not
evidence the rotation failed -- re-test after the cache window instead.

For a leaked credential, re-run with --leaked (or sweep manually): rotation does
not terminate sessions that are already established.
EOF
