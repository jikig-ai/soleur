#!/usr/bin/env bash
# Stub vendor world for the operator-script suites (ADR-264). SOURCED by:
#   plugins/soleur/test/operator-agent-runnable.test.sh   (Guard 1)
#   plugins/soleur/test/operator-9321-stages.test.sh
#
# It builds PATH-shimmed `doppler`, `gh`, `curl`, `openssl` and `jq` that
#   - answer from files under $STUB_ROOT (no network, no real vendor, ever),
#   - LOG every call to $STUB_LOG as  <tool>\t<read|mutating>\t<argv>  — argv only,
#     never a value (a secret travels on stdin or in a child's environment),
#   - classify a call as READ only when it is on an explicit allowlist of read verbs and
#     as MUTATING otherwise (default-deny): an unknown verb, a method flag, a body flag
#     (attached forms such as -XPOST, --json and -F included) or an unknown host is
#     mutating and is refused with exit 64. A read-class function that deletes, uploads
#     or posts is therefore seen. Tools the stage world has no business calling
#     (hcloud writes, terraform, ssh, scp, rsync, wget, psql) are shimmed to log+refuse
#     instead of RUNNING FOR REAL on the machine that hosts the guard,
#   - on the FIRST mutating call snapshot the receipt directory listing (how "consume
#     BEFORE the first write" is observable), and on EVERY call record whether
#     SOLEUR_APPROVAL_NONCE is visible in the stub's own environment (how "no child ever
#     inherits the nonce" is observable: the plan phase runs vendor reads BEFORE the
#     gate, and a first-mutating-call snapshot cannot see those).
#   - validate the GitHub App JWT the way GitHub would: Bearer + three base64url
#     segments, alg RS256, iss equal to the App id, exp-iat within 600 s, and a signature
#     derived from the key bytes the openssl stub was handed, so a wrong key, algorithm,
#     issuer or lifetime answers 401 instead of a 200 that ignores the request.
#
# The stubs validate argv the way the vendor would: an unexpected shape exits 64,
# so a script that queries the wrong thing fails instead of reading a fixture that
# answers regardless (the "stub dispatching on $1 only" trap).
#
# Test fixtures here are SYNTHESIZED (cq-test-fixtures-synthesized-only): the PEM
# is not a key and the token values are not tokens.

# The body below is a COPY of the canonical definition in plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh asserts it is byte-equal). Every writing window below calls it
# first, so a bad <root> refuses before any write instead of retargeting it.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

STUB_APP_ID_VALUE="424242"
STUB_PEM_SENTINEL="SENTINEL-APP-PRIVATE-KEY-7d41c9a2e0b35f68"
STUB_TOKEN_SENTINEL="STUBTOKEN-VALUE"

# stub_world_init <root> <state-home>
#   Creates <root>/{bin,stub,state}, writes the shims and the default world, and
#   exports STUB_ROOT / STUB_LOG / STUB_SNAP / XDG_STATE_HOME. Does NOT touch PATH:
#   the caller prepends "$root/bin" for the child it runs.
stub_world_init() {
  local root="$1" real_jq real_openssl
  real_jq="$(command -v jq)"; real_openssl="$(command -v openssl || true)"
  [[ -n "$real_jq" ]] || { printf 'HARNESS: jq is required\n' >&2; return 1; }
  assert_fixture_dir "$root"
  mkdir -p "$root/bin" "$root/stub/doppler/val" "$root/stub/doppler/tokens" "$root/stub/gh" "$root/state" || return 1
  STUB_ROOT="$root/stub"; STUB_LOG="$root/calls.log"; STUB_SNAP="$root/first-mutating-snapshot"
  XDG_STATE_HOME="$root/state"
  export STUB_ROOT STUB_LOG STUB_SNAP XDG_STATE_HOME
  : > "$STUB_LOG"
  rm -f "$STUB_SNAP" "$STUB_SNAP.nonce" "$STUB_LOG.nonce-seen"

  # ---- shared prologue: log + classify + snapshot ----
  cat > "$root/bin/_stub-common.sh" <<'COMMON'
stub_log() { # <tool> <class> <argv...>
  local tool="$1" class="$2"; shift 2
  printf '%s\t%s\t%s\n' "$tool" "$class" "$*" >> "$STUB_LOG"
  # EVERY call records whether the approval nonce is visible in its environment.
  if [[ -n "$(printenv SOLEUR_APPROVAL_NONCE 2>/dev/null || true)" ]]; then echo "$tool" >> "$STUB_LOG.nonce-seen"; fi
  if [[ "$class" == "mutating" && ! -e "$STUB_SNAP" ]]; then
    { ls -A "${XDG_STATE_HOME}/soleur/approvals" 2>/dev/null || true; } > "$STUB_SNAP"
    if [[ -n "$(printenv SOLEUR_APPROVAL_NONCE 2>/dev/null || true)" ]]; then echo present > "$STUB_SNAP.nonce"; else echo absent > "$STUB_SNAP.nonce"; fi
  fi
}
stub_refuse() { printf 'stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
COMMON

  # ---- doppler ----
  assert_fixture_dir "$root"
  cat > "$root/bin/doppler" <<'DOPPLER'
#!/usr/bin/env bash
source "$(dirname "$0")/_stub-common.sh"
V="$STUB_ROOT/doppler/val"; T="$STUB_ROOT/doppler/tokens"
args=("$@"); proj=""; cfg=""; i=0
while (( i < ${#args[@]} )); do
  case "${args[i]}" in
    -p|--project) proj="${args[i+1]:-}"; i=$((i+2)) ;;
    -c|--config) cfg="${args[i+1]:-}"; i=$((i+2)) ;;
    *) i=$((i+1)) ;;
  esac
done
scoped() { [[ -n "${DOPPLER_TOKEN:-}" ]]; }
deny() { printf 'Doppler Error: you do not have access to that project (forbidden)\n' >&2; exit 1; }
case "$1 ${2:-} ${3:-}" in
  "projects get "*)
    stub_log doppler read "$@"
    [[ -e "$STUB_ROOT/doppler/project-$3" ]] && { echo '{}'; exit 0; }
    exit 1 ;;
  "secrets get "*)
    stub_log doppler read "$@"
    name="$3"
    if scoped; then
      [[ "$proj" == "soleur-infra-app" && ( "$name" == "GITHUB_INFRA_APP_ID" || "$name" == "GITHUB_INFRA_APP_PRIVATE_KEY" ) ]] || deny
    fi
    [[ -f "$V/$proj/$name" ]] || exit 1
    cat "$V/$proj/$name"; exit 0 ;;
  "secrets set "*)
    stub_log doppler mutating "$@"
    name="$3"; mkdir -p "$V/$proj"; cat > "$V/$proj/$name"; exit 0 ;;
  "secrets delete "*|"secrets unset "*|"secrets upload "*|"secrets move "*|"secrets substitute "*)
    stub_log doppler mutating "$@"; exit 64 ;;
esac
case "$1 ${2:-}" in
  "secrets download")
    stub_log doppler read "$@"
    scoped || exit 64
    [[ "$proj" == "soleur-infra-app" ]] || deny
    extra=""; [[ -f "$STUB_ROOT/doppler/download-extra" ]] && extra=",\"$(cat "$STUB_ROOT/doppler/download-extra")\":\"x\""
    printf '{"DOPPLER_CONFIG":"prd","DOPPLER_ENVIRONMENT":"prd","DOPPLER_PROJECT":"soleur-infra-app","GITHUB_INFRA_APP_ID":"x","GITHUB_INFRA_APP_PRIVATE_KEY":"x"%s}\n' "$extra"; exit 0 ;;
  "secrets --only-names"|"secrets -p"|"secrets -c")
    stub_log doppler read "$@"; [[ -d "$V/$proj" || -e "$STUB_ROOT/doppler/project-$proj" ]] && exit 0; exit 1 ;;
  "configs tokens")
    case "${3:-}" in
      create)
        stub_log doppler mutating "$@"
        seq_f="$STUB_ROOT/doppler/token-seq"; n=$(( $(cat "$seq_f" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$seq_f"
        mkdir -p "$T"; printf 'slug%s|%s\n' "$n" "$4" >> "$T/$proj"
        printf '%s-%s\n' "STUBTOKEN-VALUE" "$n"; exit 0 ;;
      revoke)
        stub_log doppler mutating "$@"
        [[ -f "$T/$proj" ]] && { grep -v "^${4}|" "$T/$proj" > "$T/$proj.new" || true; mv "$T/$proj.new" "$T/$proj"; }
        exit 0 ;;
      ""|-*)
        stub_log doppler read "$@"
        [[ -f "$STUB_ROOT/doppler/tokens-unreadable" ]] && exit 1
        [[ -f "$T/$proj" ]] || { echo '[]'; exit 0; }
        awk -F'|' 'BEGIN{printf "["} {printf "%s{\"slug\":\"%s\",\"name\":\"%s\"}", (NR>1?",":""), $1, $2} END{print "]"}' "$T/$proj"; exit 0 ;;
    esac ;;
esac
# default-deny: every other verb (configs create|delete|clone|update, projects create|delete,
# run, secrets <anything else>, a flag-first form) is MUTATING and refused.
stub_log doppler mutating "$@"
stub_refuse "$@"
DOPPLER

  # ---- gh ----
  assert_fixture_dir "$root"
  cat > "$root/bin/gh" <<'GH'
#!/usr/bin/env bash
source "$(dirname "$0")/_stub-common.sh"
G="$STUB_ROOT/gh"
if [[ "$1 ${2:-}" == "secret set" ]]; then
  stub_log gh mutating "$@"
  name="$3"; env=""; i=3
  while (( i <= $# )); do [[ "${!i}" == "--env" ]] && { j=$((i+1)); env="${!j}"; }; i=$((i+1)); done
  cat > /dev/null
  [[ -f "$G/secret-set-fails" ]] && exit 1
  mkdir -p "$G"; printf '%s\n' "$name" >> "$G/env-secrets-${env:-REPO}"
  exit 0
fi
if [[ "$1" == "api" ]]; then
  # A `gh api` call is a READ only without a method other than GET and without any body
  # or field flag (-f, -F, --field, --raw-field, --input).
  class=read; i=2
  while (( i <= $# )); do
    a="${!i}"
    case "$a" in
      -X|--method) j=$((i+1)); [[ "${!j:-}" == "GET" ]] || class=mutating ;;
      -XGET|--method=GET) ;;
      -X?*|--method=*|-f|-F|--field|--raw-field|--input|-f?*|-F?*|--field=*|--raw-field=*|--input=*) class=mutating ;;
    esac
    i=$((i+1))
  done
  stub_log gh "$class" "$@"
  [[ "$class" == read ]] || exit 64
  path="$2"; jqf=""; shift 2
  while [[ $# -gt 0 ]]; do case "$1" in --jq) jqf="$2"; shift 2 ;; --paginate) shift ;; *) shift ;; esac; done
  case "$path" in
    repos/*/environments/*/secrets) envn="${path#*environments/}"; envn="${envn%%/*}"; f="$G/env-secrets-${envn}"
      if [[ -f "$f" ]]; then body="$(awk 'BEGIN{printf "{\"secrets\":["} {printf "%s{\"name\":\"%s\"}", (NR>1?",":""), $1} END{print "]}"}' "$f")"; else body='{"secrets":[]}'; fi ;;
    repos/*/environments/*/deployment-branch-policies) body="$(cat "$G/policies.json" 2>/dev/null || echo '{"branch_policies":[{"name":"main","type":"branch"}]}')" ;;
    repos/*/environments/*) body="$(cat "$G/environment.json" 2>/dev/null || echo '{"deployment_branch_policy":{"custom_branch_policies":true}}')" ;;
    repos/*/actions/secrets) body="$(cat "$G/repo-secrets.json" 2>/dev/null || echo '{"secrets":[]}')" ;;
    orgs/*/actions/secrets) [[ -f "$G/org-unreadable" ]] && exit 1; body="$(cat "$G/org-secrets.json" 2>/dev/null || echo '{"secrets":[]}')" ;;
    *) stub_refuse "$@" ;;
  esac
  if [[ -n "$jqf" ]]; then printf '%s' "$body" | "$STUB_REAL_JQ" -r "$jqf"; else printf '%s\n' "$body"; fi
  exit 0
fi
case "$1 ${2:-}" in
  "auth status"|"secret list"|"variable list"|"repo view"|"pr view"|"pr list"|"issue view"|"issue list")
    stub_log gh read "$@"; exit 0 ;;
esac
# default-deny: secret delete, variable set|delete, workflow run, pr merge, release create,
# repo edit ... are all MUTATING and refused.
stub_log gh mutating "$@"
stub_refuse "$@"
GH

  # ---- curl ----
  cat > "$root/bin/curl" <<'CURL'
#!/usr/bin/env bash
source "$(dirname "$0")/_stub-common.sh"
class=read; out=""; url=""; i=1
while (( i <= $# )); do
  a="${!i}"
  # Any method, body or upload flag — attached short forms (-XPOST, -d@x, -Ffile=@x) and
  # --json included — makes the call mutating.
  case "$a" in
    -X|--request|-d|--data|--data-*|-T|--upload-file|-F|--form|--form-*|--json|--post301|--post302|--post303) class=mutating ;;
    -X?*|-d?*|-T?*|-F?*|--request=*|--data=*|--data-*=*|--upload-file=*|--form=*|--json=*) class=mutating ;;
  esac
  case "$a" in -o) j=$((i+1)); out="${!j}" ;; https://*) url="$a" ;; esac
  i=$((i+1))
done
[[ "$url" == "https://api.github.com/app" ]] || class=mutating
stub_log curl "$class" "$@"
[[ "$class" == read ]] || exit 64
[[ "$url" == "https://api.github.com/app" ]] || stub_refuse "$@"
# The Authorization header arrives on stdin (-H @-): read it, never log it.
hdr="$(cat)"
b64d() { local s="$1"; s="${s//-/+}"; s="${s//_//}"; while (( ${#s} % 4 )); do s="${s}="; done; printf '%s' "$s" | base64 -d 2>/dev/null; }
validate_jwt() { # 0 only for a JWT GitHub would accept for the stub App
  local auth jwt h p sig_b want_id now iat exp want_hash
  auth="$(grep -i '^Authorization:' <<<"$hdr" | head -n1)"
  [[ "$auth" == "Authorization: Bearer "* ]] || return 1
  jwt="${auth#Authorization: Bearer }"
  [[ "$jwt" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] || return 1
  h="$(b64d "${jwt%%.*}")"; p="${jwt#*.}"; sig_b="${p#*.}"; p="$(b64d "${p%%.*}")"
  [[ "$("$STUB_REAL_JQ" -r '.alg' <<<"$h" 2>/dev/null)" == "RS256" ]] || return 1
  want_id="$(cat "$STUB_ROOT/app-id" 2>/dev/null || echo 424242)"
  [[ "$("$STUB_REAL_JQ" -r '.iss | tostring' <<<"$p" 2>/dev/null)" == "$want_id" ]] || return 1
  iat="$("$STUB_REAL_JQ" -r '.iat' <<<"$p" 2>/dev/null)"; exp="$("$STUB_REAL_JQ" -r '.exp' <<<"$p" 2>/dev/null)"
  [[ "$iat" =~ ^[0-9]+$ && "$exp" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  (( exp - iat <= 600 && exp > now && iat <= now )) || return 1
  want_hash="$(cat "$STUB_ROOT/app-key-hash" 2>/dev/null || true)"
  [[ -n "$want_hash" ]] || return 1
  [[ "$(b64d "$sig_b")" == "STUBSIG:${want_hash}" ]] || return 1
}
if [[ -f "$STUB_ROOT/app-code" ]]; then code="$(cat "$STUB_ROOT/app-code")"; elif validate_jwt; then code=200; else code=401; fi
if [[ "$code" == 200 ]]; then
  [[ -z "$out" ]] || printf '{"slug":"%s","id":%s}\n' "$(cat "$STUB_ROOT/app-slug" 2>/dev/null || echo soleur-infra)" "$(cat "$STUB_ROOT/app-id" 2>/dev/null || echo 424242)" > "$out"
else
  [[ -z "$out" ]] || printf '{"message":"Bad credentials"}\n' > "$out"
fi
printf '%s' "$code"
CURL

  # ---- openssl / jq ----
  assert_fixture_dir "$root"
  cat > "$root/bin/openssl" <<OPENSSL
#!/usr/bin/env bash
source "\$(dirname "\$0")/_stub-common.sh"
stub_log openssl read "\$@"
case "\$1" in
  dgst)
    # The signature is DERIVED FROM THE KEY BYTES handed to -sign, so a wrong key yields a
    # signature the curl stub's App does not know.
    key=""; i=1
    while (( i <= \$# )); do [[ "\${!i}" == "-sign" ]] && { j=\$((i+1)); key="\${!j}"; }; i=\$((i+1)); done
    [[ -n "\$key" ]] || exit 64
    cat > /dev/null
    printf 'STUBSIG:%s' "\$(sha256sum < "\$key" | cut -d' ' -f1)"; exit 0 ;;
  base64) base64 | tr -d '\n'; exit 0 ;;
esac
exec ${real_openssl:-/usr/bin/openssl} "\$@"
OPENSSL
  cat > "$root/bin/jq" <<JQ
#!/usr/bin/env bash
source "\$(dirname "\$0")/_stub-common.sh"
stub_log jq read "\$@"
exec "$real_jq" "\$@"
JQ
  # Tools a staged script has no business calling: log + refuse, never run for real.
  assert_fixture_dir "$root"
  local t
  for t in terraform ssh scp rsync wget psql; do
    printf '#!/usr/bin/env bash\nsource "$(dirname "$0")/_stub-common.sh"\nstub_log %s mutating "$@"\nstub_refuse "$@"\n' "$t" > "$root/bin/$t"
  done
  cat > "$root/bin/hcloud" <<'HCLOUD'
#!/usr/bin/env bash
source "$(dirname "$0")/_stub-common.sh"
for a in "$@"; do case "$a" in list|describe) stub_log hcloud read "$@"; echo '[]'; exit 0 ;; esac; done
stub_log hcloud mutating "$@"
stub_refuse "$@"
HCLOUD
  chmod +x "$root"/bin/*
  STUB_REAL_JQ="$real_jq"; export STUB_REAL_JQ
  stub_world_default
}

# stub_world_default — the world the #9321 script expects BEFORE its first stage:
# both Terraform-created projects exist, the source holds the two App values, the
# destination is empty, no tokens, no environment secret.
stub_world_default() {
  assert_fixture_dir "$STUB_ROOT"
  mkdir -p "$STUB_ROOT/doppler/val/soleur-infra-privileged" "$STUB_ROOT/doppler/val/soleur-infra-app"
  : > "$STUB_ROOT/doppler/project-soleur-infra-app"; : > "$STUB_ROOT/doppler/project-soleur-infra-privileged"
  printf '%s\n' "$STUB_APP_ID_VALUE" > "$STUB_ROOT/doppler/val/soleur-infra-privileged/GITHUB_INFRA_APP_ID"
  printf '%s\n' "$STUB_PEM_SENTINEL" > "$STUB_ROOT/doppler/val/soleur-infra-privileged/GITHUB_INFRA_APP_PRIVATE_KEY"
  rm -f "$STUB_ROOT"/doppler/val/soleur-infra-app/* "$STUB_ROOT"/doppler/tokens/* "$STUB_ROOT"/gh/env-secrets-* "$STUB_ROOT/doppler/token-seq" "$STUB_ROOT/app-code" "$STUB_ROOT/doppler/download-extra" "$STUB_ROOT/gh/secret-set-fails" "$STUB_ROOT/gh/org-unreadable" "$STUB_ROOT/gh/repo-secrets.json" "$STUB_ROOT/gh/org-secrets.json" "$STUB_ROOT/doppler/tokens-unreadable"
  assert_fixture_dir "$STUB_LOG"
  assert_fixture_dir "$STUB_SNAP"
  # The stub App knows the hash of the real key's bytes (the value, a trailing newline, as the
  # script hands it to `openssl dgst -sign`).
  printf '%s\n' "$STUB_PEM_SENTINEL" | sha256sum | cut -d' ' -f1 > "$STUB_ROOT/app-key-hash"
  rm -f "$STUB_ROOT/app-id" "$STUB_ROOT/app-slug"
  : > "$STUB_LOG"; rm -f "$STUB_SNAP" "$STUB_SNAP.nonce" "$STUB_LOG.nonce-seen"
}

# stub_nonce_exposures — how many stub calls (of any class) saw SOLEUR_APPROVAL_NONCE in
# their environment. Zero means no child process of the script ever inherited the nonce.
stub_nonce_exposures() { { cat "$STUB_LOG.nonce-seen" 2>/dev/null || true; } | grep -c . || true; }

# stub_calls <class> — the number of logged calls of that class (read|mutating).
stub_calls() { awk -F'\t' -v c="$1" '$2 == c' "$STUB_LOG" | grep -c . || true; }

# stub_env — the environment a child needs to run against the stub world.
# Usage:  env "$(stub_env_args)" ...  — printed as KEY=VALUE words.
stub_env_args() { printf 'PATH=%s/bin:%s STUB_ROOT=%s STUB_LOG=%s STUB_SNAP=%s STUB_REAL_JQ=%s XDG_STATE_HOME=%s' "${STUB_ROOT%/stub}" "$PATH" "$STUB_ROOT" "$STUB_LOG" "$STUB_SNAP" "$STUB_REAL_JQ" "$XDG_STATE_HOME"; }
