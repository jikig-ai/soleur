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
  # A driver that failed reports {"error": ...}; that is a harness failure, never a result with zero steps.
  python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); sys.exit(1 if d.get("error") or not d.get("steps") else 0)' "$outf" \
    || { echo "driver $sess/$arm failed: $(head -c 300 "$outf")"; return 1; }
}

spike_stub_seq() { python3 -I -c 'import json, sys
n = 0
for l in open(sys.argv[1]):
    if l.strip(): n = max(n, json.loads(l)["seq"])
print(n)' "$SPIKE_STUB_RECORDS"; }

spike_stub_since() { python3 -I -c 'import json, sys
for l in open(sys.argv[1]):
    if l.strip() and json.loads(l)["seq"] > int(sys.argv[2]): print(l.strip())' "$SPIKE_STUB_RECORDS" "$1"; }

# spike_spec <out file> <session> <arm A|B> <steps json file> [<extras json file>]: a driver spec for that session.
# The workspace is a fresh synthetic directory under the app user's HOME (never the checkout); the sandbox masks
# /run/spike entirely. Extras (@WS@ substituted): declaredFiles are appended, other keys set.
spike_spec() {
  python3 -I - "$1" "$2" "$3" "$4" "$(cat "$SPIKE_WORK/run/$2/state/router.port")" "${5:-}" <<'PYSPEC' || harness_fail DRIVER "spec $2/$3"
import json, sys
out, sess, arm, steps_file, rp, extras_file = sys.argv[1:7]
steps = json.load(open(steps_file))
ws = f"/home/soleur/spike-{sess}-{arm}-{abs(hash(steps_file)) % 100000}/ws"
for st in steps:  # the steps may name the workspace as @WS@
    st["input"] = json.loads(json.dumps(st["input"]).replace("@WS@", ws))
json.dump({"workspace": ws, "home": "/home/soleur", "routerPort": int(rp),
           "routerCredentialFile": f"/run/spike/{sess}/secrets/router-session.cred",
           "caBundle": f"/run/spike-pub/{sess}/bundle.pem", "arm": arm, "denyReadExtra": ["/run/spike"],
           "declaredFiles": [{"id": f"{s}-{k}", "file": f"/run/spike/{s}/secrets/{f}"}
                             for s in ("sessA", "sessB", "sessC")
                             for k, f in (("decoy", "decoy.token"), ("router-session", "router-session.cred"),
                                          ("router-injector", "router-injector.cred"), ("forwarder", "forwarder.token"))],
           "script": steps, "timeoutMs": 300000}, open(out, "w"))
if extras_file:
    spec = json.load(open(out))
    extras = json.loads(open(extras_file).read().replace("@WS@", ws))
    spec["declaredFiles"] += extras.pop("declaredFiles", [])
    spec.update(extras)
    json.dump(spec, open(out, "w"))
PYSPEC
}

# Criterion 4: allowlisted reads vend with no row; a read outside the allowlist and every read with the flag input
# off are refused. Verdict from the stub's record (which decoy arrived where) and the approval_request row count.
arm_c4() {
  local d="$SPIKE_WORK/c4" seqA seqC
  mkdir -p "$d" || harness_fail DRIVER "mkdir c4"
  cat > "$d/steps.json" <<'JSON'
[
 {"id": "restRead", "tool": "Bash", "input": {"command": "curl -sS -o /dev/null -w 'code=%{http_code}' https://api.github.com/repos/spike/alpha 2>&1"}},
 {"id": "clone", "tool": "Bash", "input": {"command": "git clone -q https://github.com/spike/alpha.git @WS@/c 2>&1 | tail -1; test -d @WS@/c/.git && echo cloned=yes || echo cloned=no"}},
 {"id": "graphqlQuery", "tool": "Bash", "input": {"command": "curl -sS -o /dev/null -w 'code=%{http_code}' -H 'content-type: application/json' --data '{\"query\":\"query Q { viewer { login } }\",\"operationName\":\"Q\"}' https://api.github.com/graphql 2>&1"}},
 {"id": "outsideRead", "tool": "Bash", "input": {"command": "curl -sS -o /dev/null -w 'code=%{http_code}' https://api.github.com/repos/spike/outside 2>&1"}}
]
JSON
  local rows0
  rows0="$(psql "$DB_URL" -X -At -c "SELECT count(*) FROM public.approval_request WHERE conversation_id IN ('$CONV_A', '$CONV_C')" 2>/dev/null)"
  seqA="$(spike_stub_seq)"
  spike_spec "$d/specA.json" sessA B "$d/steps.json"
  spike_drive sessA B "$d/specA.json" "$d/outA.json" || { record_verdict 4 unmeasurable "harness:DRIVER sessA"; return; }
  spike_stub_since "$seqA" > "$d/stubA.jsonl"
  seqC="$(spike_stub_seq)"
  spike_spec "$d/specC.json" sessC B "$d/steps.json"
  spike_drive sessC B "$d/specC.json" "$d/outC.json" || { record_verdict 4 unmeasurable "harness:DRIVER sessC"; return; }
  spike_stub_since "$seqC" > "$d/stubC.jsonl"
  local rows1
  rows1="$(psql "$DB_URL" -X -At -c "SELECT count(*) FROM public.approval_request WHERE conversation_id IN ('$CONV_A', '$CONV_C')" 2>/dev/null)"
  python3 -I - "$d" "$rows0" "$rows1" > "$d/verdict.txt" <<'PYC4'
import json, sys
d, rows0, rows1 = sys.argv[1], sys.argv[2], sys.argv[3]
def load(p): return json.load(open(p))
def lines(p): return [json.loads(l) for l in open(p) if l.strip()]
A, C = load(f"{d}/outA.json"), load(f"{d}/outC.json")
sa, sc = lines(f"{d}/stubA.jsonl"), lines(f"{d}/stubC.jsonl")
step = lambda o, i: next((s for s in o.get("steps", []) if s["id"] == i), {}) .get("content") or ""
def got(recs, host, path_prefix, decoy):
    return any(r["host"] == host and r["path"].startswith(path_prefix) and r["auth_class"] == "real-decoy" and r["decoy_id"] == decoy for r in recs)
obs = {
  "A.restRead": step(A, "restRead"), "A.clone": step(A, "clone"), "A.graphqlQuery": step(A, "graphqlQuery"), "A.outsideRead": step(A, "outsideRead"),
  "C.restRead": step(C, "restRead"), "C.clone": step(C, "clone"), "C.graphqlQuery": step(C, "graphqlQuery"),
  "stub.A.rest": got(sa, "api.github.com", "/repos/spike/alpha", "sessA"),
  "stub.A.git": got(sa, "github.com", "/spike/alpha.git/git-upload-pack", "sessA"),
  "stub.A.graphql": got(sa, "api.github.com", "/graphql", "sessA"),
  "stub.A.outside": any(r["path"].startswith("/repos/spike/outside") for r in sa),
  "stub.C.anyRealDecoy": any(r["auth_class"] == "real-decoy" for r in sc),
  "rows.before": rows0, "rows.after": rows1,
}
checks = {
  "allowlisted REST read vended": "code=200" in obs["A.restRead"] and obs["stub.A.rest"],
  "git clone vended": "cloned=yes" in obs["A.clone"] and obs["stub.A.git"],
  "GraphQL query vended": "code=200" in obs["A.graphqlQuery"] and obs["stub.A.graphql"],
  "read outside the allowlist refused": "code=403" in obs["A.outsideRead"] and not obs["stub.A.outside"],
  "flag off refuses every read": "code=403" in obs["C.restRead"] and "cloned=no" in obs["C.clone"] and "code=403" in obs["C.graphqlQuery"] and not obs["stub.C.anyRealDecoy"],
  # A delta, not an absolute: criterion 3 runs first and leaves rows on conversation A by design.
  "the reads created no approval row": rows0.isdigit() and rows0 == rows1,
}
json.dump({"observations": obs, "checks": checks}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC4
  observe c4 "$d/raw.json"
  spike_record_judged 4 "$d/verdict.txt"
}

# A judge prints `pass|fail` then one observation line. Anything else (a crashed judge) is unmeasurable, never a
# record_verdict refusal that would end the suite without finalizing.
spike_record_judged() {
  local v o
  v="$(sed -n 1p "$2" 2>/dev/null)"; o="$(sed -n 2p "$2" 2>/dev/null)"
  case "$v" in
    pass|fail) [[ -n "$o" ]] && record_verdict "$1" "$v" "$o" || record_verdict "$1" unmeasurable "harness:JUDGE no observation" ;;
    *) record_verdict "$1" unmeasurable "harness:JUDGE produced no verdict" ;;
  esac
}

# Criterion 2 (transport), arms A and B on session A. Arm A is the exact buildAgentEnv output (records where GitHub
# traffic goes); arm B removes the inject hosts from NO_PROXY (#11637's change). Recorded raw for every client; the
# verdict waits on the two clients not built yet (git push with a pre-approved row, and claude streaming).
arm_c2() {
  local d="$SPIKE_WORK/c2" arm seq
  mkdir -p "$d" || harness_fail DRIVER "mkdir c2"
  cat > "$d/steps.json" <<'JSON'
[
 {"id": "clone", "tool": "Bash", "input": {"command": "git clone -q https://github.com/spike/alpha.git @WS@/c 2>&1 | tail -1; test -d @WS@/c/.git && echo cloned=yes || echo cloned=no"}},
 {"id": "fetch", "tool": "Bash", "input": {"command": "git -C @WS@/c fetch -q origin 2>&1 | tail -1; echo fetch_rc=${PIPESTATUS[0]}"}},
 {"id": "ghRest", "tool": "Bash", "input": {"command": "GH_TOKEN=spike-placeholder gh api repos/spike/alpha --jq .full_name 2>&1 | tail -1"}},
 {"id": "ghGraphql", "tool": "Bash", "input": {"command": "GH_TOKEN=spike-placeholder gh api graphql -f query='query Q { viewer { login } }' 2>&1 | tail -1"}},
 {"id": "nodeFetch", "tool": "Bash", "input": {"command": "node -e 'fetch(\"https://api.github.com/repos/spike/alpha\").then(r=>console.log(\"status=\"+r.status)).catch(e=>console.log(\"err=\"+(e.cause?.code||e.message)))' 2>/dev/null"}},
 {"id": "nodeFetchEnvProxy", "tool": "Bash", "input": {"command": "NODE_USE_ENV_PROXY=1 node -e 'fetch(\"https://api.github.com/repos/spike/alpha\").then(r=>console.log(\"status=\"+r.status)).catch(e=>console.log(\"err=\"+(e.cause?.code||e.message)))' 2>/dev/null"}},
 {"id": "curlRest", "tool": "Bash", "input": {"command": "curl -sS -o /dev/null -w 'code=%{http_code}' https://api.github.com/repos/spike/alpha 2>&1"}},
 {"id": "openSse", "tool": "Bash", "input": {"command": "echo events=$(curl -sS -N --max-time 20 https://sse.open-web.spike.test/sse 2>/dev/null | grep -c '^event: tick'); curl -sS -o /dev/null -w 'issuer_verify=%{ssl_verify_result}' https://sse.open-web.spike.test/x 2>&1"}},
 {"id": "tlsLibs", "tool": "Bash", "input": {"command": "curl --version | head -1; git version; ldd $(git --exec-path)/git-remote-https 2>/dev/null | grep -oE 'lib(gnutls|ssl|curl)[^ ]*' | sort -u | tr '\\n' ' '"}}
]
JSON
  for arm in A B; do
    seq="$(spike_stub_seq)"
    local rseq
    rseq="$(docker exec "$SPIKE_APP_CTR" sh -c 'wc -l < /run/spike/sessA/logs/router.log' 2>/dev/null)"
    [[ "$rseq" =~ ^[0-9]+$ ]] || rseq=0
    spike_spec "$d/spec$arm.json" sessA "$arm" "$d/steps.json"
    spike_drive sessA "$arm" "$d/spec$arm.json" "$d/out$arm.json" || { record_verdict 2 unmeasurable "harness:DRIVER arm $arm"; return; }
    spike_stub_since "$seq" > "$d/stub$arm.jsonl"
    docker exec "$SPIKE_APP_CTR" sh -c "tail -n +$((rseq + 1)) /run/spike/sessA/logs/router.log" > "$d/router$arm.log" 2>/dev/null
  done
  python3 -I - "$d" <<'PYC2' > "$d/summary.json" || echo "WARN c2 summary failed"
import json, sys
d = sys.argv[1]
out = {}
for arm in ("A", "B"):
    o = json.load(open(f"{d}/out{arm}.json"))
    recs = [json.loads(l) for l in open(f"{d}/stub{arm}.jsonl") if l.strip()]
    out[arm] = {
        "env": o.get("env"), "steps": {s["id"]: s.get("content") for s in o.get("steps", [])},
        "stub": sorted({f'{r["host"]} {r["method"]} {r["path"]} {r["auth_class"]} {r.get("auth_scheme")}' for r in recs}),
        "router": sorted({" ".join(w for w in l.split() if w.startswith(("branch=", "host=", "status="))) for l in open(f"{d}/router{arm}.log") if l.strip()}),
    }
print(json.dumps(out))
PYC2
  observe c2 "$d/summary.json"
  record_verdict 2 unmeasurable "arm-not-implemented:git-push-with-seeded-approval-and-claude-streaming (raw client outcomes recorded under observations c2)"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 3: gating. Clients run in the app container through the session's router, OUTSIDE bwrap: this arm
# measures the vend decision and the approval lifecycle; transport through the sandbox is criterion 2's.
# ---------------------------------------------------------------------------------------------------------------

# spike_cx <session> <script file> <out file>: run a bash script in the app container with the session's proxy
# (P), CA bundle (CA) and a git config that names no credential helper.
spike_cx() {
  local cred port
  cred="$(docker exec "$SPIKE_APP_CTR" cat "/run/spike/$1/secrets/router-session.cred" 2>/dev/null)" || harness_fail DRIVER "router cred $1"
  port="$(cat "$SPIKE_WORK/run/$1/state/router.port")"
  timeout -k 5 120 docker exec -i -u "$SPIKE_APP_UID" -e "P=http://$cred@127.0.0.1:$port" -e "CA=/run/spike-pub/$1/bundle.pem" \
    -e GIT_CONFIG_GLOBAL=/dev/null -e GIT_CONFIG_NOSYSTEM=1 -e HOME=/home/soleur "$SPIKE_APP_CTR" bash -s < "$2" > "$3" 2>&1
}

spike_rows() { # conversation -> "status:count status:count ..."
  psql "$DB_URL" -X -At -F: -c "SELECT status, count(*) FROM public.approval_request WHERE conversation_id = '$1' GROUP BY status ORDER BY status" 2>/dev/null | tr '\n' ' '
}
spike_latest_pending() { psql "$DB_URL" -X -At -c "SELECT id FROM public.approval_request WHERE conversation_id = '$1' AND status = 'pending' ORDER BY created_at DESC LIMIT 1" 2>/dev/null; }
spike_row_status() { psql "$DB_URL" -X -At -c "SELECT status FROM public.approval_request WHERE id = '$1'" 2>/dev/null; }

# spike_decide <owner label> <approval id> <approve|deny>: decide_approval with the owner's JWT from a real sign-in.
spike_decide() {
  local h="$SPIKE_WORK/seed/$1.decide.headers"
  ( umask 077 && printf 'apikey: %s\nauthorization: Bearer %s\ncontent-type: application/json\n' "$(cat "$SPIKE_WORK/anon.key")" "$(cat "$SPIKE_WORK/seed/$1.jwt")" > "$h" )
  curl -sS --max-time 20 -H @"$h" --data "{\"p_id\":\"$2\",\"p_decision\":\"$3\"}" "$API_URL/rest/v1/rpc/decide_approval" -o "$SPIKE_WORK/decide.out" -w '%{http_code}' 2>/dev/null
}

spike_hook_markers_since() { # line offset -> hook output after it
  docker logs "$SPIKE_HOOK_CTR" 2>&1 | tail -n +"$(( $1 + 1 ))"
}
spike_hook_lines() { docker logs "$SPIKE_HOOK_CTR" 2>&1 | wc -l; }

# The push script: one working copy per (session, name); `MSG` names the commit; a new MSG is a new hash.
_c3_push_script() { # <session> <name> <msg> <out script file>
  cat > "$4" <<EOS
w=/home/soleur/c3-$1-$2
if [ ! -d "\$w/.git" ]; then HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git clone -q https://github.com/spike/alpha.git "\$w" 2>&1 | tail -1; fi
cd "\$w" || { echo push_rc=clone-failed; exit 0; }
if ! git log --format=%s | grep -qx "$3"; then git -c user.email=spike@example.invalid -c user.name=spike commit -q --allow-empty -m "$3"; fi
HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git push -q origin HEAD:main 2>&1 | tail -2
echo push_rc=\${PIPESTATUS[0]}
EOS
}

# Starts the expiry arm (session E, rows created with a 60 s TTL). Returns at once; arm_c3 finishes it.
arm_c3_expiry_start() {
  mkdir -p "$SPIKE_WORK/c3" || harness_fail DRIVER "mkdir c3"
  _c3_push_script sessE exp "expiry e1" "$SPIKE_WORK/c3/exp.sh"
  spike_cx sessE "$SPIKE_WORK/c3/exp.sh" "$SPIKE_WORK/c3/exp1.out"
  C3_EXP_ID="$(spike_latest_pending "$CONV_E")"
  C3_EXP_T0="$(date +%s)"
}

arm_c3() {
  local d="$SPIKE_WORK/c3" seq h0 p1 p2 x id obs="$SPIKE_WORK/c3/obs.jsonl"
  mkdir -p "$d" && : > "$obs" || harness_fail DRIVER "mkdir c3"
  note() { python3 -I -c 'import json, sys; print(json.dumps({"k": sys.argv[1], "v": sys.argv[2]}))' "$1" "$2" >> "$obs"; }
  h0="$(spike_hook_lines)"
  seq="$(spike_stub_seq)"

  # Push lifecycle on session A (CTO R16).
  _c3_push_script sessA life "life 1" "$d/l1.sh"
  spike_cx sessA "$d/l1.sh" "$d/l1a.out"; note push1 "$(tail -1 "$d/l1a.out")"; note rows1 "$(spike_rows "$CONV_A")"
  note stub1_receivepack "$(spike_stub_since "$seq" | grep -c '"path":"/spike/alpha.git/git-receive-pack"')"
  spike_cx sessA "$d/l1.sh" "$d/l1b.out"; note push1_retry "$(tail -1 "$d/l1b.out")"; note rows1_retry "$(spike_rows "$CONV_A")"
  p1="$(spike_latest_pending "$CONV_A")"; note p1 "${p1:+present}"
  note deny "$(spike_decide ownerA "$p1" deny)"
  spike_cx sessA "$d/l1.sh" "$d/l1c.out"; note push1_after_deny "$(tail -1 "$d/l1c.out")"; note rows_after_deny "$(spike_rows "$CONV_A")"
  p2="$(spike_latest_pending "$CONV_A")"; note p2_new "$([[ -n "$p2" && "$p2" != "$p1" ]] && echo yes || echo no)"
  seq="$(spike_stub_seq)"
  note approve "$(spike_decide ownerA "$p2" approve)"
  spike_cx sessA "$d/l1.sh" "$d/l1d.out"; note push1_approved "$(tail -1 "$d/l1d.out")"; note p2_status "$(spike_row_status "$p2")"
  note stub_after_approve "$(spike_stub_since "$seq" | grep '"path":"/spike/alpha.git/git-receive-pack"' | grep -c '"auth_class":"real-decoy"')"
  seq="$(spike_stub_seq)"
  _c3_push_script sessA life "life 2" "$d/l2.sh"
  spike_cx sessA "$d/l2.sh" "$d/l2.out"; note push2_new_hash "$(tail -1 "$d/l2.out")"; note rows_end "$(spike_rows "$CONV_A")"
  note stub_push2 "$(spike_stub_since "$seq" | grep '"path":"/spike/alpha.git/git-receive-pack"' | grep -c '"auth_class":"real-decoy"')"

  # REST binding (CPO C4): a row approved for body X does not authorize body Y, another path, or another repo.
  cat > "$d/rest.sh" <<'EOS'
post() { curl -sS -o /dev/null -w "$1=%{http_code}\n" --cacert "$CA" -x "$P" -H 'content-type: application/json' ${3:+-H "$3"} --data "$2" "https://api.github.com$4"; }
case "$STEP" in
  x1) post x1 '{"title":"spike X","head":"a","base":"main"}' '' /repos/spike/alpha/pulls ;;
  y1) post y1 '{"title":"spike Y","head":"a","base":"main"}' '' /repos/spike/alpha/pulls ;;
  zpath) post zpath '{"title":"spike X","head":"a","base":"main"}' '' /repos/spike/alpha/issues/1/comments ;;
  zrepo) post zrepo '{"title":"spike X","head":"a","base":"main"}' '' /repos/spike/outside/pulls ;;
  x2) post x2 '{"title":"spike X","head":"a","base":"main"}' 'Idempotency-Key: spike-1' /repos/spike/alpha/pulls ;;
  x3) post x3 '{"title":"spike X","head":"a","base":"main"}' 'Idempotency-Key: spike-1' /repos/spike/alpha/pulls ;;
esac
EOS
  rest() { { echo "STEP=$1"; cat "$d/rest.sh"; } > "$d/rest-$1.sh"; spike_cx sessA "$d/rest-$1.sh" "$d/rest-$1.out"; note "rest_$1" "$(tail -1 "$d/rest-$1.out")"; }
  seq="$(spike_stub_seq)"
  rest x1; x="$(spike_latest_pending "$CONV_A")"; note approve_x "$(spike_decide ownerA "$x" approve)"
  rest y1; rest zpath; rest zrepo
  note stub_binding_misses "$(spike_stub_since "$seq" | grep '"method":"POST"' | grep -c '"auth_class":"real-decoy"')"
  rest x2; note x_status "$(spike_row_status "$x")"
  note stub_x2 "$(spike_stub_since "$seq" | grep '"method":"POST"' | grep '"auth_class":"real-decoy"' | head -1)"
  rest x3

  # Flag input off (session C): a listed write is refused flag-off, with no row.
  _c3_push_script sessC off "flag off" "$d/off.sh"
  spike_cx sessC "$d/off.sh" "$d/off.out"; note push_flag_off "$(tail -1 "$d/off.out")"; note rows_c "$(spike_rows "$CONV_C")"

  # Expiry (session E, 60 s TTL started at topology-ready): pending near 50 s, then expired, then REJECT expired.
  local waited=$(( $(date +%s) - C3_EXP_T0 ))
  (( waited < 50 )) && sleep $(( 50 - waited ))
  note exp_at_50s "$(spike_row_status "$C3_EXP_ID")"
  waited=$(( $(date +%s) - C3_EXP_T0 )); (( waited < 66 )) && sleep $(( 66 - waited ))
  spike_cx sessE "$d/exp.sh" "$d/exp2.out"; note push_after_expiry "$(tail -1 "$d/exp2.out")"; note exp_final "$(spike_row_status "$C3_EXP_ID")"
  # Diagnostics for the expiry path (no secrets: git's own messages, marker fields, iron-proxy audit fields).
  note exp1_out "$(tr '\n' ' ' < "$SPIKE_WORK/c3/exp1.out" | head -c 400)"
  note exp2_out "$(tr '\n' ' ' < "$d/exp2.out" | head -c 400)"
  note exp_id "${C3_EXP_ID:+present}"
  note exp_rows "$(spike_rows "$CONV_E")"
  note exp_markers "$(docker logs "$SPIKE_HOOK_CTR" 2>&1 | grep 'session=sessE ' | sed -E 's/ request_id=[^ ]+//; s/ action_sha256=[^ ]+//; s/ approval_id=[0-9a-f-]+/ approval_id=<id>/' | tail -6 | tr '\n' '|')"
  note exp_iron "$(docker exec "$SPIKE_APP_CTR" sh -c 'tail -c 20000 /run/spike/sessE/logs/iron-proxy.log' 2>/dev/null | tr -d '\000' | python3 -I "$SPIKE_DIR/lib/iron-audit.py" 6 2>/dev/null)"

  spike_hook_markers_since "$h0" | grep -E '^SOLEUR_EGRESS_VEND' | sed -E 's/ request_id=[^ ]+//; s/ action_sha256=[^ ]+//; s/ approval_id=[0-9a-f-]+/ approval_id=<id>/' > "$d/markers.txt"
  python3 -I - "$d" > "$d/verdict.txt" <<'PYC3'
import json, sys
d = sys.argv[1]
o = {}
for l in open(f"{d}/obs.jsonl"):
    r = json.loads(l); o[r["k"]] = r["v"]
m = open(f"{d}/markers.txt").read().splitlines()
def reasons(sess):
    return [x.split(" reason=")[1].split()[0] for x in m if f"session={sess} " in x and " reason=" in x]
def vends(sess, cls):
    return [x for x in m if x.startswith("SOLEUR_EGRESS_VEND ") and f"session={sess} " in x and f"class={cls} " in x]
ra, rc, re_ = reasons("sessA"), reasons("sessC"), reasons("sessE")
pend = lambda s: int(dict(p.split(":") for p in s.split()).get("pending", 0)) if s.strip() else 0
checks = {
  "no row: push refused pending, one pending row": o["push1"] != "push_rc=0" and "pending" in ra and pend(o["rows1"]) == 1,
  "no real token on the refused POST git-receive-pack": o["stub1_receivepack"] == "0",
  "retry before decision keeps one row": o["push1_retry"] != "push_rc=0" and o["rows1"] == o["rows1_retry"],
  "owner deny -> rejected reported, then a new pending row": o["deny"] == "200" and "rejected" in ra and o["p2_new"] == "yes",
  "approve -> vend, consumed exactly once": o["approve"] == "200" and o["push1_approved"] == "push_rc=0" and o["p2_status"] == "consumed" and o["stub_after_approve"] == "1",
  "a new hash after consume needs a new row": o["push2_new_hash"] != "push_rc=0" and o["stub_push2"] == "0",
  "REST X pending, then approved": o["rest_x1"] == "x1=403" and o["approve_x"] == "200",
  "binding: body Y, another path, another repo get no real token": o["rest_y1"] == "y1=403" and o["rest_zpath"] == "zpath=403" and o["rest_zrepo"] == "zrepo=403" and o["stub_binding_misses"] == "0",
  "approved X consumed once, Idempotency-Key stripped": o["rest_x2"] == "x2=201" and o["x_status"] == "consumed" and '"idempotency_key":false' in o["stub_x2"] and o["rest_x3"] == "x3=403",
  "flag off: refused flag-off, no row": o["push_flag_off"] != "push_rc=0" and "flag-off" in rc and o["rows_c"].strip() == "",
  "expiry: pending at ~50 s, then REJECT expired": o["exp_at_50s"] == "pending" and "expired" in re_ and o["exp_final"] == "expired",
}
json.dump({"observations": o, "reasons": {"sessA": ra, "sessC": rc, "sessE": re_}, "checks": checks}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC3
  observe c3 "$d/raw.json"
  spike_record_judged 3 "$d/verdict.txt"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 5: session A cannot obtain session B's credential. Run as the harness in the app container (outside
# bwrap), presenting every A-side identity at every B-side door; B's own read is the control that B's chain works.
# ---------------------------------------------------------------------------------------------------------------
arm_c5() {
  local d="$SPIKE_WORK/c5" seqB seqA ra rb tb
  mkdir -p "$d" || harness_fail DRIVER "mkdir c5"
  ra="$(cat "$SPIKE_WORK/run/sessA/state/router.port")"; rb="$(cat "$SPIKE_WORK/run/sessB/state/router.port")"
  tb="$SPIKE_SESS_sessB_TUNNEL"
  cat > "$d/c5.sh" <<EOS
A=/run/spike/sessA; B=/run/spike/sessB; H=/app/test/infra/egress-injector-spike/probes/hook-client.mjs
acred=\$(cat \$A/secrets/router-session.cred); bcred=\$(cat \$B/secrets/router-session.cred); ainj=\$(cat \$A/secrets/router-injector.cred)
bdecoy=\$(cat \$B/secrets/decoy.token)
c() { curl -sS -o /dev/null --max-time 15 -w "\$1=%{http_code} connect=%{http_connect} exit=" "\${@:2}" 2>/dev/null; echo \$?; }
case "\$PHASE" in
control)
  c bControl --cacert /run/spike-pub/sessB/bundle.pem -x "http://\$bcred@127.0.0.1:$rb" https://api.github.com/repos/spike/beta ;;
probes)
  c aCarriesBToken --cacert /run/spike-pub/sessA/bundle.pem -x "http://\$acred@127.0.0.1:$ra" -H "Authorization: token \$bdecoy" https://api.github.com/repos/spike/alpha
  c aCarriesBTokenToB --cacert /run/spike-pub/sessA/bundle.pem -x "http://\$acred@127.0.0.1:$ra" -H "Authorization: token \$bdecoy" https://api.github.com/repos/spike/beta
  c bProxyCredAtARouter --cacert /run/spike-pub/sessA/bundle.pem -x "http://\$bcred@127.0.0.1:$ra" https://api.github.com/repos/spike/beta
  c aCredAtBRouter --cacert /run/spike-pub/sessB/bundle.pem -x "http://\$acred@127.0.0.1:$rb" https://api.github.com/repos/spike/beta
  c aRouterCredAtBInjector --cacert /run/spike-pub/sessB/bundle.pem -x "http://\$ainj@127.0.0.1:$tb" https://api.github.com/repos/spike/beta
  c aCaAtBInjector --cacert /run/spike-pub/sessA/bundle.pem -x "http://\$bcred@127.0.0.1:$rb" https://api.github.com/repos/spike/beta
  echo "aHookCertOnB \$(node \$H \$B/hook/hook.sock \$A/hookclient/client.pem \$A/hookclient/client.key \$B/hookclient/server-root.pem api.github.com /repos/spike/beta)"
  echo "bHookCertOnB \$(node \$H \$B/hook/hook.sock \$B/hookclient/client.pem \$B/hookclient/client.key \$B/hookclient/server-root.pem api.github.com /repos/spike/beta)"
  cd /tmp && openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -keyout c5o.key -out c5o.pem -days 1 -subj "/CN=$CONV_B" 2>/dev/null
  echo "otherRootOnB \$(node \$H \$B/hook/hook.sock /tmp/c5o.pem /tmp/c5o.key \$B/hookclient/server-root.pem api.github.com /repos/spike/beta)"
  rm -f /tmp/c5o.key /tmp/c5o.pem ;;
esac
EOS
  seqB="$(spike_stub_seq)"
  docker exec -i -u "$SPIKE_APP_UID" -e PHASE=control "$SPIKE_APP_CTR" bash -s < "$d/c5.sh" > "$d/control.out" 2>&1
  spike_stub_since "$seqB" > "$d/stubControl.jsonl"
  seqA="$(spike_stub_seq)"
  docker exec -i -u "$SPIKE_APP_UID" -e PHASE=probes "$SPIKE_APP_CTR" bash -s < "$d/c5.sh" > "$d/probes.out" 2>&1
  spike_stub_since "$seqA" > "$d/stubProbes.jsonl"
  python3 -I - "$d" > "$d/verdict.txt" <<'PYC5'
import json, re, sys
d = sys.argv[1]
o = {}
for f in ("control.out", "probes.out"):
    for line in open(f"{d}/{f}"):
        m = re.match(r"^([A-Za-z]+)=(\d{3}) connect=(\d{3}) exit=(\d+)$", line.strip())
        if m: o[m.group(1)] = {"http": m.group(2), "connect": m.group(3), "exit": int(m.group(4))}
        m2 = re.match(r"^([A-Za-z]+) (HOOK_CLIENT .*)$", line.strip())
        if m2: o[m2.group(1)] = m2.group(2)
ctl = [json.loads(l) for l in open(f"{d}/stubControl.jsonl") if l.strip()]
prb = [json.loads(l) for l in open(f"{d}/stubProbes.jsonl") if l.strip()]
g = lambda k: o.get(k, {}) if isinstance(o.get(k), dict) else {}
checks = {
  "control: B reaches the stub with B's own token": g("bControl").get("http") == "200" and any(r["decoy_id"] == "sessB" for r in ctl),
  "A carrying B's token: the injector replaces it with A's own": g("aCarriesBToken").get("http") == "200" and any(r["decoy_id"] == "sessA" and r["path"] == "/repos/spike/alpha" for r in prb),
  "A carrying B's token to B's repository is refused": g("aCarriesBTokenToB").get("http") == "403",
  "B's proxy credential at A's router: 407": g("bProxyCredAtARouter").get("connect") == "407",
  "A's credential at B's router: 407": g("aCredAtBRouter").get("connect") == "407",
  "A's router credential at B's injector: 407": g("aRouterCredAtBInjector").get("connect") == "407",
  "A's CA does not verify B's injector (TLS refused)": g("aCaAtBInjector").get("exit") == 60,
  "A's hook client certificate on B's socket is refused": str(o.get("aHookCertOnB", "")).startswith("HOOK_CLIENT action=REJECT status=403"),
  "control: B's own hook certificate is accepted": str(o.get("bHookCertOnB", "")).startswith("HOOK_CLIENT action=CONTINUE"),
  "a certificate from another root is refused at TLS": str(o.get("otherRootOnB", "")).startswith("HOOK_CLIENT error="),
  "the stub never recorded B's token during A's probes": not any(r["decoy_id"] == "sessB" for r in prb),
}
json.dump({"observations": o, "checks": checks}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC5
  observe c5 "$d/raw.json"
  spike_record_judged 5 "$d/verdict.txt"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 9: CA scope (spec TR3). Leaves signed by session A's CA (and one by B's) are served on container loopback
# by openssl s_server; each client is tried against each, with session A's bundle and no proxy (TLS verification
# is the client library's, so this runs outside bwrap). The libraries each client links are recorded first.
# ---------------------------------------------------------------------------------------------------------------
_c9_leaf_cn_only() { # <ca dir> <out prefix> <cn>
  ( umask 077 && openssl ecparam -name prime256v1 -genkey -noout -out "$2.key" ) 2>/dev/null \
    && openssl req -new -key "$2.key" -subj "/CN=$3" -out "$2.csr" 2>/dev/null \
    && printf 'extendedKeyUsage=serverAuth\nbasicConstraints=critical,CA:FALSE\n' > "$2.ext" \
    && openssl x509 -req -in "$2.csr" -CA "$1/ca.pem" -CAkey "$1/ca.key" -CAcreateserial -days 1 -sha256 -extfile "$2.ext" -out "$2.pem" 2>/dev/null \
    && rm -f "$2.csr" "$2.ext"
}

arm_c9() {
  local d="$SPIKE_WORK/c9" L="$SPIKE_WORK/run/c9"
  mkdir -p "$d" "$L" || harness_fail DRIVER "mkdir c9"
  local ca="$SPIKE_WORK/run/sessA/ca" cab="$SPIKE_WORK/run/sessB/ca"
  mint_leaf "$ca" "$L/inject" "DNS:api.github.com" && mint_leaf "$ca" "$L/noninject" "DNS:evil.example" \
    && mint_leaf "$ca" "$L/gist" "DNS:gist.github.com" && mint_leaf "$ca" "$L/ip" "IP:127.0.0.1" \
    && _c9_leaf_cn_only "$ca" "$L/cnonly" "api.github.com" && _c9_leaf_cn_only "$ca" "$L/cnonlynon" "evil.example" \
    && mint_leaf "$cab" "$L/crossb" "DNS:api.github.com" \
    || { record_verdict 9 unmeasurable "harness:LEAF_MINT"; return; }
  spike_fix_owner "$L"
  local fa fb
  fa="$(openssl x509 -in "$ca/ca.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
  fb="$(openssl x509 -in "$cab/ca.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
  local inj tun
  inj="$(docker exec "$SPIKE_APP_CTR" cat /run/spike/sessA/secrets/router-injector.cred 2>/dev/null)"; tun="$SPIKE_SESS_sessA_TUNNEL"
  cat > "$d/c9.sh" <<'EOS'
L=/run/spike/c9; BUNDLE=/run/spike-pub/sessA/bundle.pem; port=19400
echo "lib curl $(curl --version | head -1 | grep -oE '(OpenSSL|GnuTLS)/[0-9.]+' | head -1)"
echo "lib git $(ldd "$(git --exec-path)/git-remote-https" 2>/dev/null | grep -oE 'lib(gnutls|ssl)[^ ]*' | sort -u | tr '\n' ' ')"
echo "lib node openssl/$(node -p process.versions.openssl)"
try() { # <leaf> <request host> [<label>]
  port=$((port + 1)); local lab="${3:-$1}" h="$2"
  openssl s_server -quiet -accept "127.0.0.1:$port" -cert "$L/$1.pem" -key "$L/$1.key" -www >/dev/null 2>&1 & local sp=$!
  for _ in $(seq 1 30); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; sleep 0.1; done
  local hc="$h"; [ "$h" = "127.0.0.1" ] && hc=127.0.0.1
  curl -sS -o /dev/null --max-time 8 --noproxy '*' --cacert "$BUNDLE" --connect-to "$hc:$port:127.0.0.1:$port" "https://$hc:$port/" 2>/dev/null; echo "res $lab curl $([ $? -eq 0 ] && echo accept || echo reject)"
  local ge; ge="$(GIT_SSL_CAINFO="$BUNDLE" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 timeout 10 git -c "http.curloptResolve=$hc:$port:127.0.0.1" ls-remote "https://$hc:$port/x.git" 2>&1)"
  # accept only on an HTTP-level answer from the server, so a refused connection can never read as accepted
  if printf '%s' "$ge" | grep -qiE 'certificate|ssl|tls'; then echo "res $lab git reject"
  elif printf '%s' "$ge" | grep -qiE 'not found|not valid|repository|returned error|http'; then echo "res $lab git accept"
  else echo "res $lab git unknown"; fi
  NODE_EXTRA_CA_CERTS="$BUNDLE" timeout 10 node -e 'const [h,p]=process.argv.slice(1); require("https").get({host:"127.0.0.1",port:+p,servername:h==="127.0.0.1"?undefined:h,headers:{host:h}},r=>{console.log("accept");process.exit(0)}).on("error",e=>{console.log("reject "+e.code);process.exit(0)})' "$hc" "$port" 2>/dev/null | sed "s/^/res $lab node /"
  kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
}
try inject api.github.com
try inject API.GitHub.com mixedcase
try noninject evil.example
try gist gist.github.com
try ip 127.0.0.1
try cnonly api.github.com
try cnonlynon evil.example
try crossb api.github.com
EOS
  docker exec -i -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" bash -s < "$d/c9.sh" > "$d/tls.out" 2>&1
  # A non-inject CONNECT forced straight at session A's injector (skipping the router): the allowlist refuses it.
  docker exec -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" curl -sS -o /dev/null --max-time 10 -w '%{http_connect}' --cacert /run/spike-pub/sessA/bundle.pem \
    -x "http://$inj@127.0.0.1:$tun" https://sse.open-web.spike.test/ > "$d/forced.out" 2>/dev/null
  # The CA key exists while session E runs (control), and is gone once its session has ended on its own.
  local key_before key_after i
  key_before="$(docker exec "$SPIKE_APP_CTR" sh -c 'test -s /run/spike/sessE/ca/ca.key && echo present || echo absent')"
  docker exec "$SPIKE_APP_CTR" rm -f /run/spike/sessE/state/run
  for ((i = 0; i < 100; i++)); do docker exec "$SPIKE_APP_CTR" test -e /run/spike/sessE/state/ended && break; sleep 0.2; done
  key_after="$(docker exec "$SPIKE_APP_CTR" sh -c 'test -e /run/spike/sessE/ca/ca.key && echo present || echo absent')"
  python3 -I - "$d" "$fa" "$fb" "$key_before" "$key_after" "$SPIKE_WORK/run/sessB" "$SPIKE_WORK/c2" > "$d/verdict.txt" <<'PYC9'
import json, os, re, subprocess, sys
d, fa, fb, kb, ka, sessb, c2 = sys.argv[1:8]
res, libs = {}, {}
for line in open(f"{d}/tls.out"):
    p = line.split()
    if p[:1] == ["res"] and len(p) >= 4: res[f"{p[1]}.{p[2]}"] = p[3]
    if p[:1] == ["lib"]: libs[p[1]] = " ".join(p[2:])
bundle_b = open(f"{sessb}/../../pub/sessB/bundle.pem").read() if os.path.exists(f"{sessb}/../../pub/sessB/bundle.pem") else ""
fp_in_b = False
for blk in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", bundle_b, re.S):
    out = subprocess.run(["openssl", "x509", "-noout", "-fingerprint", "-sha256"], input=blk, capture_output=True, text=True).stdout
    if fa in out: fp_in_b = True
forced = open(f"{d}/forced.out").read().strip()
r2 = ""
for arm in ("A", "B"):
    p = f"{c2}/router{arm}.log"
    if os.path.exists(p): r2 += open(p).read()
clients = ("curl", "git", "node")
all_ = lambda leaf, want: all(res.get(f"{leaf}.{c}", "").startswith(want) for c in clients)
gnutls_clients = [c for c in clients if "gnutls" in libs.get(c, "").lower()]
checks = {
  "control: every client accepts a session-CA leaf for an inject host": all_("inject", "accept"),
  "every client rejects a session-CA leaf for a non-inject name": all_("noninject", "reject"),
  "gist.github.com is accepted (within the documented *.github.com scope)": all_("gist", "accept"),
  "an IP-address leaf is rejected": all_("ip", "reject"),
  # Measured 2026-11-10: every client ACCEPTS a CN-only leaf for an inject host (a name the constraints permit) and
  # REJECTS a CN-only leaf for a non-inject name, so CN fallback does not escape the name constraints. The scope
  # property is the second; the first is recorded (results note, for the CTO to rule on the plan's wording).
  "a common-name-only leaf for a non-inject name is rejected (CN fallback stays constrained)": all_("cnonlynon", "reject"),
  "session B's CA is not trusted in session A": all_("crossb", "reject"),
  "the two sessions have distinct CAs, and A's is not in B's bundle": fa != fb and bundle_b != "" and not fp_in_b,
  "a non-inject CONNECT forced at the injector is refused 403 by the allowlist": forced == "403",
  "the non-inject SSE took the router's forwarder branch, never the injector": "branch=forwarder host=sse.open-web.spike.test" in r2 and "branch=injector host=sse.open-web.spike.test" not in r2,
  "the CA key exists during the session and is absent after it ends": kb == "present" and ka == "absent",
}
# Record only (plan): a GnuTLS client rejecting a mixed-case inject name is that client's defect, not a constraint
# failure, so it never fails the criterion.
mixed = {c: res.get(f"mixedcase.{c}", "") for c in gnutls_clients}
cn_only_inject = {c: res.get(f"cnonly.{c}", "") for c in clients}
json.dump({"libraries": libs, "results": res, "mixed_case_gnutls": mixed, "cn_only_inject_host": cn_only_inject, "forced_connect": forced, "checks": checks}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC9
  observe c9 "$d/raw.json"
  spike_record_judged 9 "$d/verdict.txt"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 7: one new GitHub verb touches policy data only. Session B (no criterion 3 rows, so clear of the
# 5-pending cap). Pass 1 (base policy): POST /repos/spike/beta/issues is refused not-allowlisted with no row. Pass 2
# restarts ONLY the hook with policy.add-verb.yaml layered on; approval-hook.mjs and policy.mjs are hashed before
# and after and must be byte-identical. In pass 2 the same request is gated, consumed once and vended.
# ---------------------------------------------------------------------------------------------------------------
_c7_rest() { # <step> <out>
  cat > "$SPIKE_WORK/c7/req.sh" <<'EOS'
curl -sS -o /dev/null --max-time 15 -w "$STEP=%{http_code}\n" --cacert "$CA" -x "$P" -H 'content-type: application/json' \
  --data '{"title":"spike synthetic issue","body":"synthetic"}' https://api.github.com/repos/spike/beta/issues 2>/dev/null || echo "$STEP=000"
EOS
  { echo "STEP=$1"; cat "$SPIKE_WORK/c7/req.sh"; } > "$SPIKE_WORK/c7/req-$1.sh"
  spike_cx sessB "$SPIKE_WORK/c7/req-$1.sh" "$2"
}

_c7_warm() { # wait until session B's allowlisted read vends again through iron-proxy (gRPC reconnect backoff)
  local i
  printf '%s\n' 'curl -sS -o /dev/null --max-time 10 -w "%{http_code}" --cacert "$CA" -x "$P" https://api.github.com/repos/spike/beta 2>/dev/null' > "$SPIKE_WORK/c7/warm.sh"
  for ((i = 0; i < 30; i++)); do
    spike_cx sessB "$SPIKE_WORK/c7/warm.sh" "$SPIKE_WORK/c7/warm.out"
    [[ "$(cat "$SPIKE_WORK/c7/warm.out")" == "200" ]] && return 0
    sleep 1
  done
  return 1
}

arm_c7() {
  local d="$SPIKE_WORK/c7" h1 h2 seq rows0 rows1 id
  mkdir -p "$d" || harness_fail DRIVER "mkdir c7"
  h1="$(sha256sum "$SPIKE_DIR/approval-hook.mjs" "$SPIKE_DIR/policy.mjs" | awk '{print $1}' | tr '\n' ' ')"
  rows0="$(psql "$DB_URL" -X -At -c "SELECT count(*) FROM public.approval_request WHERE conversation_id = '$CONV_B'" 2>/dev/null)"
  seq="$(spike_stub_seq)"
  _c7_rest pass1 "$d/pass1.out"
  rows1="$(psql "$DB_URL" -X -At -c "SELECT count(*) FROM public.approval_request WHERE conversation_id = '$CONV_B'" 2>/dev/null)"
  local m1
  m1="$(docker logs "$SPIKE_HOOK_CTR" 2>&1 | grep 'session=sessB ' | grep 'method=POST' | tail -1 | grep -oE '(sub)?reason=[a-z-]+' | tr '\n' ' ')"
  # Pass 2: restart only the hook, with the overlay layered on the base policy.
  python3 -I - "$SPIKE_WORK/hookpriv/hook.json" "$SPIKE_WORK/hookpriv/hook-overlay.json" <<'PYO' || { record_verdict 7 unmeasurable "harness:HOOK_START overlay config"; return; }
import json, sys
c = json.load(open(sys.argv[1]))
c["policyFiles"] = c["policyFiles"] + ["/app/test/infra/egress-injector-spike/policy.add-verb.yaml"]
json.dump(c, open(sys.argv[2], "w"))
PYO
  spike_fix_owner "$SPIKE_WORK/hookpriv"
  docker rm -f "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  spike_start_hook hook-overlay.json
  _c7_warm || { record_verdict 7 unmeasurable "harness:HOOK_RESTART session B did not vend a read within 30 s of the overlay restart"; return; }
  h2="$(sha256sum "$SPIKE_DIR/approval-hook.mjs" "$SPIKE_DIR/policy.mjs" | awk '{print $1}' | tr '\n' ' ')"
  _c7_rest pass2a "$d/pass2a.out"
  id="$(spike_latest_pending "$CONV_B")"
  local approve; approve="$(spike_decide ownerB "$id" approve)"
  _c7_rest pass2b "$d/pass2b.out"
  local status; status="$(spike_row_status "$id")"
  spike_stub_since "$seq" > "$d/stub.jsonl"
  python3 -I - "$d" "$h1" "$h2" "$rows0" "$rows1" "${id:+present}" "$approve" "$status" "$m1" > "$d/verdict.txt" <<'PYC7'
import json, sys
d, h1, h2, rows0, rows1, idp, approve, status, m1 = sys.argv[1:10]
rd = lambda f: open(f"{d}/{f}").read().strip().splitlines()[-1] if open(f"{d}/{f}").read().strip() else ""
recs = [json.loads(l) for l in open(f"{d}/stub.jsonl") if l.strip()]
issue_vends = [r for r in recs if r["method"] == "POST" and r["path"] == "/repos/spike/beta/issues" and r["auth_class"] == "real-decoy" and r["decoy_id"] == "sessB"]
checks = {
  "control: pass 1 refuses the request not-allowlisted, with no row": rd("pass1.out") == "pass1=403" and "not-allowlisted" in m1 and rows0 == rows1,
  "approval-hook.mjs and policy.mjs are byte-identical across passes": h1 == h2 and h1.strip() != "",
  "pass 2 gates the same request (pending row)": rd("pass2a.out") == "pass2a=403" and idp == "present",
  "pass 2 consumes once and vends after approval": approve == "200" and rd("pass2b.out") == "pass2b=201" and status == "consumed" and len(issue_vends) == 1,
}
json.dump({"hashes_pass1": h1, "hashes_pass2": h2, "pass1_marker": m1, "checks": checks,
           "comparison": "one data file (policy.add-verb.yaml) against #12188's 9 source files; the overlay leaves out tests and approval-card text; the claim is limited to REST verbs that fit the generic recipe (CTO R4)"},
          open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC7
  observe c7 "$d/raw.json"
  spike_record_judged 7 "$d/verdict.txt"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 8: failure is visible and closed. Runs LAST (it stops the hook, a router and an injector). Each client
# runs under its own `timeout -k` and its elapsed time is read from /proc/uptime (monotonic); a positive control
# through a healthy hook comes first, so a broken CA or a 407 cannot pass as "refused".
# ---------------------------------------------------------------------------------------------------------------
_c8_clients() { # <label> <session> <out>: git push (write), curl POST (write), gh POST (write), curl GET (read)
  cat > "$SPIKE_WORK/c8/clients-$1.sh" <<EOS
L=$1
up() { cut -d' ' -f1 /proc/uptime; }
run() { local n=\$1; shift; local t0 t1 rc; t0=\$(up); timeout -k 2 30 "\$@" >/dev/null 2>&1; rc=\$?; t1=\$(up); echo "c8 \$L \$n rc=\$rc elapsed=\$(echo "\$t1 \$t0" | awk '{printf "%.2f", \$1-\$2}')"; }
w=/home/soleur/c8-$2
[ -d "\$w/.git" ] || HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" timeout 30 git clone -q https://github.com/spike/alpha.git "\$w" >/dev/null 2>&1
[ -d "\$w/.git" ] && git -C "\$w" -c user.email=spike@example.invalid -c user.name=spike commit -q --allow-empty -m "c8 \$L"
run gitPush env HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git -C "\$w" push -q origin HEAD:main
run curlPost curl -sS -f -o /dev/null --cacert "\$CA" -x "\$P" -H 'content-type: application/json' --data "{\"title\":\"c8 \$L\",\"head\":\"a\",\"base\":\"main\"}" https://api.github.com/repos/spike/alpha/pulls
run ghPost env HTTPS_PROXY="\$P" SSL_CERT_FILE="\$CA" GH_TOKEN=spike-placeholder gh api -X POST repos/spike/alpha/pulls -f title="c8 gh \$L" -f head=a -f base=main
run curlGet curl -sS -f -o /dev/null --cacert "\$CA" -x "\$P" https://api.github.com/repos/spike/alpha
run sse sh -c 'test "\$(curl -sS -N --max-time 20 --cacert "\$CA" -x "\$P" https://sse.open-web.spike.test/sse 2>/dev/null | grep -c "^event: tick")" = 50'
EOS
  spike_cx "$2" "$SPIKE_WORK/c8/clients-$1.sh" "$3"
}

arm_c8() {
  local d="$SPIKE_WORK/c8" kong seq
  mkdir -p "$d" && : > "$d/windows.jsonl" || harness_fail DRIVER "mkdir c8"
  window() { # <label> <stub seq at start> <hook marker lines at start>
    python3 -I -c 'import json, sys; print(json.dumps({"label": sys.argv[1], "seq": int(sys.argv[2]), "hook": int(sys.argv[3])}))' "$1" "$2" "$3" >> "$d/windows.jsonl"
  }
  kong="$(docker ps --filter 'name=supabase_kong' --format '{{.Names}}' | head -1)"
  # Positive control: a healthy hook, the same clients (sessA; the writes are refused pending, the read vends).
  window control "$(spike_stub_seq)" "$(spike_hook_lines)"; _c8_clients control sessA "$d/control.out"
  # Stalled: the hook is alive but its RPC cannot finish (the API gateway is paused); its 5 s deadline answers.
  if [[ -n "$kong" ]]; then
    docker pause "$kong" >/dev/null 2>&1
    window stalled "$(spike_stub_seq)" "$(spike_hook_lines)"; _c8_clients stalled sessA "$d/stalled.out"
    docker unpause "$kong" >/dev/null 2>&1
  fi
  docker logs "$SPIKE_HOOK_CTR" 2>&1 | grep -c 'reason=hook-timeout' > "$d/hook-timeouts.txt"
  # Frozen: the hook process is frozen (cgroup freezer, the SIGSTOP of R27); iron-proxy has no deadline of its own.
  docker pause "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  window frozen "$(spike_stub_seq)" "$(spike_hook_lines)"; _c8_clients frozen sessA "$d/frozen.out"
  docker unpause "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  # Killed hook.
  docker kill "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  window hookKilled "$(spike_stub_seq)" 0; _c8_clients hookKilled sessA "$d/hookKilled.out"
  docker exec "$SPIKE_APP_CTR" sh -c 'cat /run/spike/sessA/logs/iron-proxy.log' 2>/dev/null | tr -d '\000' | grep -a '"action":"error"' | grep -ac 'approval-hook' > "$d/iron-hook-errors.txt"
  # Killed router (session B): all of B's egress fails.
  docker exec "$SPIKE_APP_CTR" sh -c 'kill "$(cat /run/spike/sessB/state/router.pid)"' >/dev/null 2>&1
  window routerKilled "$(spike_stub_seq)" 0; _c8_clients routerKilled sessB "$d/routerKilled.out"
  # Killed iron-proxy (session A): inject hosts fail; the forwarder branch (open-web SSE) still streams.
  docker exec "$SPIKE_APP_CTR" sh -c 'kill "$(cat /run/spike/sessA/state/iron.pid)"' >/dev/null 2>&1
  window ironKilled "$(spike_stub_seq)" 0; _c8_clients ironKilled sessA "$d/ironKilled.out"
  cp "$SPIKE_STUB_RECORDS" "$d/stub-all.jsonl"
  python3 -I - "$d" "${kong:+present}" > "$d/verdict.txt" <<'PYC8'
import json, sys
d, kong = sys.argv[1], sys.argv[2]
wins = [json.loads(l) for l in open(f"{d}/windows.jsonl")]
stub = [json.loads(l) for l in open(f"{d}/stub-all.jsonl") if l.strip()]
res = {}
for w in wins:
    for line in open(f"{d}/{w['label']}.out"):
        p = line.split()
        if p[:1] == ["c8"] and len(p) == 5:
            res[(p[1], p[2])] = {"rc": int(p[3].split("=")[1]), "elapsed": float(p[4].split("=")[1])}
def real_token_in(label):
    i = [w["label"] for w in wins].index(label)
    lo, hi = wins[i]["seq"], (wins[i + 1]["seq"] if i + 1 < len(wins) else 10**9)
    return [r for r in stub if lo < r["seq"] <= hi and r["auth_class"] == "real-decoy"]
inject = ("gitPush", "curlPost", "ghPost", "curlGet")
fails_fast = lambda lab: all(res.get((lab, c), {}).get("rc", 0) != 0 and res.get((lab, c), {}).get("elapsed", 99) <= 10 for c in inject)
writes = ("gitPush", "curlPost", "ghPost")
hook_timeouts = int(open(f"{d}/hook-timeouts.txt").read().strip() or 0)
iron_errors = int(open(f"{d}/iron-hook-errors.txt").read().strip() or 0)
frozen_wait = {c: res.get(("frozen", c)) for c in inject}
checks = {
  "control: the read vends and the SSE streams through a healthy hook": res.get(("control", "curlGet"), {}).get("rc") == 0 and res.get(("control", "sse"), {}).get("rc") == 0,
  "control: writes are refused promptly (pending), not hung": all(res.get(("control", c), {}).get("rc", 0) != 0 and res.get(("control", c), {}).get("elapsed", 99) <= 10 for c in writes),
  "stalled hook: writes exit non-zero within 10 s, hook-timeout emitted, no real token on a write": kong == "present" and all(res.get(("stalled", c), {}).get("rc", 0) != 0 and res.get(("stalled", c), {}).get("elapsed", 99) <= 10 for c in writes) and hook_timeouts >= 1 and not [r for r in real_token_in("stalled") if r["method"] == "POST"],
  "frozen hook: no real token at the stub, and the non-inject SSE is uninterrupted": not real_token_in("frozen") and res.get(("frozen", "sse"), {}).get("rc") == 0,
  "killed hook: every inject-host client exits non-zero within 10 s, no real token, iron-proxy's audit names the failed call": fails_fast("hookKilled") and not real_token_in("hookKilled") and iron_errors >= 1,
  "killed router: all of the session's egress fails": all(res.get(("routerKilled", c), {}).get("rc", 0) != 0 for c in inject + ("sse",)),
  "killed iron-proxy: inject-host clients exit non-zero within 10 s, no real token, the forwarder branch still streams": fails_fast("ironKilled") and not real_token_in("ironKilled") and res.get(("ironKilled", "sse"), {}).get("rc") == 0,
}
json.dump({"results": {f"{a}.{b}": v for (a, b), v in res.items()}, "hook_timeouts": hook_timeouts, "iron_hook_errors": iron_errors,
           "frozen_client_wait_recorded_not_scored": frozen_wait, "checks": checks}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC8
  # R27: a frozen hook cannot emit anything, so the harness names every request it sent in that window.
  for c in gitPush curlPost ghPost curlGet; do echo "SOLEUR_EGRESS_VEND_REFUSED source=harness reason=no-hook-decision session=sessA client=$c window=frozen"; done
  observe c8 "$d/raw.json"
  spike_record_judged 8 "$d/verdict.txt"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 1: no real credential (or any other session secret) is observable inside the sandbox or by the same-uid
# file tools. Two chokepoints (Guard 1): the sandbox side (a sandboxed step writes everything it can observe into a
# workspace file the driver scans in full; a planted control string must be found) and the CLI tier (scripted Read
# and WebFetch calls on every secret surface; a planted workspace file must read back first).
# ---------------------------------------------------------------------------------------------------------------
arm_c1() {
  local d="$SPIKE_WORK/c1" ipid fpid planted
  mkdir -p "$d" || harness_fail DRIVER "mkdir c1"
  ipid="$(docker exec "$SPIKE_APP_CTR" cat /run/spike/sessA/state/iron.pid 2>/dev/null)"
  fpid="$(docker exec "$SPIKE_APP_CTR" cat /run/spike/sessA/state/forwarder.pid 2>/dev/null)"
  [[ "$ipid" =~ ^[0-9]+$ && "$fpid" =~ ^[0-9]+$ ]] || { record_verdict 1 unmeasurable "harness:DRIVER no injector or forwarder pid"; return; }
  planted="spkplant_$(_spike_rand 18)"
  python3 -I - "$d/steps.json" "$d/extras.json" "$ipid" "$fpid" "$planted" <<'PYC1S' || { record_verdict 1 unmeasurable "harness:DRIVER c1 spec"; return; }
import json, sys
steps_out, extras_out, ipid, fpid, planted = sys.argv[1:6]
S = "/run/spike/sessA"
scan = ("{ echo '== env'; env; echo '== ps'; ps -eo args 2>&1; echo '== proc self'; cat /proc/self/environ 2>&1 | tr '\\0' '\\n';"
        " echo '== files'; for f in $(find \"$HOME\" @WS@ /tmp -xdev -type f -size -2M 2>/dev/null | grep -v '/.spike-scan.txt$'); do echo \"== $f\"; cat \"$f\" 2>/dev/null; done;"
        " echo '== masked'; ls -la /run/spike /run/spike/sessA 2>&1; } > @WS@/.spike-scan.txt 2>&1; echo scan-written")
steps = [
  {"id": "sandboxScan", "tool": "Bash", "input": {"command": scan}},
  {"id": "sandboxHookConnect", "tool": "Bash", "input": {"command": f"node -e 'require(\"net\").connect(\"{S}/hook/hook.sock\").on(\"connect\",()=>{{console.log(\"connected\");process.exit(0)}}).on(\"error\",e=>console.log(\"error \"+e.code))'"}},
  {"id": "readPlanted", "tool": "Read", "input": {"file_path": "@WS@/planted.txt"}},
  {"id": "readDecoy", "tool": "Read", "input": {"file_path": f"{S}/secrets/decoy.token"}},
  {"id": "readCaKey", "tool": "Read", "input": {"file_path": f"{S}/ca/ca.key"}},
  {"id": "readHookSocket", "tool": "Read", "input": {"file_path": f"{S}/hook/hook.sock"}},
  {"id": "readHookClientKey", "tool": "Read", "input": {"file_path": f"{S}/hookclient/client.key"}},
  {"id": "readIronYaml", "tool": "Read", "input": {"file_path": f"{S}/iron.yaml"}},
  {"id": "readInjectorEnviron", "tool": "Read", "input": {"file_path": f"/proc/{ipid}/environ"}},
  {"id": "readInjectorCmdline", "tool": "Read", "input": {"file_path": f"/proc/{ipid}/cmdline"}},
  {"id": "readForwarderEnviron", "tool": "Read", "input": {"file_path": f"/proc/{fpid}/environ"}},
  {"id": "webfetchDecoy", "tool": "WebFetch", "input": {"url": f"file://{S}/secrets/decoy.token", "prompt": "x"}},
]
json.dump(steps, open(steps_out, "w"))
declared = []
for s in ("sessA", "sessB", "sessC", "sessE"):
    r = f"/run/spike/{s}"
    declared += [{"id": f"{s}-decoy-basic", "file": f"{r}/secrets/decoy.token", "transform": "basic-b64"},
                 {"id": f"{s}-ca-key", "file": f"{r}/ca/ca.key", "transform": "pem-body"},
                 {"id": f"{s}-hookclient-key", "file": f"{r}/hookclient/client.key", "transform": "pem-body"}]
json.dump({"declaredFiles": declared, "planted": {"id": "planted-control", "value": planted, "path": "@WS@/planted.txt"},
           "scanFiles": ["@WS@/.spike-scan.txt"]}, open(extras_out, "w"))
PYC1S
  spike_spec "$d/spec.json" sessA B "$d/steps.json" "$d/extras.json"
  spike_drive sessA B "$d/spec.json" "$d/out.json" || { record_verdict 1 unmeasurable "harness:DRIVER c1"; return; }
  # Positive control for the outside chokepoint: the harness, as the same uid outside the sandbox, CAN read the
  # injector's /proc environ, so a CLI-tier refusal is a refusal and not an unreadable path.
  local ctl
  ctl="$(docker exec -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" sh -c "wc -c < /proc/$ipid/environ" 2>/dev/null)"
  python3 -I - "$d" "${ctl:-0}" > "$d/verdict.txt" <<'PYC1'
import json, sys
d, ctl = sys.argv[1], sys.argv[2]
o = json.load(open(f"{d}/out.json"))
st = {s["id"]: s for s in o.get("steps", [])}
scan = next((s for k, s in st.items() if k.startswith("scan:")), {})
cli = ["readDecoy", "readCaKey", "readHookSocket", "readHookClientKey", "readIronYaml", "readInjectorEnviron", "readInjectorCmdline", "readForwarderEnviron", "webfetchDecoy"]
leaks = {k: s.get("hits") for k, s in st.items() if [h for h in (s.get("hits") or []) if h != "planted-control"]}
refused = {k: (st.get(k, {}).get("isError") is True and not st.get(k, {}).get("hits")) for k in cli}
checks = {
  "the sandbox scan is live (planted control found in the scanned file)": "planted-control" in (scan.get("hits") or []) and "readable=true" in (scan.get("content") or ""),
  "no session secret in anything the sandbox or the tools returned": not leaks,
  "sandboxed Bash cannot connect() the hook socket": "connected" not in (st.get("sandboxHookConnect", {}).get("content") or "") and "error" in (st.get("sandboxHookConnect", {}).get("content") or ""),
  "control: the Read tool returns a planted workspace file": "planted-control" in (st.get("readPlanted", {}).get("hits") or []),
  "control: the same uid outside the sandbox reads the injector's /proc environ": ctl.isdigit() and int(ctl) > 0,
  "every CLI-tier Read/WebFetch of a secret surface is refused": all(refused.values()),
}
json.dump({"steps": {k: {"isError": s.get("isError"), "hits": s.get("hits"), "content": (s.get("content") or "")[:300]} for k, s in st.items()},
           "leaks": leaks, "cli_refused": refused, "proc_environ_control_bytes": ctl, "checks": checks}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC1
  observe c1 "$d/raw.json"
  spike_record_judged 1 "$d/verdict.txt"
}

# ---------------------------------------------------------------------------------------------------------------
# Criterion 6: ADR-278 controls do not regress; no secret or request body is logged. Scored per CTO R28: iron-proxy's
# listeners yield no vend or credential from container loopback or session B (their TCP reachability is recorded,
# not scored: they share the app container's loopback by construction), and stay unreachable from the sandbox.
# ---------------------------------------------------------------------------------------------------------------
arm_c6() {
  local d="$SPIKE_WORK/c6" ra fwd seq canary
  mkdir -p "$d" || harness_fail DRIVER "mkdir c6"
  ra="$(cat "$SPIKE_WORK/run/sessA/state/router.port")"; fwd="$(cat "$SPIKE_WORK/run/sessA/state/forwarder.port")"
  canary="spkcanary_$(_spike_rand 18)"; mask "$canary"
  cat > "$d/c6.sh" <<EOS
A=/run/spike/sessA; B=/run/spike/sessB; BUN=/run/spike-pub/sessA/bundle.pem
acred=\$(cat \$A/secrets/router-session.cred); binj=\$(cat \$B/secrets/router-injector.cred)
c() { curl -sS -o /dev/null --max-time 12 -w "\$1 http=%{http_code} connect=%{http_connect}\n" "\${@:2}" 2>/dev/null || true; }
P="http://\$acred@127.0.0.1:$ra"
# ADR-278 controls through the chain: forwarder branch (IP literals, port 80) and injector branch (inject name, port 80).
c denyCidr --cacert \$BUN -x "\$P" https://10.0.0.1/
c localhost --cacert \$BUN -x "\$P" https://127.0.0.1/
c linkLocal --cacert \$BUN -x "\$P" https://169.254.169.254/
c port80Open -x "\$P" --proxytunnel http://sse.open-web.spike.test:80/
c port80Inject -x "\$P" --proxytunnel http://github.com:80/
c forwarderBadToken --cacert \$BUN -x "http://x:not-the-token@127.0.0.1:$fwd" https://sse.open-web.spike.test/
# The body canary rides a forwarder-branch POST and an injector-branch POST (refused pending); neither may be logged.
c canaryOpen --cacert \$BUN -x "\$P" --data "$canary" https://sse.open-web.spike.test/sink
c canaryInject --cacert \$BUN -x "\$P" -H 'content-type: application/json' --data "{\"title\":\"$canary\",\"head\":\"a\",\"base\":\"main\"}" https://api.github.com/repos/spike/alpha/pulls
# iron-proxy's listeners from container loopback: reachability (recorded) and the vend outcome (scored).
for port in $SPIKE_SESS_sessA_TUNNEL $((SPIKE_SESS_sessA_TUNNEL + 1)) $((SPIKE_SESS_sessA_TUNNEL + 2)) $((SPIKE_SESS_sessA_TUNNEL + 3)); do
  (exec 3<>"/dev/tcp/127.0.0.1/\$port") 2>/dev/null && echo "reach \$port open" || echo "reach \$port closed"
done
c tunnelNoCred --cacert \$BUN -x "http://127.0.0.1:$SPIKE_SESS_sessA_TUNNEL" https://api.github.com/repos/spike/alpha
c tunnelSessionCred --cacert \$BUN -x "http://\$acred@127.0.0.1:$SPIKE_SESS_sessA_TUNNEL" https://api.github.com/repos/spike/alpha
c tunnelSessionBRouterCred --cacert \$BUN -x "http://\$binj@127.0.0.1:$SPIKE_SESS_sessA_TUNNEL" https://api.github.com/repos/spike/alpha
c httpListenConnect --cacert \$BUN -x "http://127.0.0.1:$((SPIKE_SESS_sessA_TUNNEL + 1))" https://api.github.com/repos/spike/alpha
c httpListenAbsolute -x "http://127.0.0.1:$((SPIKE_SESS_sessA_TUNNEL + 1))" http://api.github.com/repos/spike/alpha
c httpsListen -k --resolve "api.github.com:$((SPIKE_SESS_sessA_TUNNEL + 2)):127.0.0.1" "https://api.github.com:$((SPIKE_SESS_sessA_TUNNEL + 2))/repos/spike/alpha"
curl -sS --max-time 8 "http://127.0.0.1:$((SPIKE_SESS_sessA_TUNNEL + 3))/metrics" > /tmp/c6-metrics.txt 2>&1; curl -sS --max-time 8 "http://127.0.0.1:$((SPIKE_SESS_sessA_TUNNEL + 3))/" >> /tmp/c6-metrics.txt 2>&1
echo "metrics bytes=\$(wc -c < /tmp/c6-metrics.txt) secrets=\$(for f in \$A/secrets/decoy.token \$A/secrets/router-session.cred \$A/secrets/router-injector.cred \$A/secrets/forwarder.token; do grep -cF "\$(cat \$f)" /tmp/c6-metrics.txt; done | awk '{n += \$1} END {print n + 0}')"
rm -f /tmp/c6-metrics.txt
EOS
  seq="$(spike_stub_seq)"
  docker exec -i -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" bash -s < "$d/c6.sh" > "$d/probes.out" 2>&1
  spike_stub_since "$seq" > "$d/stub.jsonl"
  # Unentitled session (no egress at all) and the sandbox's view of the listeners.
  cat > "$d/steps-n.json" <<'JSON'
[ {"id": "openWeb", "tool": "Bash", "input": {"command": "curl -sS -o /dev/null --max-time 10 -w 'code=%{http_code}' https://sse.open-web.spike.test/ 2>&1; echo; curl -sS -o /dev/null --max-time 10 -w 'code=%{http_code}' https://api.github.com/ 2>&1"}} ]
JSON
  spike_spec "$d/spec-n.json" sessA N "$d/steps-n.json"
  spike_drive sessA N "$d/spec-n.json" "$d/out-n.json" || { record_verdict 6 unmeasurable "harness:DRIVER unentitled"; return; }
  python3 -I - "$d/steps-sb.json" "$SPIKE_SESS_sessA_TUNNEL" <<'PYS'
import json, sys
t = int(sys.argv[2])
cmd = "; ".join(f"(exec 3<>/dev/tcp/127.0.0.1/{p}) 2>/dev/null && echo 'sbreach {p} open' || echo 'sbreach {p} closed'" for p in range(t, t + 4))
json.dump([{"id": "sandboxListeners", "tool": "Bash", "input": {"command": cmd}}], open(sys.argv[1], "w"))
PYS
  spike_spec "$d/spec-sb.json" sessA B "$d/steps-sb.json"
  spike_drive sessA B "$d/spec-sb.json" "$d/out-sb.json" || { record_verdict 6 unmeasurable "harness:DRIVER sandbox listeners"; return; }
  # Log grep (deepen pass): every log is non-empty and a control copy carrying the canary is found first.
  mkdir -p "$d/logs"
  docker exec "$SPIKE_APP_CTR" sh -c 'cd /run/spike && for s in sess*; do for f in $s/logs/*.log; do [ -f "$f" ] && { echo "=== $f"; tr -d "\000" < "$f"; }; done; done' > "$d/logs/app.log" 2>/dev/null
  docker logs "$SPIKE_HOOK_CTR" > "$d/logs/hook.log" 2>&1
  spike_squid_log > "$d/logs/squid.log"
  docker logs "$SPIKE_STUB_CTR" > "$d/logs/stub-stdout.log" 2>&1
  python3 -I - "$d" "$canary" "$SPIKE_WORK/run" > "$d/verdict.txt" <<'PYC6'
import base64, json, os, re, sys
d, canary, run = sys.argv[1:4]
o, reach = {}, {}
for line in open(f"{d}/probes.out"):
    m = re.match(r"^(\w+) http=(\d{3}) connect=(\d{3})$", line.strip())
    if m: o[m.group(1)] = (m.group(2), m.group(3))
    m = re.match(r"^reach (\d+) (open|closed)$", line.strip())
    if m: reach[m.group(1)] = m.group(2)
    m = re.match(r"^metrics bytes=(\d+) secrets=(\S+)$", line.strip())
    if m: o["metrics"] = (m.group(1), m.group(2))
stub = [json.loads(l) for l in open(f"{d}/stub.jsonl") if l.strip()]
n = json.load(open(f"{d}/out-n.json")); sb = json.load(open(f"{d}/out-sb.json"))
ncontent = next((s.get("content") or "" for s in n.get("steps", []) if s["id"] == "openWeb"), "")
sbcontent = next((s.get("content") or "" for s in sb.get("steps", []) if s["id"] == "sandboxListeners"), "")
secrets = []
for s in os.listdir(run):
    sec = f"{run}/{s}/secrets"
    if os.path.isdir(sec):
        for f in ("decoy.token", "router-session.cred", "router-injector.cred", "forwarder.token"):
            p = f"{sec}/{f}"
            if os.path.exists(p):
                v = open(p).read().strip()
                secrets.append((f"{s}/{f}", v))
                if f == "decoy.token": secrets.append((f"{s}/decoy-basic", base64.b64encode(f"x-access-token:{v}".encode()).decode()))
logs, log_leaks, log_live = {}, {}, {}
for f in sorted(os.listdir(f"{d}/logs")):
    text = open(f"{d}/logs/{f}", errors="replace").read()
    logs[f] = len(text)
    control = text + "\n" + canary + "\n"
    log_live[f] = len(text) > 0 and canary in control
    hits = [k for k, v in secrets if len(v) >= 8 and v in text] + (["body-canary"] if canary in text else [])
    if hits: log_leaks[f] = hits
no_real_token = not any(r["auth_class"] == "real-decoy" for r in stub)
checks = {
  "deny-CIDR, localhost and link-local targets refused at squid": all(o.get(k, ("", ""))[1] == "403" for k in ("denyCidr", "localhost", "linkLocal")),
  "port-80 targets refused on both router branches": o.get("port80Open", ("", ""))[1] == "403" and o.get("port80Inject", ("", ""))[1] == "403",
  "the forwarder refuses a bad token (407)": o.get("forwarderBadToken", ("", ""))[1] == "407",
  "an unentitled session has no route": "code=000" in ncontent and "code=200" not in ncontent,
  "the sandbox cannot reach any iron-proxy listener": sbcontent.count("closed") == 4 and "open" not in sbcontent,
  "tunnel_listen refuses no credential, the session credential and session B's router credential (407)": all(o.get(k, ("", ""))[1] == "407" for k in ("tunnelNoCred", "tunnelSessionCred", "tunnelSessionBRouterCred")),
  "http_listen and https_listen yield no vend (R28 tunnel guard)": o.get("httpListenAbsolute", ("", ""))[0] in ("403", "502", "000") and o.get("httpListenConnect", ("", ""))[1] in ("403", "407") and o.get("httpsListen", ("", ""))[0] == "403",
  "no real token reached the stub from any listener probe": no_real_token,
  "metrics carry no secret": o.get("metrics", ("0", "err"))[1] == "0",
  "every log is non-empty and its control copy finds the canary": all(log_live.values()) and len(log_live) >= 4,
  "no log carries a secret or the body canary": not log_leaks,
}
json.dump({"probes": o, "listener_reachability_recorded": reach, "unentitled": ncontent, "sandbox_listeners": sbcontent,
           "log_sizes": logs, "log_leaks": log_leaks, "checks": checks, "not_scanned": "the CI job log itself (scanned only by GitHub's masking of every generated value)"},
          open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC6
  observe c6 "$d/raw.json"
  spike_record_judged 6 "$d/verdict.txt"
}
