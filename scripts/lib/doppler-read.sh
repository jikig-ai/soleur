#!/usr/bin/env bash
# Generic Doppler machinery shared by the credential-consumer scripts (#9294 PR-B, D-2).
#
# A `doppler secrets get` whose name arrives as a variable, and any `doppler run` /
# `secrets download` of a trio-carrying project/config pair, is a counted read
# shape ONLY in a file that names the deploy-channel trio. This sibling names no
# trio member, so its generic reads sit outside the censused surface by
# construction — keep it that way: do not name WEBHOOK_DEPLOY_SECRET or
# CF_ACCESS_CLIENT_* here.
#
# Every mode fails CLOSED: a missing argument, a failed Doppler read, or an empty
# fetched value is a non-zero exit BEFORE the target command runs — a degraded
# read never executes as success (review: code-quality-analyst P1).
#
# Modes (DOPPLER_TOKEN comes from the caller's env, as before):
#   hash <project> <config> <name>   sha256 of the value on stdout; the key
#                                  exists only on the pipe into sha256sum.
#   get  <project> <config> <name>   the value itself on stdout (--plain).
#   tf   <terraform args...>         terraform under the prd_terraform tf-var
#                                  injection (the caller's env wins under
#                                  --preserve-env); cds to the web-platform
#                                  root first, so the lever is spelled
#                                  root-relative like the other modes.
#   tfapply <terraform args...>      the canonical OPERATOR state-writing lever:
#                                  exports the Tier-B AWS state pair, nests the
#                                  infra-privileged loader outside prd_terraform,
#                                  then runs terraform from the web-platform root.
#   bs   <command> [args...]         run <command> with BETTERSTACK_QUERY_{HOST,
#                                  USERNAME,PASSWORD} injected from soleur/
#                                  prd_terraform via targeted gets for the names
#                                  the caller's env does not already carry (the
#                                  exact set scripts/betterstack-query.sh and
#                                  its callers need).
#   run  <project> <config> <command> [args...]
#                                  run <command> with the full <project>/<config>
#                                  secret set in env — the generic bulk-read
#                                  form, for steps whose target needs prd env.
set -u -o pipefail
_mode="${1:-}"
case "$_mode" in
  hash|get)
    [ "$#" -eq 4 ] || { printf 'doppler-read.sh: %s wants <project> <config> <name>\n' "$_mode" >&2; exit 2; }
    ;;
  tf|tfapply)
    [ "$#" -ge 2 ] || { printf 'doppler-read.sh: %s wants <terraform args...>\n' "$_mode" >&2; exit 2; }
    ;;
  bs)
    [ "$#" -ge 2 ] || { printf 'doppler-read.sh: bs wants <command> [args...]\n' >&2; exit 2; }
    ;;
  run)
    [ "$#" -ge 4 ] || { printf 'doppler-read.sh: run wants <project> <config> <command> [args...]\n' >&2; exit 2; }
    ;;
  *)
    printf 'doppler-read.sh: unknown mode %s\n' "${_mode:-<none>}" >&2
    exit 2
    ;;
esac
case "$_mode" in
  hash)
    shift
    _v="$(doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null)" || {
      printf 'doppler-read.sh: hash read failed (project %s config %s)\n' "$1" "$2" >&2; exit 1; }
    [ -n "$_v" ] || {
      printf 'doppler-read.sh: hash read empty (project %s config %s)\n' "$1" "$2" >&2; exit 1; }
    printf '%s' "$_v" | sha256sum | cut -c1-64
    ;;
  get)
    shift
    _v="$(doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null)" || {
      printf 'doppler-read.sh: get read failed (project %s config %s)\n' "$1" "$2" >&2; exit 1; }
    [ -n "$_v" ] || {
      printf 'doppler-read.sh: get read empty (project %s config %s)\n' "$1" "$2" >&2; exit 1; }
    printf '%s\n' "$_v"
    ;;
  tf)
    shift
    # Resolve the lib dir ABSOLUTE before the cd — $0 is relative to the caller's cwd.
    _libd="$(cd "$(dirname "$0")" && pwd)"
    cd "$_libd/../../apps/web-platform/infra" || {
      printf 'doppler-read.sh: web-platform infra root is missing\n' >&2; exit 1; }
    # Pin the canonical app-domain base BEFORE the bulk injection: prd_terraform is a
    # branch-writable config, and under --name-transformer tf-var a planted APP_DOMAIN_BASE
    # there would arrive as TF_VAR_app_domain_base and redirect the credentialed webhook
    # traffic terraform's push-infra-config hook sends. --preserve-env means this exported
    # outer value wins over any injected one; the value itself comes from committed
    # variables.tf via the fail-closed derivation, never from a runtime store
    # (security-sentinel P1, #13006 review). An unused-by-this-root TF_VAR is inert.
    TF_VAR_app_domain_base="$(bash "$_libd/../derive-app-domain-base.sh")" || {
      printf 'doppler-read.sh: app-domain-base derivation failed\n' >&2; exit 1; }
    export TF_VAR_app_domain_base
    exec doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform "$@"
    ;;
  tfapply)
    shift
    # Same cwd/domain pin as tf, then the two pieces the prose form repeatedly
    # dropped: the bare AWS state backend pair and the outer infra-privileged
    # loader. Targeted gets put the AWS values in the process environment only;
    # neither value is ever an argv member.
    _libd="$(cd "$(dirname "$0")" && pwd)"
    cd "$_libd/../../apps/web-platform/infra" || {
      printf 'doppler-read.sh: web-platform infra root is missing\n' >&2; exit 1; }
    TF_VAR_app_domain_base="$(bash "$_libd/../derive-app-domain-base.sh")" || {
      printf 'doppler-read.sh: app-domain-base derivation failed\n' >&2; exit 1; }
    export TF_VAR_app_domain_base
    _aws_id="$(doppler secrets get TF_STATE_AWS_ACCESS_KEY_ID -p soleur-infra-privileged -c prd --plain 2>/dev/null)" || {
      printf 'doppler-read.sh: AWS state key read failed\n' >&2; exit 1; }
    _aws_secret="$(doppler secrets get TF_STATE_AWS_SECRET_ACCESS_KEY -p soleur-infra-privileged -c prd --plain 2>/dev/null)" || {
      printf 'doppler-read.sh: AWS state secret read failed\n' >&2; exit 1; }
    [ -n "$_aws_id" ] && [ -n "$_aws_secret" ] || {
      printf 'doppler-read.sh: AWS state pair read empty\n' >&2; exit 1; }
    AWS_ACCESS_KEY_ID="$_aws_id" AWS_SECRET_ACCESS_KEY="$_aws_secret"       exec doppler run -p soleur-infra-privileged -c prd --name-transformer tf-var --         doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform "$@"
    ;;
  bs)
    shift
    _missing=""
    for _n in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
      [ -n "${!_n:+x}" ] || _missing="$_missing $_n"
    done
    for _n in $_missing; do
      # Targeted single-name --plain gets (the shape the replaced call sites
      # used). A failed read or an empty value is a hard non-zero BEFORE the
      # command runs — never an empty-credential success. Batching the missing
      # names into one multi-name --json get (review: performance-oracle) is
      # deliberately not done here: the multi-name output shape is unverified
      # against a live server and this path is ops-critical cutover machinery.
      _v="$(doppler secrets get "$_n" -p soleur -c prd_terraform --plain 2>/dev/null)" || {
        printf 'doppler-read.sh: bs read failed (soleur/prd_terraform)\n' >&2; exit 1; }
      [ -n "$_v" ] || {
        printf 'doppler-read.sh: bs read empty for a required name\n' >&2; exit 1; }
      export "$_n=$_v"
    done
    exec "$@"
    ;;
  run)
    shift
    _p="$1"; _c="$2"; shift 2
    exec doppler run --preserve-env -p "$_p" -c "$_c" -- "$@"
    ;;
esac
