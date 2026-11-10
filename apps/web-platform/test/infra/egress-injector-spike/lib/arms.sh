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
  "zero approval rows": rows0 == rows1 == "0",
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
