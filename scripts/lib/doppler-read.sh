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
# Modes (DOPPLER_TOKEN comes from the caller's env, as before):
#   hash <project> <config> <name>   sha256 of the value on stdout; the key
#                                  exists only on the pipe into sha256sum.
#   tf   <terraform args...>         terraform under the prd_terraform tf-var
#                                  injection (the caller's env wins under
#                                  --preserve-env).
#   bs   <command> [args...]         run <command> with BETTERSTACK_QUERY_{HOST,
#                                  USERNAME,PASSWORD} injected from soleur/
#                                  prd_terraform via three targeted gets — the
#                                  exact set scripts/betterstack-query.sh and
#                                  its callers need.
set -u
case "${1:-}" in
  hash)
    shift
    doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null | sha256sum | cut -c1-64
    ;;
  tf)
    shift
    exec doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform "$@"
    ;;
  bs)
    shift
    for _n in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
      [ -n "${!_n:+x}" ] || export "$_n=$(doppler secrets get "$_n" -p soleur -c prd_terraform --plain 2>/dev/null || true)"
    done
    exec "$@"
    ;;
  *)
    printf 'doppler-read.sh: unknown mode %s\n' "${1:-<none>}" >&2
    exit 2
    ;;
esac
