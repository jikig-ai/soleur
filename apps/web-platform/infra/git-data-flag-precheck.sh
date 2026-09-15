#!/usr/bin/env bash
#
# git-data flag precheck — fail-closed read of GIT_DATA_STORE_ENABLED (#8189 D-3, blocker 1).
#
# Runs as its OWN step of .github/workflows/git-data-cutover.yml, before the SSH bridge and
# before the git-data root key is fetched. It is the only step bound to DOPPLER_TOKEN_PRD (as
# DOPPLER_TOKEN), so the `prd` read token never reaches a process that handles host bytes.
#
# WHY IT EXISTS. The deleted `read_flag` ran `doppler secrets get ... || echo ""` under a token
# scoped to prd_terraform: the scope error became "", and "" read as "flag unset". A read that
# cannot tell "absent" from "could not read" has to stop the run instead.
#
# MEASURED DOPPLER CLI SEMANTICS (v3.75.3, 2026-09-15):
#   doppler secrets get <absent> --plain --no-exit-on-missing-secret -p soleur -c <cfg>
#     -> exit 0, empty stdout
#   the same call WITHOUT --no-exit-on-missing-secret
#     -> exit 1 ("Could not find requested secret")
#   a nonexistent (or unauthorized) config, even WITH the flag
#     -> exit 1
# So with the flag, exit 0 + empty stdout means "absent", and every non-zero exit is a read
# failure (wrong scope, revoked token, network) — never "unset".
#
# VERDICTS (the only output; the flag value itself is never printed):
#   non-zero rc        -> verdict=flag_read_failed rc=<n>   exit 5
#   exactly `true`     -> verdict=flag_already_true         exit 5
#   empty              -> flag=unset                         exit 0
#   any other value    -> flag=off                           exit 0
# `true` is compared exactly (no case folding, no trimming): the app enables the store only on
# process.env.GIT_DATA_STORE_ENABLED === "true" (apps/web-platform/server/workspace-resolver.ts).
set -euo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

rc=0
flag="$(doppler secrets get GIT_DATA_STORE_ENABLED --plain --no-exit-on-missing-secret -p soleur -c prd 2>/dev/null)" || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "[git-data-flag-precheck] verdict=flag_read_failed rc=${rc}"
  echo "::error title=git-data-flag-precheck::verdict=flag_read_failed rc=${rc}"
  exit 5
fi
if [ "$flag" = true ]; then
  echo "[git-data-flag-precheck] verdict=flag_already_true"
  echo "::error title=git-data-flag-precheck::verdict=flag_already_true"
  exit 5
fi
if [ -z "$flag" ]; then
  echo "flag=unset"
else
  echo "flag=off"
fi
exit 0
