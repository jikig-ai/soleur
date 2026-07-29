#!/usr/bin/env bash
# Copy the bind-mounted app tree into the container build dir, minus what the very
# next command discards (#7007).
#
# Use:   bash <this file> SRC DEST      (call sites pass /src /build)
# Called from BOTH in-image verifiers: sandbox-canary-verify-in-image.sh and
# plugin-root-propagation-verify-in-image.sh.
# Pinned by: apps/web-platform/scripts/lib/in-image-copy-src.test.sh (auto-discovered
# by the apps/web-platform/scripts/lib/*.test.sh glob in scripts/test-all.sh).
#
# EXECUTED, not sourced -- a deliberate divergence from the sibling in this directory
# (supabase-ref-resolver.sh, which is sourced and defines a function). Sourcing this
# would leak `set -o pipefail` into the canary caller, whose next lines include a
# `curl -fsSL https://bun.sh/install | bash` pipeline. Do not harmonise it.
#
# WHY the exclusions: /src is a ro bind of apps/web-platform, so on any warm working
# tree it carries node_modules (~2 GB) and the gitignored infra/.terraform provider
# cache (~250 MB). The caller runs `npm ci` immediately after, which DELETES any
# pre-existing node_modules before installing, so copying it in was pure I/O. Nothing
# in either probe reads .terraform, .next or out. All four are already excluded from
# the deploy image's build context by .dockerignore, so filtering them makes /build
# MORE like the deploy image, not less (ADR-079 fidelity). Measured effect is on the
# LOCAL path only -- a cold CI checkout has none of these directories, so in CI this
# saves nothing and is perf-neutral within noise. Figures live in the PR body and
# knowledge-base/project/specs/<branch>/session-state.md, deliberately not here: an
# inline number rots silently and this file has no way to re-derive it.
#
# ANCHORING -- read this before editing any pattern. GNU tar --exclude defaults to
# --no-anchored and matches at ANY /-delimited component boundary; a slash in the
# pattern does NOT anchor it (measured: --exclude=infra/.terraform also excluded a
# planted deep/a/infra/.terraform). So:
#   --exclude=.terraform    matches that component at any depth -- intended. Covers
#                           infra/ and infra/sentry/ (a second terraform root). Never
#                           matches .terraform.lock.hcl: with no wildcard the pattern
#                           must match a WHOLE component.
#   --exclude=./node_modules (and ./.next, ./out) are root-only ONLY because a literal
#                           ./ component exists just once, at the archive root -- which
#                           holds solely because the archive is created with `.` as its
#                           member root below. Change that `.` to `*` or "$SRC" and the
#                           exclusions silently stop matching: the copy still succeeds,
#                           just full-fat, with no error anywhere. CI cannot see that
#                           (a cold checkout has no node_modules); the test suite is
#                           the only detector.
#
# --no-same-owner is load-bearing: GNU tar as root defaults to --same-owner and would
# restore the HOST uid/gid off the ro bind mount, so DEST would stop being root-owned
# the way cp -r left it. NOTE this is proven by the in-image rehearsal recorded in the
# PR body (measured in the pinned digest: root:root with the flag, 1001:1001 without),
# NOT by the test suite -- as non-root tar cannot chown at all, so the hermetic suite
# is structurally unable to pin it. Do not read its green as covering this flag.
#
# Other deltas from `cp -r`, none of which any consumer reads (both probes were
# grepped for statSync/mtime/birthtime/utimes/accessSync/X_OK -- zero hits):
#   - tar restores exact modes and mtimes where cp -r applied the umask and stamped
#     fresh ones; as root it also restores setuid/setgid bits that cp -r (no -p)
#     dropped. None exist in the copied set today.
#   - DEST is merged into, not replaced. `cp -r /src /build` with an EXISTING /build
#     created /build/src instead. Both call sites run in a fresh --rm container where
#     /build cannot pre-exist; a future caller must pass an empty or absent DEST.
set -euo pipefail

SRC="${1:?usage: in-image-copy-src.sh SRC DEST}"
DEST="${2:?usage: in-image-copy-src.sh SRC DEST}"

mkdir -p "$DEST"

# GNU tar OVERLOADS its exit status and the two meanings need opposite handling:
#   2 = ERROR   (unreadable member, truncated archive) -> DEST is incomplete, refuse.
#   1 = WARNING ("file changed as we read it" / "File removed before we read it")
#                -> DEST is COMPLETE; a member may be a torn snapshot.
# Collapsing both into a FATAL is wrong in the direction that matters here. The
# unreadable-member case is UNREACHABLE in production (this runs as root, and root
# reads everything), while the warning case fires on any host write during the copy
# window -- /src is read-only to the CONTAINER, but the host tree stays live, so a
# tsc --watch rewriting tsconfig.tsbuildinfo, an editor autosave, a git checkout, or
# even a file deletion (which bumps the parent directory's mtime) all trigger it.
# `cp -r` tolerated every one silently, so treating them as fatal would turn the
# operator's warm tree -- the only place this optimisation pays -- into a flaky red.
# --warning=no-file-changed does NOT help: measured, it suppresses the message and
# still exits 1. The status is the only discriminator.
#
# pipefail is off for the pipeline so both statuses survive; PIPESTATUS must be
# captured as a WHOLE ARRAY in one assignment, because reading one element is itself
# a simple command that resets it (measured: ${PIPESTATUS[1]} is already unbound on
# the next line).
set +e
set +o pipefail
tar -C "$SRC" \
  --exclude=./node_modules --exclude=./.next --exclude=./out --exclude=.terraform \
  -cf - . | tar -C "$DEST" --no-same-owner -xf -
rc=("${PIPESTATUS[@]}")
set -e
set -o pipefail

if [ "${rc[1]}" -ne 0 ] || [ "${rc[0]}" -ge 2 ]; then
  echo "FATAL: in-image copy failed ($SRC -> $DEST) - refusing to verify a truncated tree" >&2
  exit 1
fi
if [ "${rc[0]}" -eq 1 ]; then
  echo "WARN: $SRC changed during copy (tar status 1); $DEST is complete but a member may be a torn snapshot" >&2
fi
