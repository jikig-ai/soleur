#!/usr/bin/env bash
# Guard 1 — the npm lockfile is the single lockfile of record.
#
# Property (deliberately an EXISTENCE property, not a co-location one):
#   (a) no tracked `bun.lock` / `bun.lockb` exists anywhere in the repository, and
#   (b) no tracked `bunfig.toml` declares an `[install]` section.
#
# Why existence rather than "no directory carries both": bun stays installed as the test
# runner, so a habitual `bun install` silently recreates `bun.lock` and a routine commit
# resurrects the split that made every apps/web-platform Dependabot PR born red (#7084).
# A co-location property also leaves a bun-only directory undecided; this one does not.
# Clause (b) closes the other half — a reintroduced `[install]` block (the
# `minimumReleaseAge` floor lived there) signals `bun install` is a supported path again.
#
# Anti-vacuity: the floor sits on the `package-lock.json` enumeration, NEVER on the
# `bun.lock` enumeration. After this change the latter is legitimately empty, so a floor
# there would be unsatisfiable — and a guard whose success condition is "I found zero of
# the thing I searched for" is indistinguishable from a guard whose search is broken. The
# floor must sit on a set that is non-empty in the PASSING state.
#
# Scanned set is enumerated at run time from `git ls-files` — never a hardcoded directory
# list, so a `bun.lock` in a directory nobody thought of is still caught.
#
# ADR-191. Registered in scripts/test-all.sh via lint-dual-lockfile.test.sh.
set -euo pipefail

# Verified 2026-08-16: root, apps/web-platform,
# plugins/soleur/skills/pencil-setup/scripts, spike.
MIN_PACKAGE_LOCK_DIRS=4

root=$(git rev-parse --show-toplevel)
cd "$root"

failures=0
fail() {
  echo "::error::lint-dual-lockfile: $*" >&2
  failures=$((failures + 1))
}

mapfile -t tracked < <(git ls-files)
if [[ ${#tracked[@]} -eq 0 ]]; then
  echo "::error::lint-dual-lockfile: git ls-files returned nothing — enumeration is broken, not clean." >&2
  exit 1
fi

bun_locks=()
bunfigs=()
pkg_lock_dirs=()
for f in "${tracked[@]}"; do
  case "$f" in
    bun.lock | */bun.lock | bun.lockb | */bun.lockb) bun_locks+=("$f") ;;
    bunfig.toml | */bunfig.toml | bunfig.local.toml | */bunfig.local.toml) bunfigs+=("$f") ;;
    package-lock.json | */package-lock.json) pkg_lock_dirs+=("$(dirname "$f")") ;;
  esac
done

# --- Floor: assert the enumeration actually ran, before trusting any zero above. ---
if [[ ${#pkg_lock_dirs[@]} -lt $MIN_PACKAGE_LOCK_DIRS ]]; then
  fail "package-lock.json enumeration found ${#pkg_lock_dirs[@]} director(ies), below the floor of ${MIN_PACKAGE_LOCK_DIRS}. The scan is broken — a zero-violation result from this run means nothing."
fi

# --- Clause (a): no tracked bun lockfile anywhere. ---
if [[ ${#bun_locks[@]} -gt 0 ]]; then
  for f in "${bun_locks[@]}"; do
    fail "tracked bun lockfile: ${f}. npm is the single lockfile of record (ADR-191); delete it and install with 'npm ci --ignore-scripts'. Leaving it re-creates the dual-lockfile split that makes every Dependabot PR born red (#7084)."
  done
fi

# --- Clause (b): no [install] section in any tracked bunfig.toml. ---
for f in ${bunfigs[@]+"${bunfigs[@]}"}; do
  # TOML admits several spellings of the same table, and the previous anchor
  # (`^[[:space:]]*\[install(\]|\.)`) saw only the canonical one. All of these declare
  # install config and all evaded it:
  #   [ install ]              inner whitespace is legal in a table header
  #   ["install"]              quoted table keys are legal
  #   install.registry = "..."  a dotted key is equivalent to the section
  #   install = { registry = ... }   a root-level INLINE TABLE is also a declaration;
  #                                   every anchor above keys on a table HEADER and misses it
  if grep -qE '^[[:space:]]*\[[[:space:]]*"?install"?[[:space:]]*(\]|\.)|^[[:space:]]*install[[:space:]]*\.|^[[:space:]]*install[[:space:]]*=[[:space:]]*\{' "$f"; then
    fail "${f} declares an [install] section. bun is the test runner only (ADR-191) — keep [test], drop [install]. The supply-chain floor now lives in the per-directory .npmrc."
  fi
done

echo "lint-dual-lockfile: scanned ${#tracked[@]} tracked files; ${#pkg_lock_dirs[@]} package-lock.json director(ies) (floor ${MIN_PACKAGE_LOCK_DIRS}); ${#bunfigs[@]} bunfig.toml; ${#bun_locks[@]} bun lockfile(s)."

if [[ $failures -gt 0 ]]; then
  echo "::error::lint-dual-lockfile: ${failures} violation(s)." >&2
  exit 1
fi
echo "lint-dual-lockfile: OK"
