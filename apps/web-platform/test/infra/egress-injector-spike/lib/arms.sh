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
#   spike_stub_since <offset>          -> prints stub records after line <offset> (JSON lines)
#   spike_stub_seq                     -> prints the current record count (a window start)
#   spike_psql <what> <sql>            -> one read; prints PSQL_ERROR on failure and names it via spike_harness_err
#   spike_harness_err <reason>         -> the running criterion (SPIKE_CUR) records `unmeasurable harness:<reason>`

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
  # A driver that failed reports {"error": ...}, and one whose query threw reports a non-empty `thrown` (its steps
  # are whatever ran before the throw); both are harness failures, never a result to judge.
  python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); sys.exit(1 if d.get("error") or d.get("thrown") or not (d.get("steps") or "streaming" in d) else 0)' "$outf" \
    || { echo "driver $sess/$arm failed: $(head -c 300 "$outf")"; return 1; }
}

# Harness inputs (CTO R3: NO-GO only when every criterion has a MEASURED verdict). A helper that cannot read an
# input it was asked for names the reason here, under the criterion whose arm is running (SPIKE_CUR); that
# criterion then records `unmeasurable harness:<reason>` whatever its judge printed, so a failed read is never
# scored as a product failure (or a pass).
SPIKE_CUR=0
spike_harness_err() { printf '%s\n' "$1" >> "$SPIKE_WORK/harness-err-$SPIKE_CUR"; }

# spike_psql <what> <sql>: one psql read. On a non-zero exit it prints the sentinel PSQL_ERROR (never an empty
# string a caller could read as "no rows") and names the failure as a harness input error.
spike_psql() {
  local out
  if out="$(psql "$DB_URL" -X -At -v ON_ERROR_STOP=1 -F: -c "$2" 2>>"$SPIKE_WORK/psql.err")"; then
    [[ -z "$out" ]] || printf '%s\n' "$out"
  else
    spike_harness_err "PSQL $1"
    echo PSQL_ERROR
  fi
}

# Stub windows are LINE offsets in the record file, not the stub's in-memory sequence number (which a stub restart
# resets, measured 2026-11-10: records after a restart fell below the window start).
spike_stub_seq() { if [[ -f "$SPIKE_STUB_RECORDS" ]]; then wc -l < "$SPIKE_STUB_RECORDS" | tr -d ' '; else echo 0; fi; }
spike_stub_since() { tail -n +"$(( $1 + 1 ))" "$SPIKE_STUB_RECORDS" 2>/dev/null | grep -v '^$' || true; }

# spike_spec <out file> <session> <arm A|B> <steps json file> [<extras json file>]: a driver spec for that session.
# The workspace is a fresh synthetic directory under the app user's HOME (never the checkout); the sandbox masks
# /run/spike entirely. Extras (@WS@ substituted): declaredFiles are appended, other keys set.
spike_spec() {
  python3 -I - "$1" "$2" "$3" "$4" "$(cat "$SPIKE_WORK/run/$2/state/router.port")" "${5:-}" <<'PYSPEC' || harness_fail DRIVER "spec $2/$3"
import json, sys, uuid
out, sess, arm, steps_file, rp, extras_file = sys.argv[1:7]
steps = json.load(open(steps_file))
# A fresh workspace per spec (uuid4: Python's str hash() is randomized per process, so it named nothing stable).
ws = f"/home/soleur/spike-{sess}-{arm}-{uuid.uuid4().hex[:12]}/ws"
for st in steps:  # the steps may name the workspace as @WS@
    st["input"] = json.loads(json.dumps(st["input"]).replace("@WS@", ws))
# Every session (Guard 1 row 3, run 42820800719: session E's decoy went unscanned), each credential in every form
# a leak could take (bare password, Basic base64), and the harness-held secrets copied to /run/spike/declared
# (masked for every sandbox like the rest of /run/spike). PEM keys are declared by criterion 1 only: session E's CA
# key is deleted at its session end (criterion 9), and a missing declared file fails the driver.
per_session = (("decoy", "decoy.token", None), ("router-session", "router-session.cred", None),
               ("router-session-pw", "router-session.cred", "cred-password"), ("router-session-basic", "router-session.cred", "basic-cred"),
               ("router-injector", "router-injector.cred", None), ("router-injector-pw", "router-injector.cred", "cred-password"),
               ("router-injector-basic", "router-injector.cred", "basic-cred"), ("forwarder", "forwarder.token", None),
               ("forwarder-basic", "forwarder.cred", "basic-cred"))
declared = [{"id": f"{s}-{k}", "file": f"/run/spike/{s}/secrets/{f}", **({"transform": t} if t else {})}
            for s in ("sessA", "sessB", "sessC", "sessD", "sessE") for k, f, t in per_session]
declared += [{"id": f"harness-{k}", "file": f"/run/spike/declared/{k}"}
             for k in ("service-role.key", "anon.key", "hmac.key", "ownerA.jwt", "ownerB.jwt")]
json.dump({"workspace": ws, "home": "/home/soleur", "routerPort": int(rp),
           "routerCredentialFile": f"/run/spike/{sess}/secrets/router-session.cred",
           "caBundle": f"/run/spike-pub/{sess}/bundle.pem", "arm": arm, "denyReadExtra": ["/run/spike"],
           "declaredFiles": declared, "script": steps, "timeoutMs": 300000}, open(out, "w"))
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
  SPIKE_CUR=4
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
  rows0="$(spike_psql "c4 row count before" "SELECT count(*) FROM public.approval_request WHERE conversation_id IN ('$CONV_A', '$CONV_C')")"
  seqA="$(spike_stub_seq)"
  spike_spec "$d/specA.json" sessA B "$d/steps.json"
  spike_drive sessA B "$d/specA.json" "$d/outA.json" || { record_verdict 4 unmeasurable "harness:DRIVER sessA"; return; }
  spike_stub_since "$seqA" > "$d/stubA.jsonl"
  seqC="$(spike_stub_seq)"
  spike_spec "$d/specC.json" sessC B "$d/steps.json"
  spike_drive sessC B "$d/specC.json" "$d/outC.json" || { record_verdict 4 unmeasurable "harness:DRIVER sessC"; return; }
  spike_stub_since "$seqC" > "$d/stubC.jsonl"
  local rows1
  rows1="$(spike_psql "c4 row count after" "SELECT count(*) FROM public.approval_request WHERE conversation_id IN ('$CONV_A', '$CONV_C')")"
  # CTO R38 (recorded, unscored; after the row count, which it cannot affect: a query is a read).
  printf '%s\n' "curl -sS -o /dev/null --max-time 12 -w 'code=%{http_code}' --cacert \"\$CA\" -x \"\$P\" -H 'content-type: application/json' --data '{\"query\":\"query Q { repository(owner: \\\"other-synth\\\", name: \\\"x\\\") { id } }\",\"operationName\":\"Q\"}' https://api.github.com/graphql 2>&1" > "$d/a3.sh"
  local seq3; seq3="$(spike_stub_seq)"
  spike_cx sessA "$d/a3.sh" "$d/a3.out"
  spike_stub_since "$seq3" > "$d/a3-stub.jsonl"
  python3 -I - "$d" "$rows0" "$rows1" > "$d/verdict.txt" <<'PYC4'
import json, os, sys
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
  # A delta, not an absolute: criterion 2's gated push runs first and leaves a row on conversation A by design.
  "the reads created no approval row": rows0.isdigit() and rows0 == rows1,
}
# CTO R38, recorded and NOT scored: a GraphQL query naming a repository outside the allowlist is vended (GraphQL is
# not repository-scoped in this design; the per-session token is the only enforceable boundary, #11637).
a3 = {"out": open(f"{d}/a3.out").read().strip()[-200:] if os.path.exists(f"{d}/a3.out") else "",
      "vended": any(r["host"] == "api.github.com" and r["path"] == "/graphql" and r["auth_class"] == "real-decoy" for r in lines(f"{d}/a3-stub.jsonl")) if os.path.exists(f"{d}/a3-stub.jsonl") else None,
      "note": "R38: recorded only; GraphQL queries are not repository-scoped, so this does not affect the verdict"}
json.dump({"observations": obs, "checks": checks, "recorded_unscored_graphql_outside_allowlist": a3}, open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC4
  observe c4 "$d/raw.json"
  spike_record_judged 4 "$d/verdict.txt"
}

# A judge prints `pass|fail` then one observation line, or `unmeasurable` then a `harness:<reason>` line (a harness
# input it needed is missing). Anything else (a crashed judge) is unmeasurable, never a record_verdict refusal that
# would end the suite without finalizing. A harness input error named for the criterion (spike_harness_err)
# overrides whatever the judge printed.
spike_record_judged() {
  local v o herr="$SPIKE_WORK/harness-err-$1"
  if [[ -s "$herr" ]]; then
    record_verdict "$1" unmeasurable "harness:$(head -1 "$herr" | head -c 200)"
    return
  fi
  v="$(sed -n 1p "$2" 2>/dev/null)"; o="$(sed -n 2p "$2" 2>/dev/null)"
  case "$v" in
    pass|fail) [[ -n "$o" ]] && record_verdict "$1" "$v" "$o" || record_verdict "$1" unmeasurable "harness:JUDGE no observation" ;;
    unmeasurable) [[ "$o" == harness:* ]] && record_verdict "$1" unmeasurable "$o" || record_verdict "$1" unmeasurable "harness:JUDGE unmeasurable without a harness reason" ;;
    *) record_verdict "$1" unmeasurable "harness:JUDGE produced no verdict" ;;
  esac
}

# The CLI's own streaming leg (CTO R30 as amended by R33), shared by criteria 2 and 8. Runs the driver's streaming
# mode on session A and judges the PATH from the stub's record of POST /v1/messages: its peer is either the app
# container's address on the stub network (direct) or squid's (through the router's forwarder branch). A harness SSE
# through the router in the same window proves the router log was being written. Writes <dir>/stream.json:
# {deltas, route: direct|forwarder|injector|none, router_alive, peers, checks...}.
spike_claude_stream() { # <dir>
  local d="$1" rseq seq appip sqip
  appip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$SPIKE_NET_EXT\").IPAddress}}" "$SPIKE_APP_CTR" 2>/dev/null)"
  sqip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$SPIKE_NET_EXT\").IPAddress}}" "$SPIKE_SQUID_CTR" 2>/dev/null)"
  rseq="$(docker exec "$SPIKE_APP_CTR" sh -c 'wc -l < /run/spike/sessA/logs/router.log' 2>/dev/null)"; [[ "$rseq" =~ ^[0-9]+$ ]] || rseq=0
  seq="$(spike_stub_seq)"
  printf '%s\n' 'curl -sS -N --max-time 15 --cacert "$CA" -x "$P" https://sse.open-web.spike.test/sse 2>/dev/null | grep -c "^event: tick"' > "$d/liveness.sh"
  spike_cx sessA "$d/liveness.sh" "$d/liveness.out"
  printf '[]\n' > "$d/stream-steps.json"; printf '{"streaming": true}\n' > "$d/stream-extras.json"
  spike_spec "$d/spec-stream.json" sessA B "$d/stream-steps.json" "$d/stream-extras.json"
  # A failed streaming driver is a harness failure of the criterion this leg serves (2 or 8), never a scored "none".
  spike_drive sessA B "$d/spec-stream.json" "$d/out-stream.json" \
    || { spike_harness_err "DRIVER claude streaming leg"; printf '{"error": "driver"}\n' > "$d/out-stream.json"; }
  docker exec "$SPIKE_APP_CTR" sh -c "tail -n +$((rseq + 1)) /run/spike/sessA/logs/router.log" > "$d/router-stream.log" 2>/dev/null
  spike_stub_since "$seq" > "$d/stub-stream.jsonl"
  python3 -I - "$d" "$appip" "$sqip" > "$d/stream.json" <<'PYST'
import json, sys
d, appip, sqip = sys.argv[1:4]
o = json.load(open(f"{d}/out-stream.json"))
deltas = (o.get("streaming") or {}).get("deltas")
router = open(f"{d}/router-stream.log").read()
recs = [json.loads(l) for l in open(f"{d}/stub-stream.jsonl") if l.strip()]
msgs = [r for r in recs if r["host"] == "api.anthropic.com" and r["method"] == "POST" and r["path"].startswith("/v1/messages")]
peers = sorted({r.get("peer") for r in msgs})
side = sorted({f'{r["path"]} {r.get("peer")}' for r in recs if r["host"] == "api.anthropic.com" and r["path"].startswith("/api/claude_code/")})
alive = "branch=forwarder host=sse.open-web.spike.test" in router
via_router = "host=api.anthropic.com" in router
if "branch=injector host=api.anthropic.com" in router: route = "injector"
elif msgs and peers == [appip] and not via_router: route = "direct"
elif msgs and peers == [sqip] and "branch=forwarder host=api.anthropic.com" in router: route = "forwarder"
else: route = "none"
ok = deltas == 50 and alive and route in ("direct", "forwarder")
json.dump({"deltas": deltas, "route": route, "router_alive": alive, "message_peers": peers, "app_ip": appip, "squid_ip": sqip,
           "side_calls": side, "liveness_events": open(f"{d}/liveness.out").read().strip(),
           # The stub answers only on its own TLS listener with its own leaf, so a recorded POST /v1/messages means the
           # CLI's TLS peer was the stub's own certificate (the CLI printed no TLS line on stderr: stderr_tls below).
           "stub_own_certificate": bool(msgs), "stderr_tls": (o.get("streaming") or {}).get("stderrTls"), "ok": ok}, sys.stdout)
PYST
}

# Criterion 2 (transport), arms A and B on session A. Arm A is the exact buildAgentEnv output (records where GitHub
# traffic goes); arm B removes the inject hosts from NO_PROXY (#11637's change). Each client reads its own REST path,
# so the stub record attributes every vend to one client. Scored in arm B: git clone and fetch, gh REST and GraphQL,
# Node fetch with NODE_USE_ENV_PROXY=1 (CTO R29; the default env is recorded), curl, the open-web SSE on the
# router's forwarder branch, a gated sandboxed push (CTO R32), and the CLI's own streaming (CTO R30 as amended by R33).
arm_c2() {
  local d="$SPIKE_WORK/c2" arm seq rseq
  SPIKE_CUR=2
  mkdir -p "$d" || harness_fail DRIVER "mkdir c2"
  cat > "$d/steps.json" <<'JSON'
[
 {"id": "clone", "tool": "Bash", "input": {"command": "git clone -q https://github.com/spike/alpha.git @WS@/c 2>&1 | tail -1; test -d @WS@/c/.git && echo cloned=yes || echo cloned=no"}},
 {"id": "fetch", "tool": "Bash", "input": {"command": "git -C @WS@/c fetch -q origin 2>&1 | tail -1; echo fetch_rc=${PIPESTATUS[0]}"}},
 {"id": "ghRest", "tool": "Bash", "input": {"command": "GH_TOKEN=spike-placeholder gh api repos/spike/alpha/c2-gh --jq .full_name 2>&1 | tail -1"}},
 {"id": "ghGraphql", "tool": "Bash", "input": {"command": "GH_TOKEN=spike-placeholder gh api graphql -f query='query Q { viewer { login } }' 2>&1 | tail -1"}},
 {"id": "nodeFetch", "tool": "Bash", "input": {"command": "node -e 'fetch(\"https://api.github.com/repos/spike/alpha/c2-node-default\").then(r=>console.log(\"status=\"+r.status)).catch(e=>console.log(\"err=\"+(e.cause?.code||e.message)))' 2>/dev/null"}},
 {"id": "nodeFetchEnvProxy", "tool": "Bash", "input": {"command": "NODE_USE_ENV_PROXY=1 node -e 'fetch(\"https://api.github.com/repos/spike/alpha/c2-node-envproxy\").then(r=>console.log(\"status=\"+r.status)).catch(e=>console.log(\"err=\"+(e.cause?.code||e.message)))' 2>/dev/null"}},
 {"id": "curlRest", "tool": "Bash", "input": {"command": "curl -sS -o /dev/null -w 'code=%{http_code}' https://api.github.com/repos/spike/alpha/c2-curl 2>&1"}},
 {"id": "openSse", "tool": "Bash", "input": {"command": "echo events=$(curl -sS -N --max-time 20 https://sse.open-web.spike.test/sse 2>/dev/null | grep -c '^event: tick')"}},
 {"id": "tlsLibs", "tool": "Bash", "input": {"command": "curl --version | head -1; git version; ldd $(git --exec-path)/git-remote-https 2>/dev/null | grep -oE 'lib(gnutls|ssl|curl)[^ ]*' | sort -u | tr '\\n' ' '"}}
]
JSON
  rlines() { docker exec "$SPIKE_APP_CTR" sh -c 'wc -l < /run/spike/sessA/logs/router.log' 2>/dev/null; }
  for arm in A B; do
    seq="$(spike_stub_seq)"; rseq="$(rlines)"; [[ "$rseq" =~ ^[0-9]+$ ]] || rseq=0
    spike_spec "$d/spec$arm.json" sessA "$arm" "$d/steps.json"
    spike_drive sessA "$arm" "$d/spec$arm.json" "$d/out$arm.json" || { record_verdict 2 unmeasurable "harness:DRIVER arm $arm"; return; }
    spike_stub_since "$seq" > "$d/stub$arm.jsonl"
    docker exec "$SPIKE_APP_CTR" sh -c "tail -n +$((rseq + 1)) /run/spike/sessA/logs/router.log" > "$d/router$arm.log" 2>/dev/null
  done

  # CTO R32: one gated push through the sandbox. Run 1 (no row): refused pending, one pending row. The owner approves
  # that row (create_approval_request then decide_approval, the plan's seeding path). Run 2: the same push vends and
  # the row moves approved -> consumed. Both runs share one workspace, so run 2 pushes the same commit.
  local pw=/home/soleur/spike-c2push/ws rows0 id approve st seq1 seq2
  printf '{"workspace": "%s"}\n' "$pw" > "$d/push-extras.json"
  cat > "$d/push1.json" <<JSON
[ {"id": "push1", "tool": "Bash", "input": {"command": "git clone -q https://github.com/spike/alpha.git $pw/p 2>&1 | tail -1; cd $pw/p && git -c user.email=spike@example.invalid -c user.name=spike commit -q --allow-empty -m 'c2 sandboxed push' && git push -q origin HEAD:refs/heads/spike-c2-push 2>&1 | tail -3; echo push_rc=\${PIPESTATUS[0]}"}} ]
JSON
  cat > "$d/push2.json" <<JSON
[ {"id": "push2", "tool": "Bash", "input": {"command": "cd $pw/p && git push -q origin HEAD:refs/heads/spike-c2-push 2>&1 | tail -2; echo push_rc=\${PIPESTATUS[0]}"}} ]
JSON
  rows0="$(spike_rows "$CONV_A")"; seq1="$(spike_stub_seq)"
  spike_spec "$d/spec-push1.json" sessA B "$d/push1.json" "$d/push-extras.json"
  spike_drive sessA B "$d/spec-push1.json" "$d/out-push1.json" || { record_verdict 2 unmeasurable "harness:DRIVER push 1"; return; }
  spike_stub_since "$seq1" > "$d/stub-push1.jsonl"
  local rows1; rows1="$(spike_rows "$CONV_A")"
  id="$(spike_latest_pending "$CONV_A")"; approve="$(spike_decide ownerA "$id" approve)"
  local st_approved; st_approved="$(spike_row_status "$id")"
  seq2="$(spike_stub_seq)"
  spike_spec "$d/spec-push2.json" sessA B "$d/push2.json" "$d/push-extras.json"
  spike_drive sessA B "$d/spec-push2.json" "$d/out-push2.json" || { record_verdict 2 unmeasurable "harness:DRIVER push 2"; return; }
  spike_stub_since "$seq2" > "$d/stub-push2.jsonl"
  st="$(spike_row_status "$id")"
  printf '{"rows_before": "%s", "rows_after_push1": "%s", "approve_http": "%s", "status_after_approve": "%s", "status_after_push2": "%s", "row": "%s"}\n' \
    "$rows0" "$rows1" "$approve" "$st_approved" "$st" "${id:+present}" > "$d/push-rows.json"

  # The CLI's own streaming (CTO R30 as amended by R33).
  spike_claude_stream "$d"

  python3 -I - "$d" > "$d/verdict.txt" <<'PYC2'
import json, sys
d = sys.argv[1]
J = lambda f: json.load(open(f"{d}/{f}"))
L = lambda f: [json.loads(l) for l in open(f"{d}/{f}") if l.strip()]
summary = {}
for arm in ("A", "B"):
    o = J(f"out{arm}.json")
    recs = L(f"stub{arm}.jsonl")
    summary[arm] = {"env": o.get("env"), "steps": {s["id"]: s.get("content") for s in o.get("steps", [])},
                    "stub": sorted({f'{r["host"]} {r["method"]} {r["path"]} {r["auth_class"]} {r.get("auth_scheme")} {r.get("decoy_id")}' for r in recs}),
                    "router": sorted({" ".join(w for w in l.split() if w.startswith(("branch=", "host=", "status="))) for l in open(f"{d}/router{arm}.log") if l.strip()})}
B, recsB = summary["B"], L("stubB.jsonl")
step = lambda k: B["steps"].get(k) or ""
vend = lambda host, path, method="GET": any(r["host"] == host and r["path"].startswith(path) and r["method"] == method and r["auth_class"] == "real-decoy" and r["decoy_id"] == "sessA" for r in recsB)
p1, p2, rows = J("out-push1.json"), J("out-push2.json"), J("push-rows.json")
p1c = next((s.get("content") or "" for s in p1.get("steps", []) if s["id"] == "push1"), "")
p2c = next((s.get("content") or "" for s in p2.get("steps", []) if s["id"] == "push2"), "")
sp1, sp2 = L("stub-push1.jsonl"), L("stub-push2.jsonl")
rp = lambda recs: [r for r in recs if r["path"].endswith("/git-receive-pack") and r["method"] == "POST" and r["auth_class"] == "real-decoy"]
pend = lambda s: int(dict(x.split(":") for x in s.split()).get("pending", 0)) if s.strip() else 0
stream = J("stream.json")
checks = {
  "git clone and fetch through the injector": "cloned=yes" in step("clone") and "fetch_rc=0" in step("fetch") and vend("github.com", "/spike/alpha.git/git-upload-pack", "POST"),
  "gh REST through the injector (placeholder token replaced)": "spike/alpha" in step("ghRest") and vend("api.github.com", "/repos/spike/alpha/c2-gh"),
  "gh GraphQL through the injector": '"stub":true' in step("ghGraphql") and vend("api.github.com", "/graphql", "POST"),
  "Node fetch with NODE_USE_ENV_PROXY=1 through the injector (R29)": "status=200" in step("nodeFetchEnvProxy") and vend("api.github.com", "/repos/spike/alpha/c2-node-envproxy"),
  "curl through the injector": "code=200" in step("curlRest") and vend("api.github.com", "/repos/spike/alpha/c2-curl"),
  "open-web SSE untouched on the router's forwarder branch (50/50)": "events=50" in step("openSse") and any("branch=forwarder host=sse.open-web.spike.test" in r for r in B["router"]) and not any("branch=injector host=sse" in r for r in B["router"]),
  "sandboxed push with no row: refused pending, one pending row, no real token (R32)": "push_rc=0" not in p1c and pend(rows["rows_after_push1"]) == pend(rows["rows_before"]) + 1 and not rp(sp1),
  "sandboxed push after approval: vended, row approved -> consumed (R32)": rows["approve_http"] == "200" and rows["status_after_approve"] == "approved" and "push_rc=0" in p2c and rows["status_after_push2"] == "consumed" and len(rp(sp2)) == 1,
}
checks["claude CLI streaming 50/50 on its own path, never the injector, router log live (R30/R33)"] = stream.get("ok") is True
summary["push"] = {"rows": rows, "push1": p1c[-300:], "push2": p2c[-300:], "pending_message_reached_agent_R15": p1c[-300:]}
summary["claude_streaming"] = stream
summary["checks"] = checks
json.dump(summary, open(f"{d}/summary.json", "w"))
failed = [k for k, v in checks.items() if not v]
print("pass" if not failed else "fail")
print(("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed)) + f" (claude route: {stream.get('route')})")
PYC2
  observe c2 "$d/summary.json"
  spike_record_judged 2 "$d/verdict.txt"
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
  timeout -k 5 "${SPIKE_CX_TIMEOUT:-120}" docker exec -i -u "$SPIKE_APP_UID" -e "P=http://$cred@127.0.0.1:$port" -e "CA=/run/spike-pub/$1/bundle.pem" \
    -e GIT_CONFIG_GLOBAL=/dev/null -e GIT_CONFIG_NOSYSTEM=1 -e HOME=/home/soleur "$SPIKE_APP_CTR" bash -s < "$2" > "$3" 2>&1
}

# Row reads go through spike_psql: a failed read prints PSQL_ERROR and marks the running criterion unmeasurable.
spike_rows() { # conversation -> "status:count status:count ..." (empty: no rows)
  spike_psql "rows of a conversation" "SELECT status, count(*) FROM public.approval_request WHERE conversation_id = '$1' GROUP BY status ORDER BY status" | tr '\n' ' '
}
spike_latest_pending() { spike_psql "latest pending row" "SELECT id FROM public.approval_request WHERE conversation_id = '$1' AND status = 'pending' ORDER BY created_at DESC LIMIT 1"; }
spike_row_status() { spike_psql "row status" "SELECT status FROM public.approval_request WHERE id = '$1'"; }

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
# Its own branch: other arms push to the same repository, and a push to a moved main is refused by git locally
# (non-fast-forward) before any request leaves, which measured nothing (run 42809989901, the expiry arm).
HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git push -q origin HEAD:refs/heads/spike-$1-$2 2>&1 | tail -2
echo push_rc=\${PIPESTATUS[0]}
EOS
}

# A push of one commit adding <bytes> random bytes (synthetic), on its own working copy and branch of session D.
_c3_big_push_script() { # <name> <bytes> <out script file>
  cat > "$3" <<EOS
w=/home/soleur/c3-sessD-$1
if [ ! -d "\$w/.git" ]; then HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git clone -q https://github.com/spike/alpha.git "\$w" 2>&1 | tail -1; fi
cd "\$w" || { echo push_rc=clone-failed; exit 0; }
if [ ! -f "$1.bin" ]; then head -c $2 /dev/urandom > "$1.bin" && git add "$1.bin" && git -c user.email=spike@example.invalid -c user.name=spike commit -q -m "c3 $1 $2 bytes"; fi
echo "pack_bytes=\$(git count-objects -v | sed -n 's/^size-pack: //p')k loose=\$(git count-objects | cut -d' ' -f3)k"
HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git push -q origin HEAD:refs/heads/spike-sessD-$1 2>&1 | tail -2
echo push_rc=\${PIPESTATUS[0]}
EOS
}

# spike_settle_pending <conversation> <owner label>: the owner denies every pending row of the conversation, so the
# arm that follows starts at zero pending and never reaches the 5-pending cap (AP429, reason=cap).
spike_settle_pending() {
  local id
  for id in $(spike_psql "pending rows to settle" "SELECT id FROM public.approval_request WHERE conversation_id = '$1' AND status = 'pending'"); do
    [[ "$id" == PSQL_ERROR ]] && return 0
    [[ "$(spike_decide "$2" "$id" deny)" == 200 ]] || spike_harness_err "SETTLE deny of a pending row failed"
  done
}

# Starts the expiry arm (session E, rows created with a 60 s TTL). Returns at once; arm_c3 finishes it.
arm_c3_expiry_start() {
  SPIKE_CUR=3
  mkdir -p "$SPIKE_WORK/c3" || harness_fail DRIVER "mkdir c3"
  _c3_push_script sessE exp "expiry e1" "$SPIKE_WORK/c3/exp.sh"
  spike_cx sessE "$SPIKE_WORK/c3/exp.sh" "$SPIKE_WORK/c3/exp1.out"
  C3_EXP_ID="$(spike_latest_pending "$CONV_E")"
  C3_EXP_T0="$(date +%s)"
}

# Criterion 3 runs on session D, its own fresh conversation (CTO R16): no other arm's rows are on it, so every row
# count and every reason below is this arm's own. Session C (flag off) and session E (expiry) are their own too.
arm_c3() {
  local d="$SPIKE_WORK/c3" seq h0 p1 p2 x g obs="$SPIKE_WORK/c3/obs.jsonl"
  SPIKE_CUR=3
  mkdir -p "$d" && : > "$obs" || harness_fail DRIVER "mkdir c3"
  note() { python3 -I -c 'import json, sys; print(json.dumps({"k": sys.argv[1], "v": sys.argv[2]}))' "$1" "$2" >> "$obs"; }
  # The push script's exit line, found by its key (git's own output lines may follow or precede it).
  prc() { sed -n 's/.*\(push_rc=[^ ]*\).*/\1/p' "$1" | tail -1; }
  # reason_since <hook line offset> <session>: the reason of the last POST refusal the hook marked for that session
  # since the offset (empty when nothing was refused), so each probe is judged on its own refusal, not on any 403.
  reason_since() {
    spike_hook_markers_since "$1" | grep -E '^SOLEUR_EGRESS_VEND_REFUSED ' | grep -F "session=$2 " | grep -F ' method=POST ' \
      | sed -n 's/.* reason=\([a-z-]*\).*/\1/p' | tail -1
  }
  h0="$(spike_hook_lines)"
  seq="$(spike_stub_seq)"

  # Push lifecycle.
  _c3_push_script sessD life "life 1" "$d/l1.sh"
  spike_cx sessD "$d/l1.sh" "$d/l1a.out"; note push1 "$(prc "$d/l1a.out")"; note rows1 "$(spike_rows "$CONV_D")"
  note stub1_receivepack "$(spike_stub_since "$seq" | grep -c '"path":"/spike/alpha.git/git-receive-pack"')"
  spike_cx sessD "$d/l1.sh" "$d/l1b.out"; note push1_retry "$(prc "$d/l1b.out")"; note rows1_retry "$(spike_rows "$CONV_D")"
  p1="$(spike_latest_pending "$CONV_D")"; note p1 "${p1:+present}"
  note deny "$(spike_decide ownerA "$p1" deny)"
  spike_cx sessD "$d/l1.sh" "$d/l1c.out"; note push1_after_deny "$(prc "$d/l1c.out")"; note rows_after_deny "$(spike_rows "$CONV_D")"
  p2="$(spike_latest_pending "$CONV_D")"; note p2_new "$([[ -n "$p2" && "$p2" != "$p1" ]] && echo yes || echo no)"
  seq="$(spike_stub_seq)"
  note approve "$(spike_decide ownerA "$p2" approve)"
  spike_cx sessD "$d/l1.sh" "$d/l1d.out"; note push1_approved "$(prc "$d/l1d.out")"; note p2_status "$(spike_row_status "$p2")"
  note stub_after_approve "$(spike_stub_since "$seq" | grep '"path":"/spike/alpha.git/git-receive-pack"' | grep -c '"auth_class":"real-decoy"')"
  seq="$(spike_stub_seq)"
  _c3_push_script sessD life "life 2" "$d/l2.sh"
  spike_cx sessD "$d/l2.sh" "$d/l2.out"; note push2_new_hash "$(prc "$d/l2.out")"; note rows_end "$(spike_rows "$CONV_D")"
  note stub_push2 "$(spike_stub_since "$seq" | grep '"path":"/spike/alpha.git/git-receive-pack"' | grep -c '"auth_class":"real-decoy"')"
  # Every block below starts at zero pending (A7): no conversation reaches the 5-pending cap.
  note pend_after_push "$(spike_rows "$CONV_D")"; spike_settle_pending "$CONV_D" ownerA

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
  offpost) post offpost '{"title":"spike flag off","head":"a","base":"main"}' '' /repos/spike/alpha/pulls ;;
esac
EOS
  rest() { # <step> [<session>, default sessD]
    local s="${2:-sessD}" h; h="$(spike_hook_lines)"
    { echo "STEP=$1"; cat "$d/rest.sh"; } > "$d/rest-$1.sh"; spike_cx "$s" "$d/rest-$1.sh" "$d/rest-$1.out"
    note "rest_$1" "$(tail -1 "$d/rest-$1.out")"; note "rest_$1_reason" "$(reason_since "$h" "$s")"
  }
  seq="$(spike_stub_seq)"
  rest x1; x="$(spike_latest_pending "$CONV_D")"; note approve_x "$(spike_decide ownerA "$x" approve)"
  rest y1; rest zpath; rest zrepo
  note stub_binding_misses "$(spike_stub_since "$seq" | grep '"method":"POST"' | grep -c '"auth_class":"real-decoy"')"
  rest x2; note x_status "$(spike_row_status "$x")"
  note stub_x2 "$(spike_stub_since "$seq" | grep '"method":"POST"' | grep '"auth_class":"real-decoy"' | head -1)"
  rest x3
  note pend_after_rest "$(spike_rows "$CONV_D")"; spike_settle_pending "$CONV_D" ownerA

  # GraphQL mutation lifecycle (plan: criterion 3 covers "REST POST and GraphQL mutation"). The top field is in the
  # policy's graphql-mutation rule (mutation_fields: createPullRequest, addComment). Pending with one new row, then
  # approved, then the identical body vends once and consumes the row, then a replay is refused.
  cat > "$d/gql.sh" <<'EOS'
curl -sS -o /dev/null -w "$STEP=%{http_code}\n" --cacert "$CA" -x "$P" -H 'content-type: application/json' \
  --data '{"query":"mutation M { addComment(input: {subjectId: \"spike-subject\", body: \"spike synthetic\"}) { clientMutationId } }","operationName":"M"}' \
  https://api.github.com/graphql
EOS
  gql() {
    local h; h="$(spike_hook_lines)"
    { echo "STEP=$1"; cat "$d/gql.sh"; } > "$d/gql-$1.sh"; spike_cx sessD "$d/gql-$1.sh" "$d/gql-$1.out"
    note "gql_$1" "$(tail -1 "$d/gql-$1.out")"; note "gql_$1_reason" "$(reason_since "$h" sessD)"
  }
  gvend() { spike_stub_since "$1" | grep -F '"path":"/graphql"' | grep -F '"method":"POST"' | grep -c '"auth_class":"real-decoy"'; }
  seq="$(spike_stub_seq)"; note gql_rows0 "$(spike_rows "$CONV_D")"
  gql g1; note gql_rows1 "$(spike_rows "$CONV_D")"; note gql_vend_pending "$(gvend "$seq")"
  g="$(spike_latest_pending "$CONV_D")"; note gql_row "${g:+present}"; note gql_approve "$(spike_decide ownerA "$g" approve)"
  seq="$(spike_stub_seq)"
  gql g2; note gql_status "$(spike_row_status "$g")"; note gql_vend_approved "$(gvend "$seq")"
  seq="$(spike_stub_seq)"
  gql g3; note gql_vend_replay "$(gvend "$seq")"
  note pend_after_gql "$(spike_rows "$CONV_D")"; spike_settle_pending "$CONV_D" ownerA

  # Windows for the arms below: session D's hook markers (ids stripped) and the stub records, per probe.
  win() { # <label> <hook line offset> <stub seq>
    spike_hook_markers_since "$2" | grep -E '^SOLEUR_EGRESS_' | grep -F 'session=sessD ' \
      | sed -E 's/ request_id=[^ ]+//; s/ action_sha256=[^ ]+//; s/ approval_id=[0-9a-f-]+/ approval_id=<id>/' > "$d/$1.markers"
    spike_stub_since "$3" > "$d/$1.stub"
  }
  local hw sw a4

  # CTO R39: a live push of about 2 MiB (one commit adding a 2 MiB random file) on an allowlisted repository with
  # the flag on. Above http.postBuffer (1 MiB by default; spike_cx reads no git config) git first sends a probe POST
  # whose body is only a flush-pkt; it must vend with no row (rule git-receive-pack-probe). The real push then waits
  # for approval, and after approval it is consumed once with the whole body at the stub. A git that sends no probe
  # fails this arm.
  _c3_big_push_script big 2097152 "$d/a4.sh"
  note a4_rows0 "$(spike_rows "$CONV_D")"; hw="$(spike_hook_lines)"; sw="$(spike_stub_seq)"
  spike_cx sessD "$d/a4.sh" "$d/a4a.out"; note a4_push1 "$(prc "$d/a4a.out")"; note a4_rows1 "$(spike_rows "$CONV_D")"
  win a4a "$hw" "$sw"
  a4="$(spike_latest_pending "$CONV_D")"; note a4_row "${a4:+present}"; note a4_approve "$(spike_decide ownerA "$a4" approve)"
  hw="$(spike_hook_lines)"; sw="$(spike_stub_seq)"
  spike_cx sessD "$d/a4.sh" "$d/a4b.out"; note a4_push2 "$(prc "$d/a4b.out")"; note a4_status "$(spike_row_status "$a4")"
  win a4b "$hw" "$sw"
  note a4_pack "$(grep -m1 '^pack_bytes=' "$d/a4a.out")"
  note pend_after_a4 "$(spike_rows "$CONV_D")"; spike_settle_pending "$CONV_D" ownerA

  # CTO R40: a push of about 4 MiB is over the 3 MiB body cap: refused body-over-cap, no row, no decoy on the write.
  _c3_big_push_script huge 4194304 "$d/a5.sh"
  note a5_rows0 "$(spike_rows "$CONV_D")"; hw="$(spike_hook_lines)"; sw="$(spike_stub_seq)"
  spike_cx sessD "$d/a5.sh" "$d/a5.out"; note a5_push "$(prc "$d/a5.out")"; note a5_rows1 "$(spike_rows "$CONV_D")"
  win a5 "$hw" "$sw"
  note pend_after_a5 "$(spike_rows "$CONV_D")"; spike_settle_pending "$CONV_D" ownerA

  # CTO R40: one curl invocation sends an allowlisted GET and then an unapproved listed REST POST on the SAME
  # connection (--next keeps curl's connection cache), once over HTTP/1.1 and once over HTTP/2. %{num_connects} of 0
  # on the second transfer proves the reuse; the POST must still be judged on its own (pending, no real token).
  local v
  for v in http1.1 http2; do
    cat > "$d/a6-$v.sh" <<EOS
curl -sS --max-time 15 --cacert "\$CA" -x "\$P" --$v -o /dev/null -w "a6 get n=%{num_connects} code=%{http_code}\n" https://api.github.com/repos/spike/alpha \\
  --next -sS --max-time 15 --cacert "\$CA" -x "\$P" --$v -o /dev/null -w "a6 post n=%{num_connects} code=%{http_code}\n" \\
  -H 'content-type: application/json' --data '{"title":"c3 same connection $v","head":"a","base":"main"}' https://api.github.com/repos/spike/alpha/pulls
EOS
    hw="$(spike_hook_lines)"; sw="$(spike_stub_seq)"
    spike_cx sessD "$d/a6-$v.sh" "$d/a6-$v.out"
    win "a6-$v" "$hw" "$sw"
  done
  note pend_after_a6 "$(spike_rows "$CONV_D")"; spike_settle_pending "$CONV_D" ownerA
  cp "$SPIKE_STUB_BODIES" "$d/bodies.jsonl" 2>/dev/null || spike_harness_err "STUB_BODIES no body-length file"

  # Flag input off (session C): every vend is refused flag-off, with no row. C's own clone is refused like every
  # other vend (it would leave no working copy, and a push from a missing copy measured nothing), so the copy is
  # cloned through session D into C's directory and only the push goes through C. git stops at the refused push
  # advertisement (GET) and never sends its POST, so a listed REST write through C carries the POST.
  local hoff seqoff
  printf '%s\n' 'HTTPS_PROXY="$P" GIT_SSL_CAINFO="$CA" git clone -q https://github.com/spike/alpha.git /home/soleur/c3-sessC-off 2>&1 | tail -1; test -d /home/soleur/c3-sessC-off/.git && echo cloned=yes || echo cloned=no' > "$d/off-clone.sh"
  spike_cx sessD "$d/off-clone.sh" "$d/off-clone.out"; note off_clone "$(tail -1 "$d/off-clone.out")"
  _c3_push_script sessC off "flag off" "$d/off.sh"
  hoff="$(spike_hook_lines)"; seqoff="$(spike_stub_seq)"
  spike_cx sessC "$d/off.sh" "$d/off.out"; note push_flag_off "$(prc "$d/off.out")"
  note off_push_markers "$(spike_hook_markers_since "$hoff" | grep -E '^SOLEUR_EGRESS_VEND_REFUSED ' | grep -F 'session=sessC ' | sed -n 's/.* method=\([A-Z]*\) .* reason=\([a-z-]*\).*/\1:\2/p' | tr '\n' ' ')"
  rest offpost sessC
  note off_stub_real "$(spike_stub_since "$seqoff" | grep -c '"auth_class":"real-decoy"')"
  note rows_c "$(spike_rows "$CONV_C")"

  # Expiry (session E, 60 s TTL started at topology-ready): pending near 50 s, then expired, then REJECT expired.
  local waited=$(( $(date +%s) - C3_EXP_T0 ))
  (( waited < 50 )) && sleep $(( 50 - waited ))
  note exp_at_50s "$(spike_row_status "$C3_EXP_ID")"
  waited=$(( $(date +%s) - C3_EXP_T0 )); (( waited < 66 )) && sleep $(( 66 - waited ))
  spike_cx sessE "$d/exp.sh" "$d/exp2.out"; note push_after_expiry "$(prc "$d/exp2.out")"; note exp_final "$(spike_row_status "$C3_EXP_ID")"
  # Diagnostics for the expiry path (no secrets: git's own messages, marker fields, iron-proxy audit fields).
  note exp1_out "$(tr '\n' ' ' < "$SPIKE_WORK/c3/exp1.out" | head -c 400)"
  note exp2_out "$(tr '\n' ' ' < "$d/exp2.out" | head -c 400)"
  note exp_id "${C3_EXP_ID:+present}"
  note exp_rows "$(spike_rows "$CONV_E")"
  note exp_markers "$(docker logs "$SPIKE_HOOK_CTR" 2>&1 | grep 'session=sessE ' | sed -E 's/ request_id=[^ ]+//; s/ action_sha256=[^ ]+//; s/ approval_id=[0-9a-f-]+/ approval_id=<id>/' | tail -6 | tr '\n' '|')"
  note exp_iron "$(docker exec "$SPIKE_APP_CTR" sh -c 'tail -c 20000 /run/spike/sessE/logs/iron-proxy.log' 2>/dev/null | tr -d '\000' | python3 -I "$SPIKE_DIR/lib/iron-audit.py" 6 2>/dev/null)"

  spike_hook_markers_since "$h0" | grep -E '^SOLEUR_EGRESS_VEND' | sed -E 's/ request_id=[^ ]+//; s/ action_sha256=[^ ]+//; s/ approval_id=[0-9a-f-]+/ approval_id=<id>/' > "$d/markers.txt"
  python3 -I - "$d" > "$d/verdict.txt" <<'PYC3'
import json, os, re, sys
d = sys.argv[1]
o = {}
for l in open(f"{d}/obs.jsonl"):
    r = json.loads(l); o[r["k"]] = r["v"]
m = open(f"{d}/markers.txt").read().splitlines()
def reasons(sess):
    return [x.split(" reason=")[1].split()[0] for x in m if f"session={sess} " in x and " reason=" in x]
ra, rc, re_ = reasons("sessD"), reasons("sessC"), reasons("sessE")
hookreqs = [x for x in m if "session=sessD " in x and " method=CONNECT" not in x and x.startswith("SOLEUR_EGRESS_VEND")]
pend = lambda s: int(dict(p.split(":", 1) for p in s.split() if ":" in p).get("pending", 0)) if s.strip() else 0
# A refused push is git's own non-zero exit; a missing or non-numeric push_rc (a script that never reached the
# push) is never read as refused.
refused = lambda v: re.fullmatch(r"push_rc=[1-9][0-9]*", v or "") is not None
off_markers = o["off_push_markers"].split()
# Per-probe windows (A4-A6): markers, stub records, and the stub's received body length by record seq.
rd = lambda f: open(f"{d}/{f}").read() if os.path.exists(f"{d}/{f}") else ""
mk = lambda w: rd(f"{w}.markers").splitlines()
stub = lambda w: [json.loads(l) for l in rd(f"{w}.stub").splitlines() if l.strip()]
bodies = {b["seq"]: b for b in (json.loads(l) for l in rd("bodies.jsonl").splitlines() if l.strip())}
blen = lambda r: (bodies.get(r.get("seq")) or {}).get("body_bytes", -1)
rpack = lambda w: [r for r in stub(w) if r["method"] == "POST" and r["path"].endswith("/git-receive-pack") and r["auth_class"] == "real-decoy"]
FLUSH = 4  # the probe's body, "0000"
def refusal(ms, method, reason, sub=None):
    return any(x.startswith("SOLEUR_EGRESS_VEND_REFUSED ") and f" method={method} " in x and re.search(rf" reason={reason}( |$)", x)
               and (sub is None or re.search(rf" subreason={sub}( |$)", x)) for x in ms)
def vend(ms, cls, rule):
    return any(x.startswith("SOLEUR_EGRESS_VEND ") and f" class={cls} " in x and re.search(rf" rule={rule}( |$)", x) for x in ms)
a6 = {}
for v in ("http1.1", "http2"):
    t = dict(re.findall(r"^a6 (get|post) (n=\d+ code=\d{3})$", rd(f"a6-{v}.out"), re.M))
    a6[v] = {"get": t.get("get", ""), "post": t.get("post", ""), "markers": mk(f"a6-{v}"), "stub": stub(f"a6-{v}")}
def same_conn(v):
    x = a6[v]
    posts = [r for r in x["stub"] if r["method"] == "POST" and r["auth_class"] == "real-decoy"]
    return (x["get"] == "n=1 code=200" and x["post"] == "n=0 code=403" and refusal(x["markers"], "POST", "pending")
            and any(r["method"] == "GET" and r["auth_class"] == "real-decoy" for r in x["stub"]) and not posts)
pend_keys = [k for k in o if k.startswith("pend_") or k.endswith(("rows0", "rows1")) or k in ("rows1", "rows1_retry", "rows_after_deny", "rows_end")]
max_pending = max((pend(o[k]) for k in pend_keys), default=0)
cap_hits = [x for x in m if re.search(r" reason=cap( |$)", x)]
a4a, a4b, a5 = mk("a4a"), mk("a4b"), mk("a5")
checks = {
  "no row: push refused pending, one pending row": refused(o["push1"]) and "pending" in ra and pend(o["rows1"]) == 1,
  "no real token on the refused POST git-receive-pack": o["stub1_receivepack"] == "0",
  "retry before decision keeps one row": refused(o["push1_retry"]) and o["rows1"] == o["rows1_retry"],
  "owner deny -> rejected reported, then a new pending row": o["deny"] == "200" and "rejected" in ra and o["p2_new"] == "yes",
  "approve -> vend, consumed exactly once": o["approve"] == "200" and o["push1_approved"] == "push_rc=0" and o["p2_status"] == "consumed" and o["stub_after_approve"] == "1",
  "a new hash after consume needs a new row": refused(o["push2_new_hash"]) and o["stub_push2"] == "0",
  "REST X pending, then approved": o["rest_x1"] == "x1=403" and o["rest_x1_reason"] == "pending" and o["approve_x"] == "200",
  "binding: body Y and another path are new pending actions, another repo is not allowlisted, none gets a real token":
      o["rest_y1"] == "y1=403" and o["rest_y1_reason"] == "pending" and o["rest_zpath"] == "zpath=403" and o["rest_zpath_reason"] == "pending"
      and o["rest_zrepo"] == "zrepo=403" and o["rest_zrepo_reason"] == "not-allowlisted" and o["stub_binding_misses"] == "0",
  "approved X consumed once, Idempotency-Key stripped, a replay is a new pending action": o["rest_x2"] == "x2=201" and o["x_status"] == "consumed" and '"idempotency_key":false' in o["stub_x2"] and o["rest_x3"] == "x3=403" and o["rest_x3_reason"] == "pending",
  "GraphQL mutation: pending with one new row, no real token": o["gql_g1"] == "g1=403" and o["gql_g1_reason"] == "pending" and pend(o["gql_rows1"]) == pend(o["gql_rows0"]) + 1 and o["gql_row"] == "present" and o["gql_vend_pending"] == "0",
  "GraphQL mutation: approved, the identical body vends once and consumes the row": o["gql_approve"] == "200" and o["gql_g2"] == "g2=200" and o["gql_status"] == "consumed" and o["gql_vend_approved"] == "1",
  "GraphQL mutation: a replay after consume is refused, no real token": o["gql_g3"] == "g3=403" and o["gql_g3_reason"] != "" and o["gql_vend_replay"] == "0",
  "flag off: a push from an existing copy and a listed REST write are refused flag-off, no row, no real token":
      o["off_clone"] == "cloned=yes" and refused(o["push_flag_off"]) and bool(off_markers) and all(x.endswith(":flag-off") for x in off_markers)
      and o["rest_offpost"] == "offpost=403" and o["rest_offpost_reason"] == "flag-off" and o["off_stub_real"] == "0" and o["rows_c"].strip() == "",
  "expiry: pending at ~50 s, then REJECT expired": o["exp_at_50s"] == "pending" and "expired" in re_ and o["exp_final"] == "expired",
  # Guard 2 row 8: no client in this arm sends an Authorization header, so every request the hook saw must carry
  # none; one there means header replacement ran before the hook.
  "the hook ran before header replacement (client_auth=0 on every request)": bool(hookreqs) and all(" client_auth=0" in x or x.endswith("client_auth=0") for x in hookreqs),
  # CTO R39: a live ~2 MiB push. No 0000 probe from git fails the first row: the rule is then unmeasured, not passed.
  "R39 large push: git sent the 0000 probe and it vended with no row (git-receive-pack-probe)":
      vend(a4a, "push-advert", "git-receive-pack-probe") and pend(o["a4_rows1"]) == pend(o["a4_rows0"]) + 1,
  "R39 large push: the real push waits for approval (pending, one new row, no write body at the stub)":
      refused(o["a4_push1"]) and refusal(a4a, "POST", "pending") and o["a4_row"] == "present" and not [r for r in rpack("a4a") if blen(r) != FLUSH],
  "R39 large push: after approval it is consumed once and the stub receives the decoy with the whole body (>= 2 MiB)":
      o["a4_approve"] == "200" and o["a4_push2"] == "push_rc=0" and o["a4_status"] == "consumed" and vend(a4b, "write", "git-push")
      and len([r for r in rpack("a4b") if blen(r) >= 2 * 1024 * 1024]) == 1,
  "R40 a ~4 MiB push is refused body-over-cap, with no row and no decoy on the write":
      refused(o["a5_push"]) and refusal(a5, "POST", "guard-refused", "body-over-cap") and o["a5_rows0"] == o["a5_rows1"]
      and not [r for r in rpack("a5") if blen(r) != FLUSH],
  "R40 same connection, HTTP/1.1: a reused connection's unapproved POST is pending, no real token": same_conn("http1.1"),
  "R40 same connection, HTTP/2: a reused connection's unapproved POST is pending, no real token": same_conn("http2"),
  "no conversation reached the 5-pending cap and no request was refused reason=cap": max_pending < 5 and not cap_hits,
}
json.dump({"observations": o, "reasons": {"sessD": ra, "sessC": rc, "sessE": re_}, "max_pending": max_pending, "cap_hits": cap_hits,
           "large_push": {"push1_markers": a4a, "push2_markers": a4b, "push1_receive_pack_bodies": [blen(r) for r in rpack("a4a")],
                          "push2_receive_pack_bodies": [blen(r) for r in rpack("a4b")], "probe_seen": vend(a4a, "push-advert", "git-receive-pack-probe")},
           "over_cap_push": {"markers": a5, "receive_pack_bodies": [blen(r) for r in rpack("a5")]},
           "same_connection": {v: {k: x[k] for k in ("get", "post", "markers")} for v, x in a6.items()}, "checks": checks}, open(f"{d}/raw.json", "w"))
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
  SPIKE_CUR=5
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
  # The identity refusal carries no soleur_reason annotation; the hook's own guards do. An empty reason is required so
  # a refusal by any other guard (the tunnel guard, run 42811970877) cannot pass for the identity check.
  "A's hook client certificate on B's socket is refused (client identity)": str(o.get("aHookCertOnB", "")).strip() == "HOOK_CLIENT action=REJECT status=403 reason=",
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
  SPIKE_CUR=9
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
  port=$((port + 1)); local lab="${3:-$1}" h="$2" up=no rc ge c
  openssl s_server -quiet -accept "127.0.0.1:$port" -cert "$L/$1.pem" -key "$L/$1.key" -www >/dev/null 2>&1 & local sp=$!
  for _ in $(seq 1 30); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { up=yes; break; }; sleep 0.1; done
  # A row whose listener never came up measured nothing: every client reads `nolisten`, neither accept nor reject,
  # so the row fails whichever outcome it expects.
  if [ "$up" != yes ]; then
    for c in curl git node; do echo "res $lab $c nolisten"; done
    kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null; return
  fi
  # curl: accept on exit 0, reject only on exit 60 (the peer certificate failed verification); any other exit (a
  # refused or reset connection, a timeout) is an error, never a rejection.
  curl -sS -o /dev/null --max-time 8 --noproxy '*' --cacert "$BUNDLE" --connect-to "$h:$port:127.0.0.1:$port" "https://$h:$port/" 2>/dev/null; rc=$?
  case "$rc" in 0) echo "res $lab curl accept" ;; 60) echo "res $lab curl reject rc=60" ;; *) echo "res $lab curl error rc=$rc" ;; esac
  ge="$(GIT_SSL_CAINFO="$BUNDLE" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 timeout 10 git -c "http.curloptResolve=$h:$port:127.0.0.1" ls-remote "https://$h:$port/x.git" 2>&1)"
  # reject only on git's own certificate or SSL message; accept only on an HTTP-level answer from the server (never a
  # bare "http", which matches git's echo of the URL itself), so a refused connection reads neither.
  if printf '%s' "$ge" | grep -qiE 'certificate|ssl'; then echo "res $lab git reject"
  elif printf '%s' "$ge" | grep -qiE 'not found|not valid|repository|returned error'; then echo "res $lab git accept"
  else echo "res $lab git unknown"; fi
  # node: reject only on a certificate or TLS verification code; ECONNREFUSED, ECONNRESET and the like are errors.
  # Node has no code for a name-constraint violation: it reports code UNSPECIFIED with the message "permitted subtree
  # violation" or "excluded subtree violation" (measured 2026-11-10, node openssl/3.5.9), so that pair is a rejection.
  NODE_EXTRA_CA_CERTS="$BUNDLE" timeout 10 node -e 'const [h,p]=process.argv.slice(1); const cert=/^(ERR_TLS_|ERR_SSL_|CERT_|UNABLE_TO_|SELF_SIGNED_|DEPTH_ZERO_|HOSTNAME_MISMATCH|IP_ADDRESS_MISMATCH|PERMITTED_SUBTREE_VIOLATION|EXCLUDED_VIOLATION|SUBTREE_TYPE_NOT_SUPPORTED|UNSUPPORTED_(NAME_SYNTAX|CONSTRAINT_TYPE|CONSTRAINT_SYNTAX)|NAME_CONSTRAINTS_|INVALID_(CA|PURPOSE|NON_CA)|PATH_LENGTH_EXCEEDED)/; require("https").get({host:"127.0.0.1",port:+p,servername:h==="127.0.0.1"?undefined:h,headers:{host:h}},r=>{console.log("accept");process.exit(0)}).on("error",e=>{const c=String(e.code||""), nc=c==="UNSPECIFIED"&&/^(permitted|excluded) subtree violation$/.test(String(e.message||"")); console.log((cert.test(c)||nc?"reject ":"error ")+c+(nc?":"+String(e.message).split(" ")[0]+"-subtree-violation":""));process.exit(0)})' "$h" "$port" 2>/dev/null | sed "s/^/res $lab node /"
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
    # The outcome word first (accept, reject, error, unknown, nolisten), then its detail (curl's exit, node's code).
    if p[:1] == ["res"] and len(p) >= 4: res[f"{p[1]}.{p[2]}"] = " ".join(p[3:])
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
_c7_rest() { # <step> <out> [<path suffix, default issues>]
  cat > "$SPIKE_WORK/c7/req.sh" <<'EOS'
curl -sS -o /dev/null --max-time 15 -w "$STEP=%{http_code}\n" --cacert "$CA" -x "$P" -H 'content-type: application/json' \
  --data '{"title":"spike synthetic issue","body":"synthetic"}' "https://api.github.com/repos/spike/beta/$VERB" 2>/dev/null || echo "$STEP=000"
EOS
  { echo "STEP=$1"; echo "VERB=${3:-issues}"; cat "$SPIKE_WORK/c7/req.sh"; } > "$SPIKE_WORK/c7/req-$1.sh"
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
  SPIKE_CUR=7
  mkdir -p "$d" || harness_fail DRIVER "mkdir c7"
  h1="$(sha256sum "$SPIKE_DIR/approval-hook.mjs" "$SPIKE_DIR/policy.mjs" | awk '{print $1}' | tr '\n' ' ')"
  rows0="$(spike_psql "c7 row count before" "SELECT count(*) FROM public.approval_request WHERE conversation_id = '$CONV_B'")"
  seq="$(spike_stub_seq)"
  _c7_rest pass1 "$d/pass1.out"
  rows1="$(spike_psql "c7 row count after" "SELECT count(*) FROM public.approval_request WHERE conversation_id = '$CONV_B'")"
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
  # Binding across verbs: a row approved for "create pull request" with body X must not authorize "create issue"
  # with the same body X (found 2026-11-10: the canonical path dropped literal segments, so the two shared a hash).
  local bseq bpull bapprove
  bseq="$(spike_stub_seq)"
  _c7_rest bindpull "$d/bindpull.out" pulls
  bpull="$(spike_latest_pending "$CONV_B")"; bapprove="$(spike_decide ownerB "$bpull" approve)"
  _c7_rest bindissue "$d/bindissue.out" issues
  local bvend; bvend="$(spike_stub_since "$bseq" | grep '"path":"/repos/spike/beta/issues"' | grep -c '"auth_class":"real-decoy"')"
  printf '%s %s %s\n' "${bpull:+present}" "$bapprove" "$bvend" > "$d/binding.txt"
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
  "binding across verbs: an approved create-pull row does not authorize create-issue with the same body": open(f"{d}/binding.txt").read().split() == ["present", "200", "0"] and rd("bindissue.out") == "bindissue=403",
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
run() { local n=\$1; shift; local t0 t1 rc; t0=\$(up); timeout -k 2 ${C8_CLIENT_CAP:-30} "\$@" >/dev/null 2>&1; rc=\$?; t1=\$(up); echo "c8 \$L \$n rc=\$rc elapsed=\$(echo "\$t1 \$t0" | awk '{printf "%.2f", \$1-\$2}')"; }
w=/home/soleur/c8-$2
[ -d "\$w/.git" ] || HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" timeout 30 git clone -q https://github.com/spike/alpha.git "\$w" >/dev/null 2>&1
[ -d "\$w/.git" ] && git -C "\$w" -c user.email=spike@example.invalid -c user.name=spike commit -q --allow-empty -m "c8 \$L"
run gitPush env HTTPS_PROXY="\$P" GIT_SSL_CAINFO="\$CA" git -C "\$w" push -q origin HEAD:refs/heads/spike-c8-\$L
run curlPost curl -sS -f -o /dev/null --cacert "\$CA" -x "\$P" -H 'content-type: application/json' --data "{\"title\":\"c8 \$L\",\"head\":\"a\",\"base\":\"main\"}" https://api.github.com/repos/spike/alpha/pulls
run ghPost env HTTPS_PROXY="\$P" SSL_CERT_FILE="\$CA" GH_TOKEN=spike-placeholder gh api -X POST repos/spike/alpha/pulls -f title="c8 gh \$L" -f head=a -f base=main
run curlGet curl -sS -f -o /dev/null --cacert "\$CA" -x "\$P" https://api.github.com/repos/spike/alpha
run sse sh -c 'test "\$(curl -sS -N --max-time 20 --cacert "\$CA" -x "\$P" https://sse.open-web.spike.test/sse 2>/dev/null | grep -c "^event: tick")" = 50'
EOS
  spike_cx "$2" "$SPIKE_WORK/c8/clients-$1.sh" "$3"
}

arm_c8() {
  local d="$SPIKE_WORK/c8" kong seq hs he
  SPIKE_CUR=8
  mkdir -p "$d" && : > "$d/windows.jsonl" || harness_fail DRIVER "mkdir c8"
  window() { # <label> <stub seq at start>
    python3 -I -c 'import json, sys; print(json.dumps({"label": sys.argv[1], "seq": int(sys.argv[2])}))' "$1" "$2" >> "$d/windows.jsonl"
  }
  kong="$(docker ps --filter "label=$SPIKE_SUPA_LABEL" --filter 'name=supabase_kong' --format '{{.Names}}' | head -1)"
  # Positive control: a healthy hook, the same clients (sessA; the writes are refused pending, the read vends).
  window control "$(spike_stub_seq)"; _c8_clients control sessA "$d/control.out"
  # Stalled: the hook is alive but its RPC cannot finish (the API gateway is paused); its 5 s deadline answers.
  # Without the gateway container the stalled window cannot run: a missing harness input, never a scored failure.
  echo 0 > "$d/hook-timeouts.txt"
  if [[ -n "$kong" ]]; then
    docker pause "$kong" >/dev/null 2>&1
    window stalled "$(spike_stub_seq)"; hs="$(spike_hook_lines)"
    _c8_clients stalled sessA "$d/stalled.out"
    he="$(spike_hook_lines)"
    docker unpause "$kong" >/dev/null 2>&1
    # Only the stalled window's markers (lines hs+1..he), anchored on the refusal marker and session A.
    if (( he > hs )); then
      docker logs "$SPIKE_HOOK_CTR" 2>&1 | sed -n "$((hs + 1)),${he}p" \
        | grep -E '^SOLEUR_EGRESS_VEND_REFUSED .*session=sessA .*reason=hook-timeout( |$)' | wc -l | tr -d ' ' > "$d/hook-timeouts.txt"
    fi
  else
    spike_harness_err "KONG no supabase_kong container for this stack (stalled window not run)"
  fi
  # Frozen: the hook process is frozen (cgroup freezer, the SIGSTOP of R27); iron-proxy has no deadline of its own.
  docker pause "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  # A frozen hook makes each inject-host client wait until its own timeout (R27: recorded, not scored), so the per-client
  # cap is shorter here and the script's cap longer, or the read and the SSE never run (run 42809989901).
  window frozen "$(spike_stub_seq)"; C8_CLIENT_CAP=15 SPIKE_CX_TIMEOUT=200 _c8_clients frozen sessA "$d/frozen.out"
  docker unpause "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  # Killed hook.
  docker kill "$SPIKE_HOOK_CTR" >/dev/null 2>&1
  window hookKilled "$(spike_stub_seq)"; _c8_clients hookKilled sessA "$d/hookKilled.out"
  docker exec "$SPIKE_APP_CTR" sh -c 'cat /run/spike/sessA/logs/iron-proxy.log' 2>/dev/null | tr -d '\000' | grep -a '"action":"error"' | grep -ac 'approval-hook' > "$d/iron-hook-errors.txt"
  # Killed router (session B): all of B's egress fails.
  docker exec "$SPIKE_APP_CTR" sh -c 'kill "$(cat /run/spike/sessB/state/router.pid)"' >/dev/null 2>&1
  window routerKilled "$(spike_stub_seq)"; _c8_clients routerKilled sessB "$d/routerKilled.out"
  # Killed iron-proxy (session A): inject hosts fail; the forwarder branch (open-web SSE) still streams.
  docker exec "$SPIKE_APP_CTR" sh -c 'kill "$(cat /run/spike/sessA/state/iron.pid)"' >/dev/null 2>&1
  window ironKilled "$(spike_stub_seq)"; _c8_clients ironKilled sessA "$d/ironKilled.out"
  cp "$SPIKE_STUB_RECORDS" "$d/stub-all.jsonl"
  # CTO R30/R33: the CLI's own streaming, after confirming iron-proxy is really gone.
  local iron_dead=no
  docker exec "$SPIKE_APP_CTR" sh -c 'kill -0 "$(cat /run/spike/sessA/state/iron.pid)"' >/dev/null 2>&1 || iron_dead=yes
  mkdir -p "$d/stream" && spike_claude_stream "$d/stream"
  python3 -I - "$d" "${kong:+present}" "$iron_dead" > "$d/verdict.txt" <<'PYC8'
import json, sys
d, kong, iron_dead = sys.argv[1], sys.argv[2], sys.argv[3]
stream = json.load(open(f"{d}/stream/stream.json"))
wins = [json.loads(l) for l in open(f"{d}/windows.jsonl")]
# Windows are line offsets (spike_stub_seq), so each record is placed by its line number, not its seq field.
stub = [dict(json.loads(l), line=i) for i, l in enumerate(open(f"{d}/stub-all.jsonl"), 1) if l.strip()]
res = {}
for w in wins:
    for line in open(f"{d}/{w['label']}.out"):
        p = line.split()
        if p[:1] == ["c8"] and len(p) == 5:
            res[(p[1], p[2])] = {"rc": int(p[3].split("=")[1]), "elapsed": float(p[4].split("=")[1])}
def real_token_in(label):
    i = [w["label"] for w in wins].index(label)
    lo, hi = wins[i]["seq"], (wins[i + 1]["seq"] if i + 1 < len(wins) else 10**9)
    return [r for r in stub if lo < r["line"] <= hi and r["auth_class"] == "real-decoy"]
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
  "killed iron-proxy: claude streaming continues 50/50 on its own path (R30/R33)": iron_dead == "yes" and stream.get("ok") is True,
}
json.dump({"results": {f"{a}.{b}": v for (a, b), v in res.items()}, "hook_timeouts": hook_timeouts, "iron_hook_errors": iron_errors,
           "frozen_client_wait_recorded_not_scored": frozen_wait, "claude_streaming_after_iron_killed": stream,
           "iron_proxy_dead": iron_dead, "checks": checks}, open(f"{d}/raw.json", "w"))
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
  SPIKE_CUR=1
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
for s in ("sessA", "sessB", "sessC", "sessD", "sessE"):
    r = f"/run/spike/{s}"
    declared += [{"id": f"{s}-decoy-basic", "file": f"{r}/secrets/decoy.token", "transform": "basic-b64"},
                 {"id": f"{s}-ca-key", "file": f"{r}/ca/ca.key", "transform": "pem-body"},
                 {"id": f"{s}-hookclient-key", "file": f"{r}/hookclient/client.key", "transform": "pem-body"},
                 {"id": f"{s}-hook-server-key", "file": f"/run/spike/declared/{s}-server.key", "transform": "pem-body"}]
# The three roots' keys (hook server, hook client, test upstream): harness-held, copied to /run/spike/declared.
declared += [{"id": f"harness-{k}", "file": f"/run/spike/declared/{k}.key", "transform": "pem-body"}
             for k in ("hook-server-root", "hook-client-root", "upstream-root")]
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
spec = json.load(open(f"{d}/spec.json"))
st = {s["id"]: s for s in o.get("steps", [])}
scan = next((s for k, s in st.items() if k.startswith("scan:")), {})
# Every declared surface must be scanned: the driver drops a value under 8 characters silently from its scan.
want_declared = len(spec.get("declaredFiles", []))
cli = ["readDecoy", "readCaKey", "readHookSocket", "readHookClientKey", "readIronYaml", "readInjectorEnviron", "readInjectorCmdline", "readForwarderEnviron", "webfetchDecoy"]
leaks = {k: s.get("hits") for k, s in st.items() if [h for h in (s.get("hits") or []) if h != "planted-control"]}
refused = {k: (st.get(k, {}).get("isError") is True and not st.get(k, {}).get("hits")) for k in cli}
checks = {
  "every declared secret surface was scanned (declaredCount equals the declared files, none dropped)": want_declared > 0 and o.get("declaredCount") == want_declared and not o.get("declaredDropped"),
  "the sandbox scan is live (planted control found in the scanned file)": "planted-control" in (scan.get("hits") or []) and "readable=true" in (scan.get("content") or ""),
  "no session secret in anything the sandbox or the tools returned": not leaks,
  "sandboxed Bash cannot connect() the hook socket": "connected" not in (st.get("sandboxHookConnect", {}).get("content") or "") and "error" in (st.get("sandboxHookConnect", {}).get("content") or ""),
  "control: the Read tool returns a planted workspace file": "planted-control" in (st.get("readPlanted", {}).get("hits") or []),
  "control: the same uid outside the sandbox reads the injector's /proc environ": ctl.isdigit() and int(ctl) > 0,
  "every CLI-tier Read/WebFetch of a secret surface is refused": all(refused.values()),
}
json.dump({"steps": {k: {"isError": s.get("isError"), "hits": s.get("hits"), "content": (s.get("content") or "")[:300]} for k, s in st.items()},
           "leaks": leaks, "cli_refused": refused, "proc_environ_control_bytes": ctl,
           "declared": {"files": want_declared, "scanned": o.get("declaredCount"), "dropped": o.get("declaredDropped")}, "checks": checks}, open(f"{d}/raw.json", "w"))
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
  SPIKE_CUR=6
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
# The metrics listener: iron-proxy v0.56.0 serves /healthz only (internal/metrics has no Prometheus handler), so
# /metrics must be a 404 and /healthz a 200 whose body, kept for the judge, is scanned with the full secret list.
curl -sS --max-time 8 -o /dev/null -w 'metrics http=%{http_code}\n' "http://127.0.0.1:$((SPIKE_SESS_sessA_TUNNEL + 3))/metrics" 2>/dev/null || echo "metrics http=000"
curl -sS --max-time 8 -o /run/spike/c6-healthz.txt -w 'healthz http=%{http_code}\n' "http://127.0.0.1:$((SPIKE_SESS_sessA_TUNNEL + 3))/healthz" 2>/dev/null || echo "healthz http=000"
EOS
  seq="$(spike_stub_seq)"
  docker exec -i -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" bash -s < "$d/c6.sh" > "$d/probes.out" 2>&1
  spike_stub_since "$seq" > "$d/stub.jsonl"
  # A1 (CTO R36): three CONNECTs carrying the ROUTER credential (read from router-injector.cred as the router reads
  # it), sent straight to iron-proxy's listeners: http_listen, https_listen over TLS (no SNI: scored; SNI equal to the
  # CONNECT host: recorded, scored on no real token only), and inside an established tunnel_listen tunnel. A2 (R37):
  # plain HTTP inside a 443 tunnel through the router. Each probe has its own window of session A's hook markers,
  # stub records and squid lines; the forwarder logs no request content, so what it received is recorded unmeasured.
  local cp=/app/test/infra/egress-injector-spike/probes/connect-probe.mjs cr=/run/spike/sessA/secrets/router-injector.cred
  local cb=/run/spike-pub/sessA/bundle.pem t="$SPIKE_SESS_sessA_TUNNEL"
  mkdir -p "$d/win"
  printf 'node %s http-listen %s %s %s api.github.com\n' "$cp" "$((t + 1))" "$cr" "$cb" > "$d/win/a1-http-listen.sh"
  printf 'node %s https-listen %s %s %s api.github.com none\n' "$cp" "$((t + 2))" "$cr" "$cb" > "$d/win/a1-https-listen.sh"
  printf 'node %s https-listen %s %s %s api.github.com api.github.com\n' "$cp" "$((t + 2))" "$cr" "$cb" > "$d/win/a1-https-listen-sni.sh"
  printf 'node %s in-tunnel %s %s %s api.github.com\n' "$cp" "$t" "$cr" "$cb" > "$d/win/a1-in-tunnel.sh"
  printf '%s\n' 'curl -sS -o /dev/null --max-time 12 -w "a2 http=%{http_code} connect=%{http_connect}\n" -p -x "$P" http://api.github.com:443/repos/spike/alpha 2>&1' > "$d/win/a2-get.sh"
  printf '%s\n' 'curl -sS -o /dev/null --max-time 12 -w "a2 http=%{http_code} connect=%{http_connect}\n" -p -x "$P" -H "content-type: application/json" --data "{\"title\":\"c6 plain\",\"head\":\"a\",\"base\":\"main\"}" http://api.github.com:443/repos/spike/alpha/pulls 2>&1' > "$d/win/a2-post.sh"
  local w h sq
  for w in a1-http-listen a1-https-listen a1-https-listen-sni a1-in-tunnel a2-get a2-post; do
    h="$(spike_hook_lines)"; seq="$(spike_stub_seq)"; sq="$(spike_squid_log | wc -l)"
    spike_cx sessA "$d/win/$w.sh" "$d/win/$w.out"
    spike_hook_markers_since "$h" | grep -E '^SOLEUR_EGRESS_' | grep -F 'session=sessA ' | sed -E 's/ request_id=[^ ]+//' > "$d/win/$w.markers"
    spike_stub_since "$seq" > "$d/win/$w.stub"
    spike_squid_log | tail -n +$((sq + 1)) > "$d/win/$w.squid"
  done
  # Unentitled session (CTO R34: scored on the driver's deny answer), the entitled positive control, and the sandbox's
  # view of container loopback (direct, and forced through the SDK's proxy where the NO_PROXY rule must deny).
  local hp=$((SPIKE_SESS_sessA_TUNNEL + 2)) hl=$((SPIKE_SESS_sessA_TUNNEL + 1)) nseq nr ns
  python3 -I - "$d/steps-n.json" "$d/steps-e.json" "$hp" "$hl" <<'PYS' || { record_verdict 6 unmeasurable "harness:DRIVER c6 specs"; return; }
import json, sys
hp, hl = sys.argv[3], sys.argv[4]
probe = lambda urls: " ; ".join(f"echo \"{u} $(curl -sS -o /dev/null --max-time 10 -w '%{{http_code}}' {u} 2>/dev/null)\"" for u in urls)
json.dump([{"id": "unentitled", "tool": "Bash", "input": {"command": probe(["https://sse.open-web.spike.test/", "https://api.github.com/repos/spike/alpha", f"https://127.0.0.1:{hp}/"])}}], open(sys.argv[1], "w"))
forced = " ; ".join(f"echo \"forced {u} $(curl -sS -o /dev/null --max-time 10 --noproxy '' -x \"$HTTPS_PROXY\" -w '%{{http_code}}' {u} 2>/dev/null)\"" for u in (f"http://127.0.0.1:{hl}/", f"http://localhost:{hl}/"))
json.dump([{"id": "entitledControl", "tool": "Bash", "input": {"command": probe(["https://sse.open-web.spike.test/"])}},
           {"id": "loopbackDirect", "tool": "Bash", "input": {"command": probe([f"https://127.0.0.1:{hp}/", f"http://localhost:{hl}/"])}},
           {"id": "loopbackForced", "tool": "Bash", "input": {"command": forced}}], open(sys.argv[2], "w"))
PYS
  nseq="$(spike_stub_seq)"; nr="$(docker exec "$SPIKE_APP_CTR" sh -c 'wc -l < /run/spike/sessA/logs/router.log' 2>/dev/null)"; ns="$(spike_squid_log | wc -l)"
  spike_spec "$d/spec-n.json" sessA N "$d/steps-n.json"
  spike_drive sessA N "$d/spec-n.json" "$d/out-n.json" || { record_verdict 6 unmeasurable "harness:DRIVER unentitled"; return; }
  printf '%s\n%s\n%s\n' "$(spike_stub_since "$nseq" | wc -l)" "$(docker exec "$SPIKE_APP_CTR" sh -c "tail -n +$((nr + 1)) /run/spike/sessA/logs/router.log" 2>/dev/null | wc -l)" "$(spike_squid_log | tail -n +$((ns + 1)) | wc -l)" > "$d/unentitled-traces.txt"
  spike_spec "$d/spec-e.json" sessA B "$d/steps-e.json"
  spike_drive sessA B "$d/spec-e.json" "$d/out-e.json" || { record_verdict 6 unmeasurable "harness:DRIVER entitled control"; return; }
  # Recorded only (R34): the same unentitled probe with every SandboxNetworkAccess request allowed.
  printf '{"networkAllowAll": true}\n' > "$d/allowall-extras.json"
  spike_spec "$d/spec-n-allowall.json" sessA N "$d/steps-n.json" "$d/allowall-extras.json"
  spike_drive sessA N "$d/spec-n-allowall.json" "$d/out-n-allowall.json" || printf '{"error": "driver"}\n' > "$d/out-n-allowall.json"
  # Log grep (deepen pass): every log is non-empty and a control copy carrying the canary is found first.
  mkdir -p "$d/logs"
  docker exec "$SPIKE_APP_CTR" sh -c 'cd /run/spike && for s in sess*; do for f in $s/logs/*.log; do [ -f "$f" ] && { echo "=== $f"; tr -d "\000" < "$f"; }; done; done' > "$d/logs/app.log" 2>/dev/null
  docker logs "$SPIKE_HOOK_CTR" > "$d/logs/hook.log" 2>&1
  spike_squid_log > "$d/logs/squid.log"
  docker logs "$SPIKE_STUB_CTR" > "$d/logs/stub-stdout.log" 2>&1
  python3 -I - "$d" "$canary" "$SPIKE_WORK/run" "$SPIKE_WORK" > "$d/verdict.txt" <<'PYC6'
import base64, json, os, re, sys
d, canary, run, work = sys.argv[1:5]
o, reach, metrics_http, healthz_http = {}, {}, "", ""
for line in open(f"{d}/probes.out"):
    m = re.match(r"^(\w+) http=(\d{3}) connect=(\d{3})$", line.strip())
    if m: o[m.group(1)] = (m.group(2), m.group(3))
    m = re.match(r"^reach (\d+) (open|closed)$", line.strip())
    if m: reach[m.group(1)] = m.group(2)
    m = re.match(r"^metrics http=(\d{3})$", line.strip())
    if m: metrics_http = m.group(1)
    m = re.match(r"^healthz http=(\d{3})$", line.strip())
    if m: healthz_http = m.group(1)
stub = [json.loads(l) for l in open(f"{d}/stub.jsonl") if l.strip()]
n, e, aa = (json.load(open(f"{d}/{f}")) for f in ("out-n.json", "out-e.json", "out-n-allowall.json"))
stepc = lambda o, i: next((s.get("content") or "" for s in o.get("steps", []) if s["id"] == i), "")
ncontent, econtrol, ldirect, lforced = stepc(n, "unentitled"), stepc(e, "entitledControl"), stepc(e, "loopbackDirect"), stepc(e, "loopbackForced")
traces = [int(x) for x in open(f"{d}/unentitled-traces.txt").read().split()]
ndec, edec = n.get("networkDecisions") or [], e.get("networkDecisions") or []
codes = lambda txt: [ln.split()[-1] for ln in txt.splitlines() if ln.startswith(("http", "forced"))]
# The secret list (R10's intent; the structural map): every session's credentials in each form a leak could take
# (raw, bare password, Basic base64), its CA, hook client and hook server keys, and the harness-held keys and owner
# tokens. A fixed list, so a missing file is a named harness input error, never a silently shorter scan.
b64 = lambda s: base64.b64encode(s.encode()).decode()
pem_body = lambda t: max((l for l in t.splitlines() if l and not l.startswith("-----")), key=len, default="")
FORMS = {"raw": lambda r: r, "pw": lambda r: r.split(":", 1)[1] if ":" in r else "", "basic": b64,
         "x-access": lambda r: b64(f"x-access-token:{r}"), "pem": pem_body}
specs = []
for s in ("sessA", "sessB", "sessC", "sessD", "sessE"):
    sec = f"{run}/{s}/secrets"
    specs += [(f"{s}/decoy", f"{sec}/decoy.token", "raw"), (f"{s}/decoy-basic", f"{sec}/decoy.token", "x-access"),
              (f"{s}/router-session", f"{sec}/router-session.cred", "raw"), (f"{s}/router-session-pw", f"{sec}/router-session.cred", "pw"),
              (f"{s}/router-session-basic", f"{sec}/router-session.cred", "basic"),
              (f"{s}/router-injector", f"{sec}/router-injector.cred", "raw"), (f"{s}/router-injector-pw", f"{sec}/router-injector.cred", "pw"),
              (f"{s}/router-injector-basic", f"{sec}/router-injector.cred", "basic"),
              (f"{s}/forwarder", f"{sec}/forwarder.token", "raw"), (f"{s}/forwarder-basic", f"{sec}/forwarder.cred", "basic"),
              (f"{s}/ca-key", f"{run}/{s}/ca/ca.key", "pem"), (f"{s}/hookclient-key", f"{run}/{s}/hookclient/client.key", "pem"),
              (f"{s}/hook-server-key", f"{work}/hookpriv/{s}/server.key", "pem")]
specs += [("service-role-key", f"{work}/service-role.key", "raw"), ("anon-key", f"{work}/anon.key", "raw"),
          ("hmac-key", f"{work}/hookpriv/hmac.key", "raw"), ("ownerA-jwt", f"{work}/seed/ownerA.jwt", "raw"),
          ("ownerB-jwt", f"{work}/seed/ownerB.jwt", "raw")]
specs += [(f"{k}-key", f"{work}/{k}/ca.key", "pem") for k in ("hook-server-root", "hook-client-root", "upstream-root")]
secrets, missing = [], []
for k, p, form in specs:
    try:
        secrets.append((k, FORMS[form](open(p).read().strip())))
    except OSError:
        missing.append(k)
short = [k for k, v in secrets if len(v) < 8]
hits = lambda text: [k for k, v in secrets if len(v) >= 8 and v in text] + (["body-canary"] if canary in text else [])
planted_id, planted = next(((k, v) for k, v in secrets if k == "sessA/decoy"), ("sessA/decoy", ""))
logs, log_leaks, log_live = {}, {}, {}
for f in sorted(os.listdir(f"{d}/logs")):
    text = open(f"{d}/logs/{f}", errors="replace").read()
    logs[f] = len(text)
    # The control: a copy of THIS log with a decoy-shaped value and the canary planted, through the same `hits`
    # expression the real scan uses; it must find both, or the scan below proves nothing for this log.
    control_hits = hits(text + "\n" + planted + "\n" + canary + "\n") if planted else []
    log_live[f] = len(text) > 0 and planted_id in control_hits and "body-canary" in control_hits
    if hits(text): log_leaks[f] = hits(text)
healthz_text = open(f"{run}/c6-healthz.txt", errors="replace").read() if os.path.exists(f"{run}/c6-healthz.txt") else ""
o["metrics"] = {"note": "metrics listener serves /healthz only (v0.56.0)", "metrics_http": metrics_http, "healthz_http": healthz_http,
                "healthz_bytes": len(healthz_text), "healthz_hits": hits(healthz_text)}
# A1 (R36) and A2 (R37): per-probe windows, each judged on its own hook marker and its own stub records.
rdw = lambda f: open(f"{d}/win/{f}", errors="replace").read() if os.path.exists(f"{d}/win/{f}") else ""
def window(label):
    return {"out": rdw(f"{label}.out").strip()[-300:], "markers": rdw(f"{label}.markers").splitlines(),
            "stub": [json.loads(l) for l in rdw(f"{label}.stub").splitlines() if l.strip()], "squid": rdw(f"{label}.squid").splitlines()}
W = {k: window(k) for k in ("a1-http-listen", "a1-https-listen", "a1-https-listen-sni", "a1-in-tunnel", "a2-get", "a2-post")}
no_decoy = lambda w: not any(r["auth_class"] == "real-decoy" for r in W[w]["stub"])
def connect_refusals(w):  # the subreasons of the CONNECT refusals the hook marked in that window
    return [m.group(1) for x in W[w]["markers"] if x.startswith("SOLEUR_EGRESS_CONNECT ") and " outcome=refused-407" in x
            for m in [re.search(r" subreason=([a-z-]+)", x)] if m]
def connect_continued(w):  # did the hook let a CONNECT through in that window?
    return any(x.startswith("SOLEUR_EGRESS_CONNECT ") and " outcome=continue" in x for x in W[w]["markers"])
def refused_before_hook(w):  # iron-proxy refused it itself: a TLS error, or a non-2xx with no CONNECT continue
    m = re.search(r"status=(\S+)", W[w]["out"])
    st = m.group(1) if m else ""
    return st != "" and not st.startswith("2") and not connect_continued(w)
def no_tls(w, method):
    return any(x.startswith("SOLEUR_EGRESS_VEND_REFUSED ") and f" method={method} " in x and re.search(r" reason=guard-refused( |$)", x)
               and re.search(r" subreason=no-tls( |$)", x) for x in W[w]["markers"])
o["connect_probes"] = {w: {"out": W[w]["out"], "connect_refusals": connect_refusals(w), "real_decoy_at_stub": not no_decoy(w),
                           # egress-forwarder.mjs logs no request content: what it received is not observable here.
                           "forwarder": "unmeasured: egress-forwarder.mjs logs no request content", "squid_lines": W[w]["squid"][-4:]}
                       for w in W if w.startswith("a1-")}
o["plain_http_in_tunnel"] = {w: {"out": W[w]["out"], "markers": W[w]["markers"][-4:], "real_decoy_at_stub": not no_decoy(w)} for w in W if w.startswith("a2-")}
no_real_token = not any(r["auth_class"] == "real-decoy" for r in stub)
checks = {
  "deny-CIDR, localhost and link-local targets refused at squid": all(o.get(k, ("", ""))[1] == "403" for k in ("denyCidr", "localhost", "linkLocal")),
  "port-80 targets refused on both router branches": o.get("port80Open", ("", ""))[1] == "403" and o.get("port80Inject", ("", ""))[1] == "403",
  "the forwarder refuses a bad token (407)": o.get("forwarderBadToken", ("", ""))[1] == "407",
  "an unentitled session has no route: every probe ends in a sandbox deny, nothing reaches router, squid or stub (R34)": codes(ncontent) == ["000", "000", "000"] and "deny network-outbound sse.open-web.spike.test:443" in ncontent and all(x["decision"] == "deny" for x in ndec) and len(ndec) >= 2 and traces == [0, 0, 0],
  "control: the entitled session reaches the open-web stub in the same run": codes(econtrol) == ["200"] and any(x["host"] == "sse.open-web.spike.test" and x["decision"] == "allow" for x in edec),
  "the entitled sandbox cannot reach container loopback, directly or through the SDK proxy (NO_PROXY rule denies)": codes(ldirect) == ["000", "000"] and all(c in ("000", "403") for c in codes(lforced)) and len(codes(lforced)) == 2 and "deny network-outbound 127.0.0.1" in lforced and {x["host"] for x in edec if x["decision"] == "deny"} >= {"127.0.0.1", "localhost"},
  "tunnel_listen refuses no credential, the session credential and session B's router credential (407)": all(o.get(k, ("", ""))[1] == "407" for k in ("tunnelNoCred", "tunnelSessionCred", "tunnelSessionBRouterCred")),
  "http_listen and https_listen yield no vend (R28 tunnel guard)": o.get("httpListenAbsolute", ("", ""))[0] in ("403", "502", "000") and o.get("httpListenConnect", ("", ""))[1] in ("403", "407") and o.get("httpsListen", ("", ""))[0] == "403",
  "no real token reached the stub from any listener probe": no_real_token,
  "metrics listener serves /healthz only (v0.56.0): /metrics 404, /healthz 200 and its body carries no secret":
      metrics_http == "404" and healthz_http == "200" and not o["metrics"]["healthz_hits"],
  "R36 a CONNECT with the router credential to http_listen is refused no-sni, no real token at the stub":
      "no-sni" in connect_refusals("a1-http-listen") and no_decoy("a1-http-listen"),
  # Run 42864371897: with no SNI iron-proxy cannot mint a leaf and aborts the handshake (internal_error), so the
  # CONNECT never reaches the hook; that is a refusal too, recorded in the probe's `out`.
  "R36 a CONNECT with the router credential over TLS to https_listen is refused (by the hook or by iron-proxy), no real token at the stub":
      (bool(connect_refusals("a1-https-listen")) or refused_before_hook("a1-https-listen")) and no_decoy("a1-https-listen"),
  "R36 the same over TLS with SNI equal to the CONNECT host gets no real token at the stub (the secrets method list)": no_decoy("a1-https-listen-sni"),
  "R36 a CONNECT with the router credential inside an established tunnel is refused (subreason recorded), no real token at the stub":
      bool(connect_refusals("a1-in-tunnel")) and no_decoy("a1-in-tunnel"),
  "R37 a plain-HTTP GET inside a 443 tunnel is refused no-tls, no real token at the stub": no_tls("a2-get", "GET") and no_decoy("a2-get"),
  "R37 a plain-HTTP POST inside a 443 tunnel is refused no-tls, no real token at the stub": no_tls("a2-post", "POST") and no_decoy("a2-post"),
  "every log is non-empty and its control copy (a planted decoy and the canary) is found by the same scan": all(log_live.values()) and len(log_live) >= 4,
  "no log carries a secret or the body canary": not log_leaks,
}
json.dump({"probes": o, "listener_reachability_recorded": reach, "unentitled": ncontent, "unentitled_decisions": ndec,
           "unentitled_traces_stub_router_squid": traces, "entitled_control": econtrol, "loopback_direct": ldirect,
           "loopback_forced": lforced, "entitled_decisions": edec,
           "recorded_only_unentitled_with_network_allowed": stepc(aa, "unentitled"),
           "log_sizes": logs, "log_leaks": log_leaks, "checks": checks,
           "secret_list": {"declared": len(specs), "scanned": len(secrets) - len(short), "missing": missing, "short": short},
           "not_scanned": "the CI job log itself (scanned only by GitHub's masking of every generated value)"},
          open(f"{d}/raw.json", "w"))
failed = [k for k, v in checks.items() if not v]
if missing or short or not specs:
    # Floor: the scan ran on a shorter list than declared, so neither a pass nor a fail is measured.
    print("unmeasurable")
    print(f"harness:SECRET_LIST {len(missing)} missing, {len(short)} under 8 characters: {', '.join((missing + short)[:6])}")
else:
    print("pass" if not failed else "fail")
    print("all checks held: " + "; ".join(checks) if not failed else "failed: " + "; ".join(failed))
PYC6
  observe c6 "$d/raw.json"
  spike_record_judged 6 "$d/verdict.txt"
}
