# shellcheck shell=bash
# Egress injector spike (#12517): seeding and probe helpers, sourced after lib/harness.sh and lib/bringup.sh.
# Test path only. Nothing here prints a secret value; keys travel in files, never argv.
#
#   spike_seed_user <label> <var>      -> sets <var> to the new user id (= its personal workspace id; handle_new_user)
#   spike_new_conversation <user id> <var> -> sets <var> to a new conversation id in that user's workspace
# Both set a caller-named variable rather than printing, so a harness_fail inside them ends the suite instead of a
# command-substitution subshell.
#   spike_sign_in <label>              -> writes $SPIKE_WORK/seed/<label>.jwt (the owner's access token)
#   spike_drive <session> <arm> <spec json file on host> <out file>
#                                       runs probes/sdk-egress-driver.mts in the app container for that session
#   spike_stub_since <seq>             -> prints stub records after <seq> (JSON lines)
#   spike_stub_seq                     -> prints the last stub record seq

spike_seed_init() {
  mkdir -p "$SPIKE_WORK/seed" || harness_fail SEED "mkdir"
  ( umask 077 && printf 'apikey: %s\nauthorization: Bearer %s\ncontent-type: application/json\n' "$(cat "$SPIKE_WORK/service-role.key")" "$(cat "$SPIKE_WORK/service-role.key")" > "$SPIKE_WORK/seed/service.headers" ) \
    || harness_fail SEED "service headers"
  ( umask 077 && printf 'apikey: %s\ncontent-type: application/json\n' "$(cat "$SPIKE_WORK/anon.key")" > "$SPIKE_WORK/seed/anon.headers" ) \
    || harness_fail SEED "anon headers"
}

spike_seed_user() {
  local label="$1" var="$2" pw body id
  pw="$(_spike_rand 24)"; mask "$pw"
  _spike_secret_file "$SPIKE_WORK/seed/$label.pw" "$pw"
  body="$(python3 -I -c 'import json, sys; print(json.dumps({"email": sys.argv[1], "password": open(sys.argv[2]).read().strip(), "email_confirm": True}))' \
    "spike-$label-$$@example.invalid" "$SPIKE_WORK/seed/$label.pw")"
  printf '%s' "$body" > "$SPIKE_WORK/seed/$label.req"; chmod 600 "$SPIKE_WORK/seed/$label.req"
  curl -sS --max-time 20 -H @"$SPIKE_WORK/seed/service.headers" --data @"$SPIKE_WORK/seed/$label.req" \
    "$API_URL/auth/v1/admin/users" -o "$SPIKE_WORK/seed/$label.user.json" 2>"$SPIKE_WORK/seed/$label.err" \
    || harness_fail SEED "create user $label: $(head -c 200 "$SPIKE_WORK/seed/$label.err")"
  rm -f "$SPIKE_WORK/seed/$label.req"
  id="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$SPIKE_WORK/seed/$label.user.json" 2>/dev/null)"
  [[ "$id" =~ ^[0-9a-f-]{36}$ ]] || harness_fail SEED "create user $label returned no id"
  # The personal workspace and owner membership come from handle_new_user; confirm rather than assume.
  [[ "$(psql "$DB_URL" -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM public.workspace_members WHERE workspace_id = '$id' AND user_id = '$id' AND role = 'owner'" 2>/dev/null)" == "1" ]] \
    || harness_fail SEED "user $label has no owner membership of workspace $id"
  printf -v "$var" '%s' "$id"
}

spike_new_conversation() {
  local c var="$2"
  c="$(psql "$DB_URL" -X -At -v ON_ERROR_STOP=1 -c "INSERT INTO public.conversations (user_id, workspace_id) VALUES ('$1', '$1') RETURNING id" 2>"$SPIKE_WORK/seed/conv.err" | head -1)"
  [[ "$c" =~ ^[0-9a-f-]{36}$ ]] || harness_fail SEED "conversation insert failed: $(head -c 200 "$SPIKE_WORK/seed/conv.err")"
  printf -v "$var" '%s' "$c"
}

spike_sign_in() {
  local label="$1"
  python3 -I -c 'import json, sys; print(json.dumps({"email": sys.argv[1], "password": open(sys.argv[2]).read().strip()}))' \
    "spike-$label-$$@example.invalid" "$SPIKE_WORK/seed/$label.pw" > "$SPIKE_WORK/seed/$label.signin" && chmod 600 "$SPIKE_WORK/seed/$label.signin"
  curl -sS --max-time 20 -H @"$SPIKE_WORK/seed/anon.headers" --data @"$SPIKE_WORK/seed/$label.signin" \
    "$API_URL/auth/v1/token?grant_type=password" -o "$SPIKE_WORK/seed/$label.token.json" 2>/dev/null \
    || harness_fail SEED "sign-in $label failed"
  rm -f "$SPIKE_WORK/seed/$label.signin"
  python3 -I - "$SPIKE_WORK/seed/$label.token.json" "$SPIKE_WORK/seed/$label.jwt" <<'PY' || harness_fail SEED "sign-in $label returned no access token"
import json, os, sys
t = json.load(open(sys.argv[1])).get("access_token", "")
if not t:
    sys.exit(1)
fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600); os.write(fd, t.encode()); os.close(fd)
PY
  rm -f "$SPIKE_WORK/seed/$label.token.json"
  mask "$(cat "$SPIKE_WORK/seed/$label.jwt")"
}

spike_drive() {
  local sess="$1" arm="$2" spec="$3" outf="$4" name
  name="$(basename "$spec")"
  # Through a root container: the run dir belongs to the app uid, which the host uid need not be.
  docker run --rm -u 0 -v "$spec:/spec.json:ro" -v "$SPIKE_WORK/run/$sess:/r" "$SPIKE_IMG" \
    sh -c "mkdir -p /r/drv && cp /spec.json /r/drv/$name && chown -R $SPIKE_APP_UID:$SPIKE_APP_UID /r/drv" >/dev/null 2>&1 \
    || harness_fail DRIVER "copy spec $name"
  timeout -k 10 420 docker exec -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" /app/node_modules/.bin/tsx --tsconfig /app/tsconfig.json \
    /app/test/infra/egress-injector-spike/probes/sdk-egress-driver.mts "/run/spike/$sess/drv/$name" \
    > "$SPIKE_WORK/drive-$sess-$arm.out" 2> "$SPIKE_WORK/drive-$sess-$arm.err"
  sed -n 's/^SDK_EGRESS_RESULT //p' "$SPIKE_WORK/drive-$sess-$arm.out" | tail -1 > "$outf"
  [[ -s "$outf" ]] || { echo "driver $sess/$arm printed no result: $(grep -v SENTRY "$SPIKE_WORK/drive-$sess-$arm.err" | tail -2 | tr '\n' ' ' | head -c 300)"; return 1; }
}

spike_stub_seq() { python3 -I -c 'import json, sys
n = 0
for l in open(sys.argv[1]):
    if l.strip(): n = max(n, json.loads(l)["seq"])
print(n)' "$SPIKE_STUB_RECORDS"; }

spike_stub_since() { python3 -I -c 'import json, sys
for l in open(sys.argv[1]):
    if l.strip() and json.loads(l)["seq"] > int(sys.argv[2]): print(l.strip())' "$SPIKE_STUB_RECORDS" "$1"; }
