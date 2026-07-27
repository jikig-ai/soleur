#!/usr/bin/env bash
# Resolve a DISK-BACKED scratch root for bulk temporary writes.
#
# WHY
# ---
# /tmp on this workstation is a RAM-backed tmpfs with a fixed ceiling. That is fine for
# the small fixtures most suites create, and wrong for the handful of call sites that
# copy a repo and run `npm install` — a single such run measured 2.3 GB against a 4 GiB
# mount. When that mount fills, tool output stops being writable and interactive sessions
# wedge; `du` itself cannot write its output on a full tmpfs.
#
# Worse, tmpfs pressure defeats cleanup: a process SIGKILLed because the mount filled
# never runs its EXIT trap, so the very condition that causes the failure also orphans
# the largest artifacts. A trap cannot save you here — the fix is to not put multi-GB
# writes on a RAM disk in the first place.
#
# So: bulk writers source this and allocate under a disk-backed root instead, where a
# leak costs disk (hundreds of GB) rather than wedging the machine. Small-fixture callers
# should keep using plain `mktemp` — tmpfs is faster and the volume is irrelevant.
#
# USAGE
# -----
#   source "$(git rev-parse --show-toplevel)/scripts/lib/scratch-root.sh"
#   root=$(soleur_scratch_root) || exit 1      # resolve (creates it if needed)
#   work=$(mktemp -d "$root/mytask.XXXXXXXX")
#   trap 'rm -rf -- "$work"' EXIT INT TERM     # the CALLER still owns cleanup
#
# This module deliberately does NOT install a trap or export TMPDIR. Both are the
# caller's decision: exporting TMPDIR redirects every child process, which is correct for
# a test harness and wrong for a script that shells out to tools with their own
# expectations. Ownership stays where it can be reasoned about.
#
# RELATIONSHIP TO test-contention.sh
# ----------------------------------
# `scripts/lib/test-contention.sh` binds TC_TMPDIR at SOURCE time and declares itself
# observation-only — it measures the tmpfs under contention. This module must not mutate
# it: repointing TC_TMPDIR would silently blind that instrumentation to the mount it
# exists to watch. The two are deliberately separate.

# Guard against double-sourcing.
[[ -n "${_SOLEUR_SCRATCH_ROOT_SOURCED:-}" ]] && return 0
_SOLEUR_SCRATCH_ROOT_SOURCED=1

# soleur_scratch_root
#
# Prints an absolute, existing, writable, disk-backed directory. Returns non-zero and
# explains why on any failure — it NEVER falls back to /tmp silently.
#
# A silent fallback here is the exact failure this whole module exists to prevent: an
# empty return makes `export TMPDIR=""` send allocations straight back to the tmpfs while
# every root-scoped leak check reads clean. Two silent failures compounding into a false
# green (cq-silent-fallback-must-mirror-to-sentry).
soleur_scratch_root() {
  local base root

  # Explicit override wins, so CI and tests can point this anywhere.
  if [[ -n "${SOLEUR_SCRATCH_ROOT:-}" ]]; then
    root="$SOLEUR_SCRATCH_ROOT"
  else
    base="${XDG_CACHE_HOME:-${HOME:-}/.cache}"
    if [[ -z "${HOME:-}" && -z "${XDG_CACHE_HOME:-}" ]]; then
      echo "scratch-root: neither HOME nor XDG_CACHE_HOME is set; cannot resolve a disk-backed root" >&2
      return 1
    fi
    root="$base/soleur/tmp"
  fi

  # XDG_CACHE_HOME is only meaningful as an ABSOLUTE path (per the XDG spec, a relative
  # value must be ignored). Honouring a relative one would resolve the root against the
  # caller's CWD — i.e. inside the repo working tree — and a caller's `rm -rf` would then
  # delete tracked files.
  if [[ "$root" != /* ]]; then
    echo "scratch-root: resolved root '$root' is not absolute (check XDG_CACHE_HOME); refusing" >&2
    return 1
  fi

  if ! mkdir -p -- "$root" 2>/dev/null; then
    echo "scratch-root: cannot create '$root' (permissions? read-only filesystem?)" >&2
    return 1
  fi

  # Resolve symlinks before the containment checks below, so a symlinked cache dir cannot
  # smuggle the root somewhere unexpected.
  local resolved
  resolved=$(realpath -e -- "$root" 2>/dev/null) || {
    echo "scratch-root: cannot resolve '$root'" >&2
    return 1
  }

  if [[ ! -d "$resolved" || ! -w "$resolved" ]]; then
    echo "scratch-root: '$resolved' is not a writable directory" >&2
    return 1
  fi

  # Never hand back a root inside the repo. A caller's recursive delete would take
  # tracked files with it. Skipped when the operator set SOLEUR_SCRATCH_ROOT explicitly —
  # that is a deliberate act, and CI legitimately points it at a workspace path.
  if [[ -z "${SOLEUR_SCRATCH_ROOT:-}" ]]; then
    local repo
    if repo=$(git rev-parse --show-toplevel 2>/dev/null); then
      repo=$(realpath -e -- "$repo" 2>/dev/null || printf '%s' "$repo")
      if [[ "$resolved" == "$repo" || "$resolved" == "$repo"/* ]]; then
        echo "scratch-root: resolved root '$resolved' is inside the repo at '$repo'; refusing" >&2
        return 1
      fi
    fi
  fi

  # Warn (do not fail) if the root is itself RAM-backed — the caller asked for disk. This
  # is advisory because a container or CI runner may legitimately have no disk-backed
  # option, and failing there would be worse than proceeding loudly.
  local fstype
  fstype=$(findmnt -no FSTYPE --target "$resolved" 2>/dev/null || true)
  if [[ "$fstype" == "tmpfs" || "$fstype" == "ramfs" ]]; then
    echo "scratch-root: WARNING '$resolved' is $fstype (RAM-backed); bulk writes will still consume RAM" >&2
  fi

  printf '%s' "$resolved"
}
