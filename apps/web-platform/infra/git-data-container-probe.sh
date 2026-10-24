#!/bin/sh
#
# git-data container probe — the body git-data-cutover.sh runs INSIDE the app container (#8211 PR-E).
#
# Sent on stdin to `docker exec -i -u 1001:1001 <container> sh -s` over the web host's SSH session
# (refuse_if_container_unready in git-data-cutover.sh), so it runs as the app's own user, in the app's own
# network namespace, with the app's own environment. That is the point: the flag-on rehearsal (2026-10-24) found two
# faults no host-side or runner-side check could see, because both are properties of the container:
#   1. the worktree root was not writable by uid 1001 (EACCES at mkdir, every session);
#   2. the container's egress to the git-data endpoint was a blackhole, which a host-side ssh does not share.
#
# Two reads, in order, each with its own exit code (digits and fixed words only; nothing the container holds is printed):
#   21  the worktree root is absent, not a directory, or a probe directory cannot be made and removed in it  -> worktree_root_not_writable
#   22  no scratch directory                                                                                 -> probe_failed reason=scratch
#   23  GIT_TRANSPORT_SSH_PRIVATE_KEY, GIT_DATA_SSH_HOST_KEY or GIT_DATA_SSH_HOST is empty here              -> probe_failed reason=transport_env_absent
#   24  the ssh dial did not answer within its ConnectTimeout (timeout / banner timeout)                     -> container_egress_blackhole reason=timeout
#   25  connection refused / no route / network unreachable / reset                                          -> container_egress_blackhole reason=refused
#   26  the endpoint answered and refused the transport key                                                  -> probe_failed reason=auth_refused
#   27  the pinned host key did not verify                                                                   -> probe_failed reason=host_key
#   28  anything else                                                                                        -> probe_failed reason=unclassified
#    0  the transport wrapper answered
#
# The egress read dials the git-data endpoint with the TRANSPORT key and the same pinned options the app uses, asking
# the forced-command wrapper (git-data-transport-wrapper.sh) for a repository that cannot exist. The wrapper rejects an
# absent repo (or a frozen or unverified store) at once with a `remote: git-data transport: ...` line. That line proves
# reachability, the key, the pin AND the wrapper in one dial; a timeout means the egress is a blackhole. The probe asks
# for no real repository, touches no ref, and cannot change the store.
#
# Key handling: the key goes from this process's environment into a 0600 file in a 0700 scratch directory, never into
# argv and never to stdout or stderr; ssh's stderr goes to a file inside that directory, is only pattern-matched, and
# the directory is removed on every exit. stdin is /dev/null for ssh: this script's own stdin is the script text.
#
# Seams (suite only): GDCP_SSH (ssh binary), GDCP_TIMEOUT (outer bound, seconds), GDCP_REPO_ROOT (the wrapper's repo root).
set -u
umask 077

wr="${WORKTREE_ROOT:-/var/lib/soleur/worktrees}"
case "$wr" in
  /*) : ;;
  *) exit 21 ;;
esac

# Read 1: the directory the app writes its trees to, as the user the app runs as.
[ -d "$wr" ] || exit 21
probe_dir="$wr/.cutover-probe.$$"
mkdir "$probe_dir" 2>/dev/null || exit 21
rmdir "$probe_dir" 2>/dev/null || exit 21

# Read 2: the transport, from inside this container.
key="${GIT_TRANSPORT_SSH_PRIVATE_KEY:-}"
pin="${GIT_DATA_SSH_HOST_KEY:-}"
host="${GIT_DATA_SSH_HOST:-}"
if [ -z "$key" ] || [ -z "$pin" ] || [ -z "$host" ]; then exit 23; fi
case "$host" in
  *[!0-9.]*) exit 23 ;;
esac

d="$(mktemp -d)" || exit 22
trap 'rm -rf "$d"' EXIT
printf '%s\n' "$key" > "$d/k" || exit 22
printf 'git-data %s\n' "$pin" > "$d/kh" || exit 22

repo_root="${GDCP_REPO_ROOT:-/mnt/git-data/repositories}"
rc=0
timeout "${GDCP_TIMEOUT:-15}" "${GDCP_SSH:-ssh}" \
  -F /dev/null -i "$d/k" -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes -o HostKeyAlias=git-data -o HostKeyAlgorithms=ssh-ed25519 \
  -o UpdateHostKeys=no -o GlobalKnownHostsFile=/dev/null -o "UserKnownHostsFile=$d/kh" \
  -o BatchMode=yes -o ConnectTimeout=5 \
  "git@$host" "git-upload-pack '$repo_root/cutover-container-probe-absent.git'" \
  </dev/null >/dev/null 2>"$d/err" || rc=$?

if grep -qF 'remote: git-data transport:' "$d/err"; then
  printf 'container_probe ok worktree_root=writable transport=answered\n'
  exit 0
fi
if [ "$rc" -eq 124 ] || grep -qiE 'timed out|timeout' "$d/err"; then exit 24; fi
if grep -qiE 'connection refused|no route to host|network is unreachable|connection reset|connection closed' "$d/err"; then exit 25; fi
if grep -qiF 'permission denied' "$d/err"; then exit 26; fi
if grep -qiE 'host key verification failed|no matching host key|remote host identification' "$d/err"; then exit 27; fi
exit 28
