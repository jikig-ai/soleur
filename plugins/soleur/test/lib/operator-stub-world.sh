#!/usr/bin/env bash
# Stub vendor world for the operator-script suites (ADR-264). SOURCED by:
#   plugins/soleur/test/operator-agent-runnable.test.sh   (Guard 1)
#   plugins/soleur/test/operator-9321-stages.test.sh
#
# It builds PATH-shimmed `doppler`, `gh`, `curl`, `openssl` and `jq` that
#   - answer from files under $STUB_ROOT (no network, no real vendor, ever),
#   - LOG every call to $STUB_LOG as  <tool>\t<read|mutating>\t<argv>  — argv only,
#     never a value (a secret travels on stdin or in a child's environment),
#   - classify a call as mutating by VERB: `doppler secrets set`, `doppler configs
#     tokens create|revoke`, `gh secret set`, and `curl` with -X / -d / --data* /
#     -T / --upload-file,
#   - on the FIRST mutating call snapshot (a) the receipt directory listing and
#     (b) whether SOLEUR_APPROVAL_NONCE is visible in the stub's own environment.
#     That is how "consume BEFORE the first write" and "unset the nonce before any
#     child" are observable from outside the script (a suite that only reads state
#     after the function returns cannot see a reorder).
#
# The stubs validate argv the way the vendor would: an unexpected shape exits 64,
# so a script that queries the wrong thing fails instead of reading a fixture that
# answers regardless (the "stub dispatching on $1 only" trap).
#
# Test fixtures here are SYNTHESIZED (cq-test-fixtures-synthesized-only): the PEM
# is not a key and the token values are not tokens.

STUB_APP_ID_VALUE="424242"
STUB_PEM_SENTINEL="SENTINEL-APP-PRIVATE-KEY-7d41c9a2e0b35f68"
STUB_TOKEN_SENTINEL="SENTINEL-READ-TOKEN-5b8e2f1a90c4d637"

# stub_world_init <root> <state-home>
#   Creates <root>/{bin,stub,state}, writes the shims and the default world, and
#   exports STUB_ROOT / STUB_LOG / STUB_SNAP / XDG_STATE_HOME. Does NOT touch PATH:
#   the caller prepends "$root/bin" for the child it runs.
stub_world_init() {
  local root="$1" real_jq real_openssl
  real_jq="$(command -v jq)"; real_openssl="$(command -v openssl || true)"
  [[ -n "$real_jq" ]] || { printf 'HARNESS: jq is required\n' >&2; return 1; }
  mkdir -p "$root/bin" "$root/stub/doppler/val" "$root/stub/doppler/tokens" "$root/stub/gh" "$root/state" || return 1
  STUB_ROOT="$root/stub"; STUB_LOG="$root/calls.log"; STUB_SNAP="$root/first-mutating-snapshot"
  XDG_STATE_HOME="$root/state"
  export STUB_ROOT STUB_LOG STUB_SNAP XDG_STATE_HOME
  : > "$STUB_LOG"
  rm -f "$STUB_SNAP" "$STUB_SNAP.nonce"

  # ---- shared prologue: log + classify + snapshot ----
  cat > "$root/bin/_stub-common.sh" <<'COMMON'
stub_log() { # <tool> <class> <argv...>
  local tool="$1" class="$2"; shift 2
  printf '%s\t%s\t%s\n' "$tool" "$class" "$*" >> "$STUB_LOG"
  if [[ "$class" == "mutating" && ! -e "$STUB_SNAP" ]]; then
    { ls -A "${XDG_STATE_HOME}/soleur/approvals" 2>/dev/null || true; } > "$STUB_SNAP"
    if [[ -n "$(printenv SOLEUR_APPROVAL_NONCE 2>/dev/null || true)" ]]; then echo present > "$STUB_SNAP.nonce"; else echo absent > "$STUB_SNAP.nonce"; fi
  fi
}
stub_refuse() { printf 'stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
COMMON

  # ---- doppler ----
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
esac
case "$1 ${2:-}" in
  "secrets download")
    stub_log doppler read "$@"
    scoped || exit 64
    [[ "$proj" == "soleur-infra-app" ]] || deny
    printf '{"DOPPLER_CONFIG":"prd","DOPPLER_ENVIRONMENT":"prd","DOPPLER_PROJECT":"soleur-infra-app","GITHUB_INFRA_APP_ID":"x","GITHUB_INFRA_APP_PRIVATE_KEY":"x"}\n'; exit 0 ;;
  "secrets -p"|"secrets "*)
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
      *)
        stub_log doppler read "$@"
        [[ -f "$T/$proj" ]] || { echo '[]'; exit 0; }
        awk -F'|' 'BEGIN{printf "["} {printf "%s{\"slug\":\"%s\",\"name\":\"%s\"}", (NR>1?",":""), $1, $2} END{print "]"}' "$T/$proj"; exit 0 ;;
    esac ;;
esac
stub_refuse "$@"
DOPPLER

  # ---- gh ----
  cat > "$root/bin/gh" <<'GH'
#!/usr/bin/env bash
source "$(dirname "$0")/_stub-common.sh"
G="$STUB_ROOT/gh"
if [[ "$1 ${2:-}" == "secret set" ]]; then
  stub_log gh mutating "$@"
  name="$3"; env=""; i=3
  while (( i <= $# )); do [[ "${!i}" == "--env" ]] && { j=$((i+1)); env="${!j}"; }; i=$((i+1)); done
  cat > /dev/null
  mkdir -p "$G"; printf '%s\n' "$name" >> "$G/env-secrets-${env:-REPO}"
  exit 0
fi
if [[ "$1" == "api" ]]; then
  stub_log gh read "$@"
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
stub_refuse "$@"
GH

  # ---- curl ----
  cat > "$root/bin/curl" <<'CURL'
#!/usr/bin/env bash
source "$(dirname "$0")/_stub-common.sh"
class=read; out=""; url=""; i=1
while (( i <= $# )); do
  a="${!i}"
  case "$a" in
    -X|--request|-d|--data|--data-*|-T|--upload-file) class=mutating ;;
  esac
  case "$a" in -o) j=$((i+1)); out="${!j}" ;; https://*) url="$a" ;; esac
  i=$((i+1))
done
stub_log curl "$class" "$@"
[[ "$url" == "https://api.github.com/app" ]] || stub_refuse "$@"
# The Authorization header arrives on stdin (-H @-): consume it, never log it.
cat > /dev/null
code="$(cat "$STUB_ROOT/app-code" 2>/dev/null || echo 200)"
[[ -z "$out" ]] || printf '{"slug":"%s","id":%s}\n' "$(cat "$STUB_ROOT/app-slug" 2>/dev/null || echo soleur-infra)" "$(cat "$STUB_ROOT/app-id" 2>/dev/null || echo 424242)" > "$out"
printf '%s' "$code"
CURL

  # ---- openssl / jq ----
  cat > "$root/bin/openssl" <<OPENSSL
#!/usr/bin/env bash
source "\$(dirname "\$0")/_stub-common.sh"
stub_log openssl read "\$@"
case "\$1" in
  dgst) printf 'STUBSIG'; exit 0 ;;
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
  chmod +x "$root"/bin/*
  STUB_REAL_JQ="$real_jq"; export STUB_REAL_JQ
  stub_world_default
}

# stub_world_default — the world the #9321 script expects BEFORE its first stage:
# both Terraform-created projects exist, the source holds the two App values, the
# destination is empty, no tokens, no environment secret.
stub_world_default() {
  mkdir -p "$STUB_ROOT/doppler/val/soleur-infra-privileged" "$STUB_ROOT/doppler/val/soleur-infra-app"
  : > "$STUB_ROOT/doppler/project-soleur-infra-app"; : > "$STUB_ROOT/doppler/project-soleur-infra-privileged"
  printf '%s\n' "$STUB_APP_ID_VALUE" > "$STUB_ROOT/doppler/val/soleur-infra-privileged/GITHUB_INFRA_APP_ID"
  printf '%s\n' "$STUB_PEM_SENTINEL" > "$STUB_ROOT/doppler/val/soleur-infra-privileged/GITHUB_INFRA_APP_PRIVATE_KEY"
  rm -f "$STUB_ROOT"/doppler/val/soleur-infra-app/* "$STUB_ROOT"/doppler/tokens/* "$STUB_ROOT"/gh/env-secrets-* "$STUB_ROOT/doppler/token-seq" "$STUB_ROOT/app-code"
  : > "$STUB_LOG"; rm -f "$STUB_SNAP" "$STUB_SNAP.nonce"
}

# stub_calls <class> — the number of logged calls of that class (read|mutating).
stub_calls() { awk -F'\t' -v c="$1" '$2 == c' "$STUB_LOG" | grep -c . || true; }

# stub_env — the environment a child needs to run against the stub world.
# Usage:  env "$(stub_env_args)" ...  — printed as KEY=VALUE words.
stub_env_args() { printf 'PATH=%s/bin:%s STUB_ROOT=%s STUB_LOG=%s STUB_SNAP=%s STUB_REAL_JQ=%s XDG_STATE_HOME=%s' "${STUB_ROOT%/stub}" "$PATH" "$STUB_ROOT" "$STUB_LOG" "$STUB_SNAP" "$STUB_REAL_JQ" "$XDG_STATE_HOME"; }
