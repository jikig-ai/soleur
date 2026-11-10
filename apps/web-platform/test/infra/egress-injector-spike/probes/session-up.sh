#!/usr/bin/env bash
# Egress injector spike (#12517): one session's egress chain, started INSIDE the app container as the app uid,
# outside bwrap (CTO F-c). Test path only. Run by the suite through `docker exec -d`; stays alive as the parent the
# forwarder's and router's ppid watchdogs check, and stops its children when the suite removes the stop file.
#
#   real egress-forwarder.mjs  (unchanged; env from the dispatcher's shape, gateway = the squid container)
#   iron-proxy                 (digest-pinned binary; config rendered here from iron-proxy.config.tmpl.yaml)
#   connect-router.mjs         (the only path to iron-proxy's tunnel_listen; R24)
#
# Usage: session-up.sh <session dir>   e.g. /run/spike/sessA
# The session dir (masked for every sandbox) holds, written by the suite:
#   session.env      SESSION_ID WORKSPACE_ID GW_HOST TUNNEL_PORT HTTP_PORT HTTPS_PORT METRICS_PORT (no secrets)
#   secrets/forwarder.token  secrets/router-session.cred  secrets/router-injector.cred  secrets/decoy.token
#   ca/ca.pem ca/ca.key  hookclient/{client.pem,client.key,server-root.pem}  upstream-root.pem
# and this script writes state/{forwarder.port,router.port,iron.pid,forwarder.pid,router.pid,ready} and logs/.
# Secrets never reach argv. The forwarder's token reaches its env, exactly as spawnEgressForwarder does in production.
set -uo pipefail
case "$-" in *x*) echo "session-up: refusing xtrace"; exit 1 ;; esac
S="${1:?session dir}"
SPIKE_APP=/app/test/infra/egress-injector-spike
mkdir -p "$S/state" "$S/logs" || exit 1
fail() { echo "SESSION_UP_FAIL $*" > "$S/state/failed"; exit 1; }
# shellcheck disable=SC1091
source "$S/session.env" || fail "session.env"

wait_line() { # file, regex, seconds -> prints the first match
  local i
  for ((i = 0; i < $3 * 10; i++)); do
    if grep -qE "$2" "$1" 2>/dev/null; then grep -oE "$2" "$1" | head -1; return 0; fi
    sleep 0.1
  done
  return 1
}

# 1. The real forwarder.
EGRESS_GW_HOST="$GW_HOST" EGRESS_GW_PORT=8443 EGRESS_WORKSPACE_ID="$WORKSPACE_ID" \
  EGRESS_SESSION_TOKEN="$(cat "$S/secrets/forwarder.token")" NODE_ENV=production \
  node /app/infra/egress-forwarder.mjs > "$S/logs/forwarder.log" 2>&1 &
echo $! > "$S/state/forwarder.pid"
FWD_PORT="$(wait_line "$S/logs/forwarder.log" 'egress-forwarder-listening [0-9]+' 10 | awk '{print $2}')" || fail "forwarder did not listen"
echo "$FWD_PORT" > "$S/state/forwarder.port"

# 2. iron-proxy, configured for this session. The forwarder credential sits in the rendered file under the masked dir.
( umask 077 && printf 'http://%s:%s@127.0.0.1:%s\n' "$WORKSPACE_ID" "$(cat "$S/secrets/forwarder.token")" "$FWD_PORT" \
  > "$S/secrets/forwarder.url" ) || fail "forwarder.url"
# (The app image carries no python3, as production does not; node renders.)
node -e '
const fs = require("node:fs");
const [tmpl, out, s, tun, hp, hsp, mp] = process.argv.slice(1);
let t = fs.readFileSync(tmpl, "utf8");
const v = {
  TUNNEL_LISTEN: `127.0.0.1:${tun}`, HTTP_PORT: hp, HTTPS_PORT: hsp, METRICS_PORT: mp,
  FORWARDER_PROXY_URL: fs.readFileSync(`${s}/secrets/forwarder.url`, "utf8").trim(),
  SESSION_CA_CERT: `${s}/ca/ca.pem`, SESSION_CA_KEY: `${s}/ca/ca.key`, HOOK_SOCKET: `${s}/hook/hook.sock`,
  HOOK_SERVER_ROOT: `${s}/hookclient/server-root.pem`, HOOK_CLIENT_CERT: `${s}/hookclient/client.pem`,
  HOOK_CLIENT_KEY: `${s}/hookclient/client.key`, DECOY_TOKEN_FILE: `${s}/secrets/decoy.token`,
  UPSTREAM_DENY_CIDRS: JSON.stringify(fs.readFileSync("/app/infra/egress-deny-cidrs.txt", "utf8").split("\n")
    .map((l) => l.trim()).filter((l) => l && !l.startsWith("#") && l !== "127.0.0.0/8" && l !== "::1/128")),
};
for (const [k, val] of Object.entries(v)) t = t.split(`@@${k}@@`).join(val);
const left = [...new Set(t.match(/@@[A-Z_]+@@/g) ?? [])];
if (left.length) { console.error("unreplaced placeholders: " + left.join(" ")); process.exit(1); }
fs.writeFileSync(out, t, { mode: 0o600 });
' "$SPIKE_APP/iron-proxy.config.tmpl.yaml" "$S/iron.yaml" "$S" "$TUNNEL_PORT" "$HTTP_PORT" "$HTTPS_PORT" "$METRICS_PORT" \
  2>"$S/logs/render.err" || fail "render iron-proxy config: $(tail -1 "$S/logs/render.err")"
# A port already bound means a previous chain for this session is still alive; refuse rather than probe it.
for port in "$TUNNEL_PORT" "$HTTP_PORT" "$HTTPS_PORT" "$METRICS_PORT"; do
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && fail "port $port already bound before iron-proxy started"
done
# SSL_CERT_FILE is the test upstream root (tracer item 4): verification stays on against the stub's issuer.
SSL_CERT_FILE="$S/upstream-root.pem" /run/spike-bin/iron-proxy -config "$S/iron.yaml" > "$S/logs/iron-proxy.log" 2>&1 &
echo $! > "$S/state/iron.pid"
for ((i = 0; i < 100; i++)); do
  (exec 3<>"/dev/tcp/127.0.0.1/$TUNNEL_PORT") 2>/dev/null && break
  kill -0 "$(cat "$S/state/iron.pid")" 2>/dev/null || fail "iron-proxy exited: $(tail -2 "$S/logs/iron-proxy.log" | tr '\n' ' ' | head -c 300)"
  sleep 0.1
done
(exec 3<>"/dev/tcp/127.0.0.1/$TUNNEL_PORT") 2>/dev/null || fail "iron-proxy tunnel_listen not up"
kill -0 "$(cat "$S/state/iron.pid")" 2>/dev/null || fail "iron-proxy exited after binding"

# 3. The router: the session credential in, the router-only credential to iron-proxy, the forwarder credential out.
( umask 077 && printf '%s:%s\n' "$WORKSPACE_ID" "$(cat "$S/secrets/forwarder.token")" > "$S/secrets/forwarder.cred" ) || fail "forwarder.cred"
node -e '
const fs = require("node:fs");
const [out, sid, s, tun, fwd] = process.argv.slice(1);
const cfg = { sessionId: sid, sessionCredentialFile: `${s}/secrets/router-session.cred`,
  injector: { host: "127.0.0.1", port: Number(tun), credentialFile: `${s}/secrets/router-injector.cred` },
  forwarder: { host: "127.0.0.1", port: Number(fwd), credentialFile: `${s}/secrets/forwarder.cred` },
  listenHost: "127.0.0.1", listenPort: 0 };
fs.writeFileSync(out, JSON.stringify(cfg), { mode: 0o600 });
' "$S/router.json" "$SESSION_ID" "$S" "$TUNNEL_PORT" "$FWD_PORT" || fail "router config"
node "$SPIKE_APP/connect-router.mjs" "$S/router.json" > "$S/logs/router.log" 2>&1 &
echo $! > "$S/state/router.pid"
RT_PORT="$(wait_line "$S/logs/router.log" 'connect-router-listening [0-9]+' 10 | awk '{print $2}')" || fail "router did not listen"
echo "$RT_PORT" > "$S/state/router.port"
touch "$S/state/ready"

# Stay alive (the forwarder's and router's ppid watchdogs need a live parent) until the suite asks us to stop, or a
# child dies (criterion 8 kills them on purpose; the suite reads which one through the pid files).
touch "$S/state/run"
while [[ -e "$S/state/run" ]]; do sleep 1; done
for p in forwarder iron router; do kill "$(cat "$S/state/$p.pid")" 2>/dev/null; done
wait
# Session end (spec TR3): the session's CA key does not outlive the session. This script stands in for the
# dispatcher that owns the session's lifetime; criterion 9 checks the key's absence after this exit, and the suite
# itself never deletes it.
rm -f "$S/ca/ca.key"
touch "$S/state/ended"
