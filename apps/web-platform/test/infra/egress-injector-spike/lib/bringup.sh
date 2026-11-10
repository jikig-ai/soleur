# shellcheck shell=bash
# Egress injector spike (#12517): topology bring-up, sourced by injector-spike-docker.test.sh after lib/harness.sh.
# Test path only. Every failure goes through harness_fail with a named token; nothing here skips.
#
# Topology (plan "Injector spike"; CTO F-c, R9, R21, R24):
#
#   spike-ext  docker --internal network, subnet SPIKE_EXT_SUBNET (public range, outside egress-deny-cidrs.txt, no
#              route out). The stub destinations container answers by DNS alias for the four inject hosts and
#              api.anthropic.com. Squid resolves through docker's embedded resolver 127.0.0.11 (the real conf).
#   spike-int  docker --internal network joining squid and the app container (the production soleur-egress0 role).
#              The app container is ALSO on spike-ext: production's app tier reaches its NO_PROXY hosts directly.
#   app        the production base image plus the runner stage's packages, run with the prod tuple's posture
#              (lib/docker-run-tuple.py), uid 1001. Per session it runs, outside bwrap: the real egress-forwarder.mjs,
#              connect-router.mjs and iron-proxy (the static binary copied out of the digest-pinned image).
#   hook       approval-hook.mjs in its own container with --network host (R21: 127.0.0.1 is the loopback the local
#              Supabase stack binds), uid 1001. Its sockets live in the shared per-session run directory; its own
#              keys live in a directory only the hook container mounts.
#
# Paths inside the app container: /app (apps/web-platform, read-only), /run/spike/<session>/... (secrets, CA,
# hook socket, configs; masked for every sandbox through denyReadExtra), /run/spike-bin/iron-proxy, and
# /run/spike-pub/<session>/bundle.pem (the only per-session file a sandbox may read: certificates, no keys).
#
# Functions (all set globals; none prints a secret):
#   spike_posture          POSTURE_OPTS, SPIKE_BASE_IMAGE, SPIKE_APP_UID
#   spike_apparmor         APPARMOR_OPT_VALUE (loads the profile; local override refused under CI)
#   spike_build_image      SPIKE_IMG
#   spike_iron_proxy_bin   copies the binary to $SPIKE_WORK/bin/iron-proxy
#   spike_networks         SPIKE_NET_EXT, SPIKE_NET_INT
#   spike_start_stub       SPIKE_STUB_CTR (+ the test upstream root and stub leaf)
#   spike_start_squid      SPIKE_SQUID_CTR, SPIKE_SQUID_IP
#   spike_start_app        SPIKE_APP_CTR
#   spike_fix_owner <dir>  chown -R 1001 through a throwaway root container (host uid may differ)
#   spike_teardown         removes every container and network this run created (EXIT trap)

SPIKE_EXT_SUBNET="${SPIKE_EXT_SUBNET:-11.12.13.0/24}"
SPIKE_RUN_ID="spike$$"
SPIKE_CONTAINERS=()
SPIKE_NETWORKS=()

_spike_docker_run() { # name, args... (records the container for teardown)
  local name="$1"; shift
  SPIKE_CONTAINERS+=("$name")
  docker run -d --name "$name" "$@" >/dev/null 2>"$SPIKE_WORK/docker-run-$name.err"
}

spike_teardown() {
  local c n
  for c in "${SPIKE_CONTAINERS[@]}"; do docker rm -f "$c" >/dev/null 2>&1; done
  for n in "${SPIKE_NETWORKS[@]}"; do docker network rm "$n" >/dev/null 2>&1; done
  # Files chowned to the app uid may not be removable by the host uid (it differs outside CI): empty the work dir as
  # root in a throwaway container, then let the caller remove the directory itself.
  if [[ -n "${SPIKE_IMG:-}" && -d "$SPIKE_WORK" ]]; then
    docker run --rm -u 0 -v "$SPIKE_WORK:/w" "$SPIKE_IMG" find /w -mindepth 1 -delete >/dev/null 2>&1
  fi
  [[ -n "${SPIKE_IMG:-}" ]] && docker rmi "$SPIKE_IMG" >/dev/null 2>&1
  return 0
}

spike_posture() {
  local tuple_py="$WP/infra/lib/docker-run-tuple.py" raw line opt val aa=0 sc=0
  raw="$(python3 -I "$tuple_py" posture --tuple prod --root "$WP" 2>"$SPIKE_WORK/posture.err")" \
    || harness_fail TUPLE_CHECK "posture --tuple prod failed: $(head -c 300 "$SPIKE_WORK/posture.err")"
  [[ -n "$raw" ]] || harness_fail TUPLE_CHECK "posture --tuple prod printed nothing"
  POSTURE_OPTS=()
  while IFS= read -r line; do
    opt="${line%% *}"; val=""
    [[ "$line" == *" "* ]] && val="${line#* }"
    case "$opt $val" in
      "--init ") POSTURE_OPTS+=(--init) ;;
      "--tmpfs /tmp:"*) POSTURE_OPTS+=(--tmpfs "$val") ;;
      "--security-opt apparmor="*) POSTURE_OPTS+=(--security-opt "apparmor=@APPARMOR@"); aa=$((aa + 1)) ;;
      "--security-opt seccomp="*) POSTURE_OPTS+=(--security-opt "seccomp=$WP/infra/seccomp-bwrap.json"); sc=$((sc + 1)) ;;
      *) harness_fail TUPLE_CHECK "the prod tuple posture carries '$line', which this suite has no mapping for" ;;
    esac
  done <<<"$raw"
  [[ "$aa" -eq 1 && "$sc" -eq 1 ]] || harness_fail TUPLE_CHECK "prod posture has $aa apparmor and $sc seccomp entries (expected one each)"
  [[ -r "$WP/infra/seccomp-bwrap.json" ]] || harness_fail TUPLE_CHECK "infra/seccomp-bwrap.json missing"
  SPIKE_BASE_IMAGE="$(sed -n 's/^FROM \(node:[^ ]*@sha256:[0-9a-f]\{64\}\) AS cli-tools$/\1/p' "$WP/Dockerfile" | head -1)"
  [[ -n "$SPIKE_BASE_IMAGE" ]] || harness_fail TUPLE_CHECK "the Dockerfile's cli-tools stage is not FROM a digest-pinned node image"
  SPIKE_APP_UID="$(sed -n 's/.*useradd .*--uid \([0-9][0-9]*\).*/\1/p' "$WP/Dockerfile" | head -1)"
  [[ "$SPIKE_APP_UID" =~ ^[0-9]+$ ]] || harness_fail TUPLE_CHECK "no useradd --uid in the Dockerfile"
  SPIKE_CLAUDE_CODE_PIN="$(sed -n 's/^RUN npm install -g @anthropic-ai\/claude-code@\([0-9][0-9.]*\)$/\1/p' "$WP/Dockerfile" | head -1)"
  SPIKE_GH_PIN="$(sed -n 's/^ARG GH_VERSION=\([0-9][0-9.]*\)$/\1/p' "$WP/Dockerfile" | head -1)"
  [[ -n "$SPIKE_CLAUDE_CODE_PIN" && -n "$SPIKE_GH_PIN" ]] || harness_fail TUPLE_CHECK "claude-code or gh pin not readable from the Dockerfile"
  export SPIKE_APP_IMAGE="$SPIKE_BASE_IMAGE+runner-packages claude-code@$SPIKE_CLAUDE_CODE_PIN gh@$SPIKE_GH_PIN"
}

spike_apparmor() {
  local profile="$WP/infra/apparmor-soleur-bwrap.profile"
  APPARMOR_OPT_VALUE="soleur-bwrap"
  if [[ "${SOLEUR_SPIKE_APPARMOR:-}" == "unconfined" ]]; then
    [[ -z "${CI:-}" ]] || harness_fail APPARMOR_UNAVAILABLE "SOLEUR_SPIKE_APPARMOR=unconfined is refused when CI is set"
    echo "APPARMOR_OVERRIDE: apparmor=unconfined (local run); the AppArmor profile is NOT measured"
    APPARMOR_OPT_VALUE="unconfined"
  else
    [[ -r /sys/kernel/security/apparmor/profiles ]] || harness_fail APPARMOR_UNAVAILABLE "AppArmor is not enabled on this host"
    command -v apparmor_parser >/dev/null 2>&1 || harness_fail APPARMOR_UNAVAILABLE "apparmor_parser not installed"
    apparmor_parser -r "$profile" 2>"$SPIKE_WORK/aa.err" \
      || { [[ "$(id -u)" != "0" ]] && sudo -n apparmor_parser -r "$profile" 2>"$SPIKE_WORK/aa.err"; } \
      || harness_fail APPARMOR_UNAVAILABLE "apparmor_parser -r failed: $(head -c 300 "$SPIKE_WORK/aa.err")"
    # The profile list is root-readable only on the CI runner (measured, run 42806898443); this suite is not run
    # under sudo, so the check takes the same sudo -n fallback as the load.
    { grep -q '^soleur-bwrap ' /sys/kernel/security/apparmor/profiles 2>/dev/null \
      || sudo -n grep -q '^soleur-bwrap ' /sys/kernel/security/apparmor/profiles 2>/dev/null; } \
      || harness_fail APPARMOR_UNAVAILABLE "profile soleur-bwrap not loaded"
  fi
  if sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
    sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1 \
      || { [[ "$(id -u)" != "0" ]] && sudo -n sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 >/dev/null 2>&1; } \
      || harness_fail SYSCTL_UNAVAILABLE "could not set kernel.apparmor_restrict_unprivileged_userns=0"
  fi
  local i
  for i in "${!POSTURE_OPTS[@]}"; do POSTURE_OPTS[$i]="${POSTURE_OPTS[$i]/@APPARMOR@/$APPARMOR_OPT_VALUE}"; done
}

# The runner stage's package set (Dockerfile, `FROM cli-tools AS runner`) on the cli-tools base, minus playwright and
# qpdf (no criterion uses them), plus procps for the CLI-tier /proc probes. The production bwrap shim is mounted at
# run time, never baked, so the image tests the checkout's shim.
spike_build_image() {
  SPIKE_IMG="soleur-injector-spike:${SPIKE_RUN_ID}"
  local ctx="$SPIKE_WORK/image"
  mkdir -p "$ctx" || harness_fail IMAGE_BUILD_FAILED "mkdir $ctx"
  cat > "$ctx/Dockerfile" <<EOF
FROM ${SPIKE_BASE_IMAGE}
RUN npm install -g @anthropic-ai/claude-code@${SPIKE_CLAUDE_CODE_PIN}
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git bubblewrap socat jq openssh-client libcap2-bin procps curl \\
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \\
 && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \\
 && echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \\
 && apt-get update \\
 && { apt-get install -y --no-install-recommends "gh=${SPIKE_GH_PIN}" || apt-get install -y --no-install-recommends gh; } \\
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u ${SPIKE_APP_UID} soleur
USER soleur
EOF
  timeout -k 10 600 docker build -q -t "$SPIKE_IMG" "$ctx" > "$SPIKE_WORK/image-build.log" 2>&1 \
    || harness_fail IMAGE_BUILD_FAILED "docker build failed: $(tail -3 "$SPIKE_WORK/image-build.log" | tr '\n' ' ' | head -c 400)"
  local bw
  bw="$(docker run --rm "$SPIKE_IMG" bwrap --version 2>&1 | head -1)"
  case "$bw" in "bubblewrap 0.8."*) ;; *) harness_fail IMAGE_DRIFT "image bubblewrap is '$bw', production runs 0.8.x" ;; esac
  # Production's Dockerfile falls back to the newest gh when the rolling apt repo drops the pin; so does this image,
  # and the version actually installed is what the results record.
  SPIKE_GH_INSTALLED="$(docker run --rm "$SPIKE_IMG" gh --version 2>/dev/null | head -1 | awk '{print $3}')"
  [[ -n "$SPIKE_GH_INSTALLED" ]] || harness_fail IMAGE_DRIFT "gh is not runnable in the image"
  export SPIKE_APP_IMAGE="$SPIKE_BASE_IMAGE+runner-packages claude-code@$SPIKE_CLAUDE_CODE_PIN gh@$SPIKE_GH_INSTALLED (pin $SPIKE_GH_PIN) $bw"
}

spike_iron_proxy_bin() {
  local ref="docker.io/ironsh/iron-proxy@${SPIKE_IRON_PROXY_DIGEST}" c
  mkdir -p "$SPIKE_WORK/bin" || harness_fail IRON_PROXY "mkdir bin"
  timeout -k 10 300 docker pull -q "$ref" > "$SPIKE_WORK/iron-pull.log" 2>&1 || harness_fail IRON_PROXY "pull $ref failed"
  c="$(docker create "$ref" 2>/dev/null)" || harness_fail IRON_PROXY "docker create failed"
  docker cp "$c:/usr/local/bin/iron-proxy" "$SPIKE_WORK/bin/iron-proxy" >/dev/null 2>&1 || { docker rm "$c" >/dev/null 2>&1; harness_fail IRON_PROXY "docker cp of the binary failed"; }
  docker rm "$c" >/dev/null 2>&1
  [[ -s "$SPIKE_WORK/bin/iron-proxy" ]] || harness_fail IRON_PROXY "binary is empty"
}

spike_networks() {
  SPIKE_NET_EXT="${SPIKE_RUN_ID}-ext"
  SPIKE_NET_INT="${SPIKE_RUN_ID}-int"
  docker network create --internal --subnet "$SPIKE_EXT_SUBNET" "$SPIKE_NET_EXT" >/dev/null 2>"$SPIKE_WORK/net.err" \
    || harness_fail NETWORK "create $SPIKE_NET_EXT ($SPIKE_EXT_SUBNET): $(head -c 200 "$SPIKE_WORK/net.err")"
  SPIKE_NETWORKS+=("$SPIKE_NET_EXT")
  docker network create --internal "$SPIKE_NET_INT" >/dev/null 2>"$SPIKE_WORK/net.err" \
    || harness_fail NETWORK "create $SPIKE_NET_INT: $(head -c 200 "$SPIKE_WORK/net.err")"
  SPIKE_NETWORKS+=("$SPIKE_NET_INT")
  # The ext subnet must sit outside every deny range, or squid would refuse the stub for the wrong reason.
  python3 -I - "$WP/infra/egress-deny-cidrs.txt" "$SPIKE_EXT_SUBNET" <<'PY' || harness_fail NETWORK "the ext subnet overlaps egress-deny-cidrs.txt"
import ipaddress, sys
net = ipaddress.ip_network(sys.argv[2])
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    d = ipaddress.ip_network(line)
    if d.version == net.version and net.overlaps(d):
        sys.exit(1)
PY
}

spike_fix_owner() {
  docker run --rm -u 0 -v "$1:/d" "$SPIKE_IMG" chown -R "${SPIKE_APP_UID}:${SPIKE_APP_UID}" /d >/dev/null 2>&1 \
    || harness_fail OWNERSHIP "chown of $1 failed"
}

# The stub destinations. Its leaf is signed by the TEST UPSTREAM root (standing in for a public CA): the sandbox
# bundle carries that root so the non-inject SSE verifies, and iron-proxy verifies the inject hosts against it.
spike_start_stub() {
  local d="$SPIKE_WORK/stub"
  mkdir -p "$d/repos" || harness_fail STUB_START "mkdir"
  [[ -s "$d/leaf.pem" ]] || harness_fail STUB_START "spike_upstream_root must run first"
  : > "$d/records.jsonl"
  SPIKE_STUB_RECORDS="$d/records.jsonl"
  spike_fix_owner "$d"
  SPIKE_STUB_CTR="${SPIKE_RUN_ID}-stub"
  _spike_docker_run "$SPIKE_STUB_CTR" --network "$SPIKE_NET_EXT" \
    --network-alias github.com --network-alias api.github.com --network-alias uploads.github.com \
    --network-alias codeload.github.com --network-alias api.anthropic.com --network-alias gist.github.com \
    --network-alias sse.open-web.spike.test \
    --sysctl net.ipv4.ip_unprivileged_port_start=443 -u "$SPIKE_APP_UID" \
    -v "$WP:/app:ro" -v "$d:/stub" "$SPIKE_IMG" node /app/test/infra/egress-injector-spike/stub-github/server.mjs /stub/config.json \
    || harness_fail STUB_START "docker run: $(head -c 300 "$SPIKE_WORK/docker-run-$SPIKE_STUB_CTR.err")"
}

# The TEST UPSTREAM root (a public CA stand-in) and the stub's leaf. Runs before any session is prepared.
spike_upstream_root() {
  mkdir -p "$SPIKE_WORK/stub" || harness_fail STUB_START "mkdir"
  mint_plain_root "$SPIKE_WORK/upstream-root" "spike test upstream root" || harness_fail STUB_START "upstream root"
  mint_leaf "$SPIKE_WORK/upstream-root" "$SPIKE_WORK/stub/leaf" \
    "DNS:github.com,DNS:api.github.com,DNS:uploads.github.com,DNS:codeload.github.com,DNS:api.anthropic.com,DNS:gist.github.com,DNS:sse.open-web.spike.test" \
    || harness_fail STUB_START "stub leaf"
}

spike_wait_log() { # container, literal line prefix, seconds
  local i
  for ((i = 0; i < $3 * 2; i++)); do
    # Not `docker logs | grep -q` under pipefail: grep exiting at the first match can kill docker logs with SIGPIPE,
    # and the pipeline then reads as no match.
    grep -q -- "$2" < <(docker logs "$1" 2>&1) && return 0
    sleep 0.5
  done
  return 1
}

spike_start_squid() {
  local d="$SPIKE_WORK/squid" ref
  ref="$(sed -n 's/^| Pinned reference | `\(ubuntu\/squid@sha256:[0-9a-f]\{64\}\)` |$/\1/p' "$WP/infra/egress-gw-image.provenance.md" | head -1)"
  [[ -n "$ref" ]] || harness_fail SQUID_START "squid pin not readable from egress-gw-image.provenance.md"
  mkdir -p "$d/tokens" || harness_fail SQUID_START "mkdir"
  chmod 0711 "$d/tokens"
  SPIKE_SQUID_TOKENS="$d/tokens"
  SPIKE_SQUID_CTR="${SPIKE_RUN_ID}-squid"
  # The production mount layout (egress-gateway-bootstrap.sh), every file from the checkout, unchanged.
  _spike_docker_run "$SPIKE_SQUID_CTR" --network "$SPIKE_NET_INT" \
    -v "$WP/infra/egress-gateway-squid.conf:/etc/squid/squid.conf:ro" \
    -v "$WP/infra/egress-auth-helper.sh:/usr/local/bin/egress-auth-helper.sh:ro" \
    -v "$WP/infra/egress-deny-cidrs.txt:/etc/squid/egress-deny-cidrs.txt:ro" \
    -v "$d/tokens:/etc/squid/session-tokens:ro" "$ref" \
    || harness_fail SQUID_START "docker run: $(head -c 300 "$SPIKE_WORK/docker-run-$SPIKE_SQUID_CTR.err")"
  docker network connect "$SPIKE_NET_EXT" "$SPIKE_SQUID_CTR" 2>"$SPIKE_WORK/net.err" \
    || harness_fail SQUID_START "connect squid to ext: $(head -c 200 "$SPIKE_WORK/net.err")"
  SPIKE_SQUID_IP="$(docker inspect -f "{{(index .NetworkSettings.Networks \"$SPIKE_NET_INT\").IPAddress}}" "$SPIKE_SQUID_CTR" 2>/dev/null)"
  [[ "$SPIKE_SQUID_IP" =~ ^[0-9.]+$ ]] || harness_fail SQUID_START "no squid address on $SPIKE_NET_INT"
}

# The squid decision log is a file inside its container (the real conf); this copies it out for the log scans.
spike_squid_log() { docker exec "$SPIKE_SQUID_CTR" cat /var/log/squid/access.log 2>/dev/null; }

spike_start_app() {
  SPIKE_APP_CTR="${SPIKE_RUN_ID}-app"
  mkdir -p "$SPIKE_WORK/run" || harness_fail CONTAINER_START_FAILED "mkdir run"
  _spike_docker_run "$SPIKE_APP_CTR" --network "$SPIKE_NET_INT" -u "$SPIKE_APP_UID" "${POSTURE_OPTS[@]}" \
    -v "$WP:/app:ro" -v "$WP/infra/bwrap-shim/bwrap:/usr/local/bin/bwrap:ro" \
    -v "$SPIKE_WORK/run:/run/spike" -v "$SPIKE_WORK/bin:/run/spike-bin:ro" -v "$SPIKE_WORK/pub:/run/spike-pub:ro" \
    -e HOME=/home/soleur "$SPIKE_IMG" sleep 7200 \
    || harness_fail CONTAINER_START_FAILED "docker run: $(head -c 300 "$SPIKE_WORK/docker-run-$SPIKE_APP_CTR.err")"
  # A direct route for the app tier, as production's app container has for its NO_PROXY hosts (the CLI process's own
  # Messages API and WebFetch preflight). Sandboxed processes never use it: bwrap leaves them only the SDK's proxy.
  docker network connect "$SPIKE_NET_EXT" "$SPIKE_APP_CTR" 2>"$SPIKE_WORK/net.err" \
    || harness_fail CONTAINER_START_FAILED "connect app to ext: $(head -c 200 "$SPIKE_WORK/net.err")"
  local i
  for ((i = 0; i < 60; i++)); do
    docker exec "$SPIKE_APP_CTR" bash -c "exec 3<>/dev/tcp/$SPIKE_SQUID_IP/8443" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  harness_fail SQUID_START "squid did not bind $SPIKE_SQUID_IP:8443 within 30 s ($(docker logs "$SPIKE_SQUID_CTR" 2>&1 | tail -2 | tr '\n' ' ' | head -c 300))"
}

# ---------------------------------------------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------------------------------------------

_spike_rand() { python3 -I -c 'import secrets, sys; print(secrets.token_urlsafe(int(sys.argv[1])))' "$1"; }
_spike_secret_file() { ( umask 077 && printf '%s\n' "$2" > "$1" ) || harness_fail SESSION_PREP "write $(basename "$1")"; }

# Roots shared by every session: the hook's server root (the injector verifies the hook) and client root (the hook
# verifies the injector, R25). Both keys stay in the suite's work dir; neither enters the app container.
spike_hook_roots() {
  mint_plain_root "$SPIKE_WORK/hook-server-root" "spike hook server root" || harness_fail SESSION_PREP "hook server root"
  mint_plain_root "$SPIKE_WORK/hook-client-root" "spike hook client root" || harness_fail SESSION_PREP "hook client root"
  mkdir -p "$SPIKE_WORK/hookpriv" "$SPIKE_WORK/pub" || harness_fail SESSION_PREP "mkdir"
  cp "$SPIKE_WORK/hook-client-root/ca.pem" "$SPIKE_WORK/hookpriv/client-root.pem"
  docker run --rm "$SPIKE_IMG" cat /etc/ssl/certs/ca-certificates.crt > "$SPIKE_WORK/system-bundle.pem" 2>/dev/null
  [[ -s "$SPIKE_WORK/system-bundle.pem" ]] || harness_fail SESSION_PREP "system CA bundle not readable from the image"
}

# spike_session_prepare <id> <index 0-9> <workspace id> <conversation id>
# Sets SPIKE_SESS_<id>_* globals; every secret value goes to a file and is masked in the CI log.
spike_session_prepare() {
  local id="$1" idx="$2" ws="$3" conv="$4" r="$SPIKE_WORK/run/$1" h="$SPIKE_WORK/hookpriv/$1" p="$SPIKE_WORK/pub/$1" v
  mkdir -p "$r/secrets" "$r/hookclient" "$r/hook" "$h" "$p" || harness_fail SESSION_PREP "mkdir $id"
  local fwd_token decoy rsess rinj
  fwd_token="$(_spike_rand 24)"; decoy="spkdecoy_$(_spike_rand 30)"; rsess="$(_spike_rand 24)"; rinj="$(_spike_rand 24)"
  for v in "$fwd_token" "$decoy" "$rsess" "$rinj"; do mask "$v"; done
  _spike_secret_file "$r/secrets/forwarder.token" "$fwd_token"
  # No trailing newline: iron-proxy's `type: file` secret source uses the bytes verbatim, and a newline makes the
  # injected Authorization value invalid (measured 2026-11-10: "invalid header field value").
  ( umask 077 && printf '%s' "$decoy" > "$r/secrets/decoy.token" ) || harness_fail SESSION_PREP "write decoy.token"
  _spike_secret_file "$r/secrets/router-session.cred" "session:$rsess"
  _spike_secret_file "$r/secrets/router-injector.cred" "router:$rinj"
  _spike_secret_file "$h/router.pw" "$rinj"
  # The squid auth helper's token file: named by the token, holding the workspace id (server/egress-forwarder.ts).
  printf '%s\n' "$ws" > "$SPIKE_SQUID_TOKENS/$fwd_token" && chmod 0644 "$SPIKE_SQUID_TOKENS/$fwd_token" \
    || harness_fail SESSION_PREP "squid token file"
  mint_session_ca "$r/ca" "spike session ca $id" || harness_fail SESSION_PREP "session CA $id"
  mint_leaf "$SPIKE_WORK/hook-client-root" "$r/hookclient/client" "DNS:$conv" clientAuth || harness_fail SESSION_PREP "hook client cert $id"
  # The client cert's CN is the conversation (R25): mint_leaf takes CN from the first SAN.
  mint_leaf "$SPIKE_WORK/hook-server-root" "$h/server" "DNS:localhost" serverAuth || harness_fail SESSION_PREP "hook server cert $id"
  cp "$SPIKE_WORK/hook-server-root/ca.pem" "$r/hookclient/server-root.pem" \
    && cp "$SPIKE_WORK/upstream-root/ca.pem" "$r/upstream-root.pem" \
    && cat "$SPIKE_WORK/system-bundle.pem" "$SPIKE_WORK/upstream-root/ca.pem" "$r/ca/ca.pem" > "$p/bundle.pem" \
    || harness_fail SESSION_PREP "copy roots for $id"
  # (bundle.pem: system roots + the test upstream root standing in for a public CA + this session's CA; TR3.)
  cat > "$r/session.env" <<ENV
SESSION_ID=$id
WORKSPACE_ID=$ws
GW_HOST=$SPIKE_SQUID_IP
TUNNEL_PORT=$((18080 + idx * 10))
HTTP_PORT=$((18081 + idx * 10))
HTTPS_PORT=$((18082 + idx * 10))
METRICS_PORT=$((18083 + idx * 10))
ENV
  printf -v "SPIKE_SESS_${id}_WS" '%s' "$ws"
  printf -v "SPIKE_SESS_${id}_CONV" '%s' "$conv"
  printf -v "SPIKE_SESS_${id}_TUNNEL" '%s' "$((18080 + idx * 10))"
}

# spike_start_hook <hook config json path on host>. Runs with --network host (R21) as the app uid; mounts the shared
# run dir (sockets) and its private dir (service-role key, HMAC key, server keys, router passwords).
spike_start_hook() { # [config file name under hookpriv, default hook.json]
  SPIKE_HOOK_CTR="${SPIKE_RUN_ID}-hook"
  _spike_docker_run "$SPIKE_HOOK_CTR" --network host -u "$SPIKE_APP_UID" \
    -v "$WP:/app:ro" -v "$SPIKE_WORK/run:/run/spike" -v "$SPIKE_WORK/hookpriv:/run/spike-hook:ro" \
    "$SPIKE_IMG" node /app/test/infra/egress-injector-spike/approval-hook.mjs "/run/spike-hook/${1:-hook.json}" \
    || harness_fail HOOK_START "docker run: $(head -c 300 "$SPIKE_WORK/docker-run-$SPIKE_HOOK_CTR.err")"
  spike_wait_log "$SPIKE_HOOK_CTR" approval-hook-listening 20 \
    || harness_fail HOOK_START "hook did not listen: $(docker logs "$SPIKE_HOOK_CTR" 2>&1 | tail -3 | tr '\n' ' ' | head -c 300)"
}

# spike_session_up <id>: start the session's chain inside the app container and wait for it.
spike_session_up() {
  local s="/run/spike/$1" i
  docker exec -d -u "$SPIKE_APP_UID" "$SPIKE_APP_CTR" bash /app/test/infra/egress-injector-spike/probes/session-up.sh "$s" \
    || harness_fail SESSION_UP "docker exec for $1 failed"
  for ((i = 0; i < 200; i++)); do
    [[ -e "$SPIKE_WORK/run/$1/state/ready" ]] && return 0
    [[ -e "$SPIKE_WORK/run/$1/state/failed" ]] && harness_fail SESSION_UP "$1: $(cat "$SPIKE_WORK/run/$1/state/failed")"
    sleep 0.1
  done
  harness_fail SESSION_UP "$1 not ready in 20 s"
}
