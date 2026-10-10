#!/usr/bin/env bash
# run-in-pid-namespace.sh [--] <command> [args...]
#
# Runs <command> as PID 1 of a fresh PID namespace (own /proc), via
#   unshare -Urpf --kill-child --mount-proc
# and REFUSES (rc 125, no unsandboxed fallback) when it cannot arrange that. Use it to run a
# MUTANT of any helper that signals processes: a helper that walks $PPID upward and signals the
# outermost ancestor whose argv matches is bounded only by its own match predicate, so a mutant
# of that predicate (-v, a dropped pattern, a catch-all) walks to the top of the user's session
# and ends it. Inside the namespace the command has no ancestor at all, so such a walk stops at
# the command itself. The incident this exists for: see
# knowledge-base/project/learnings/test-failures/2026-10-09-an-inverted-match-mutant-of-an-ancestor-walking-helper-ended-the-desktop-session-four-times.md
#
# Exit codes: the command's own code on success; 125 = refused (the command never started; the
# FIRST stderr line is "RUN_IN_PID_NAMESPACE_REFUSED reason=<missing-unshare|userns-unavailable|
# not-isolating> ..."; a wrapped command that itself exits 125 prints no such line, so a caller
# tells them apart by the marker, not the code); 2 = usage error.
#
# Trust anchor: PATH. The probe and the run use one absolute unshare, but sh, awk and the other tools
# resolve through the caller's PATH, so a caller who controls PATH controls them.
#
# What a PID namespace does NOT bound: filesystem writes (the mount namespace is created for
# /proc only), network, IPC, abstract unix sockets, the D-Bus session bus, path-based sockets under XDG_RUNTIME_DIR (hyprctl,
# tmux, sway/i3 IPC) and the session manager (loginctl terminate-session still reaches the host). The caller is mapped to uid 0
# inside, so id -u and root-guard branches differ. The command is PID 1 there, so a signal it
# sends ITSELF is ignored: bound a run with `timeout -k <grace> <secs> <this script> ...`, never
# a plain `timeout`. A backgrounded child does not outlive the command (--kill-child).
set -u

readonly MARKER=RUN_IN_PID_NAMESPACE_REFUSED

[[ "${1:-}" == "--" ]] && shift
if [[ $# -eq 0 ]]; then
  printf 'usage: %s [--] <command> [args...]\n' "${0##*/}" >&2
  exit 2
fi
# `exec` reads a leading dash as an option, and `exec --` is not portable (dash, the sh of Debian and
# Ubuntu, rejects it), so a command word that begins with a dash is refused here, before anything
# starts. A file whose name begins with a dash runs when given as a path (./-name).
if [[ "$1" == -* ]]; then
  printf '%s: the command must not begin with "-" (give a path such as ./%s)\n' "${0##*/}" "$1" >&2
  exit 2
fi

# The isolation property, written ONCE and used by the probe and by the run: this shell is PID 1
# and /proc is the namespace's own (NSpid has exactly one field; a wrapper that drops
# --mount-proc keeps $$ at 1 but shows the host's process list, so $$ alone is not enough).
# shellcheck disable=SC2016  # the single quotes are intentional: this text runs inside the namespace
CHECK='[ "$$" = 1 ] && [ "$(awk "/^NSpid:/{print NF-1}" /proc/self/status 2>/dev/null)" = 1 ]'

refuse() { # reason cause remedy
  {
    printf '%s reason=%s\n' "$MARKER" "$1"
    printf 'cause: %s\n' "$2"
    printf 'remedy: %s\n' "$3"
    printf 'no unsandboxed fallback: run the mutant on a host that allows user namespaces, or do not run it.\n'
  } >&2
  exit 125
}

# Resolve unshare ONCE to an absolute path: `type -P` consults PATH only, so a shell function or alias
# named unshare cannot decide the probe, a relative PATH entry is refused, and the probe and the run use
# the same binary.
u="$(type -P unshare 2>/dev/null || true)"
if [[ -z "$u" || "$u" != /* ]]; then
  refuse missing-unshare "unshare (util-linux) was not found on PATH as an absolute path" \
    "use a Linux host with util-linux; stock macOS has no unshare, so use a Linux VM"
fi

probe_err="$("$u" -Urpf --kill-child --mount-proc -- sh -c "$CHECK || exit 97" 2>&1 >/dev/null)"
probe_rc=$?
if [[ "$probe_rc" -ne 0 ]]; then
  # One line, control characters stripped, cut short: the text comes from whatever unshare is.
  first="$(printf '%s\n' "$probe_err" | head -n 1 | tr -d '\000-\037\177' | cut -c1-200)"
  if [[ "$probe_rc" -eq 97 ]]; then
    refuse not-isolating "the unshare on PATH ran the command without a fresh PID namespace and its own /proc (or awk or /proc/self/status was unusable inside it)" \
      "check which unshare resolves first on PATH and that it is util-linux unshare"
  fi
  refuse userns-unavailable "unshare failed (rc $probe_rc): ${first:-no message}" \
    "run the mutant on a disposable VM or container that allows unprivileged user namespaces; enabling them on a workstation (sysctl kernel.unprivileged_userns_clone, kernel.apparmor_restrict_unprivileged_userns, user.max_user_namespaces) or allowing unshare in a container seccomp profile weakens that host, so do it only on a throwaway host. On a restricted CI runner every seat on a signalling helper refuses until the runner relaxes the sysctl"
fi

# The same check runs again inside the namespace right before the command (it keeps the property
# true at the instant of the exec even if the probe and this run disagreed). A plain `exec` (never
# `exec --`, which dash rejects) leaves the command as PID 1 with no ancestor; a command word that
# begins with a dash was refused above, so exec cannot read it as an option.
RUN="$CHECK || { printf '%s\\n' '$MARKER reason=not-isolating (re-check inside the namespace failed)' >&2; exit 125; }; exec \"\$@\""
exec "$u" -Urpf --kill-child --mount-proc -- sh -c "$RUN" sh "$@"
