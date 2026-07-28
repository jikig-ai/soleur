#!/usr/bin/env bash
# Copy the bind-mounted app tree into the container build dir, minus what the very
# next command discards (#7007).
#
# Use:   bash /src/scripts/lib/in-image-copy-src.sh /src /build
# Called from BOTH in-image verifiers: sandbox-canary-verify-in-image.sh and
# plugin-root-propagation-verify-in-image.sh.
# Pinned by: apps/web-platform/scripts/lib/in-image-copy-src.test.sh (auto-discovered
# by the apps/web-platform/scripts/lib/*.test.sh glob in scripts/test-all.sh).
#
# EXECUTED, not sourced -- a deliberate divergence from the sibling library
# (supabase-ref-resolver.sh, which is sourced, defines one function, returns rather
# than exits, and sets no shell options at file scope). Sourcing this would leak
# `set -o pipefail` into the canary caller, whose next lines include a
# `curl -fsSL https://bun.sh/install | bash` pipeline. Scoping pipefail to this file
# is the entire reason the exit guard below can be trusted; do not harmonise it with
# the sibling by converting it to a sourced function.
#
# WHY the exclusions: /src is a ro bind of apps/web-platform, so on any warm working
# tree it carries node_modules (~2 GB) and the gitignored infra/.terraform provider
# cache (~250 MB). The caller runs `npm ci` immediately after, which rebuilds
# node_modules from scratch, and nothing in either probe reads .terraform. Measured
# in the pinned node:22-slim image against a warm tree: 22.96 s / 2.3 GB before,
# 0.48 s / 35 MB after.
#
# NOT GLOBIGNORE (the sibling pattern in infra/credential-persist-home-guard.test.sh):
# that filters glob EXPANSION, so it can only exclude a TOP-LEVEL entry.
# infra/.terraform is one level down, cp -r recurses into infra on its own, and the
# exclusion silently does nothing. Measured on a fixture, not assumed.
#
# ANCHORING -- read this before editing either pattern. GNU tar --exclude defaults to
# --no-anchored and matches at ANY /-delimited component boundary; a slash in the
# pattern does NOT anchor it (measured: --exclude=infra/.terraform also excluded a
# planted deep/a/infra/.terraform). So:
#   --exclude=.terraform      matches that component at any depth -- intended. Covers
#                             infra/ and infra/sentry/ (a second terraform root, not
#                             yet initialised). Never matches .terraform.lock.hcl,
#                             because the pattern has no wildcard and must match a
#                             whole component.
#   --exclude=./node_modules  is root-only ONLY because a literal ./ component exists
#                             just once, at the archive root -- which holds solely
#                             because the archive is created with `.` as its member
#                             root below. Change that `.` to `*` or to "$SRC" and the
#                             exclusion silently stops matching: the copy still
#                             succeeds, just full-fat, with no error anywhere. CI
#                             cannot see that regression (a cold checkout has no
#                             node_modules); the test suite is the only detector.
#
# --no-same-owner is load-bearing, not defensive: GNU tar as root defaults to
# --same-owner and would restore the HOST uid/gid off the ro bind mount, so DEST would
# stop being root-owned the way cp -r left it. Ownership parity only -- tar also
# restores exact modes and mtimes where cp -r applied the umask and stamped fresh ones
# (measured as root, umask 022: cp -r -> 644 + mtime now; tar -> 664 + mtime
# preserved). Accepted: strictly more faithful to the source, and provably outside the
# canary fixture projection surface (see ADR-079 Fidelity note).
#
# pipefail is set HERE rather than in the callers precisely so it has no blast radius
# on the canary caller's bun-install pipeline. It is load-bearing and measured: on an
# unreadable member the pipeline gives PIPESTATUS=(2 0) -- WITH pipefail the guard
# fires (exit 2), WITHOUT it the shell exits 0 and DEST is silently truncated while
# npm ci carries on against a partial tree.
set -euo pipefail

SRC="${1:?usage: in-image-copy-src.sh SRC DEST}"
DEST="${2:?usage: in-image-copy-src.sh SRC DEST}"

mkdir -p "$DEST"
if ! tar -C "$SRC" --exclude=./node_modules --exclude=.terraform -cf - . \
  | tar -C "$DEST" --no-same-owner -xf -; then
  echo "FATAL: in-image copy failed ($SRC -> $DEST) - refusing to verify a truncated tree" >&2
  exit 1
fi
