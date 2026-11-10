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

# spike_spec <out file> <session> <arm A|B> <steps json file>: a driver spec for that session. The workspace is a
# fresh synthetic directory under the app user's HOME (never the checkout); the sandbox masks /run/spike entirely.
spike_spec() {
  python3 -I - "$1" "$2" "$3" "$4" "$(cat "$SPIKE_WORK/run/$2/state/router.port")" <<'PYSPEC' || harness_fail DRIVER "spec $2/$3"
import json, sys
out, sess, arm, steps_file, rp = sys.argv[1:6]
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
