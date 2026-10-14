#!/usr/bin/env bash
# apex-origin-markers.sh — the GitHub/Fastly origin markers, in ONE place.
#
# WHY THIS FILE EXISTS
#
# Two consumers decide "is the apex still served by GitHub Pages?" from response
# headers: `apex-origin-probe.sh` (the rollback's branch selector) and
# `cutover-verify.sh` CUT2. They carried two different lists — the probe knew
# three markers, CUT2 knew six.
#
# That divergence is dangerous in one specific direction. The probe's
# `SERVING-FROM-CLOUDFLARE-PAGES` arm is RESIDUAL — "200, and no GitHub marker" —
# so a marker the probe does not know reads as Cloudflare. At the T+20 decision
# point that verdict is what routes an operator into reverting PR3, a SECOND
# destroy, on an apex that is already in trouble. A response carrying only
# `x-proxy-cache` (measured present on the live pre-cutover apex) did exactly
# that.
#
# `server: cloudflare` is deliberately NOT a marker: it is true before AND after
# the cutover, because the apex was already proxied.
#
# Anchored on `^` because these are header NAMES at line start; an unanchored
# match would also hit the token inside another header's VALUE.
# shellcheck disable=SC2034  # consumed by the scripts that source this file.
APEX_GH_ORIGIN_MARKERS='^(x-github-request-id|x-github-edge-region|x-fastly-request-id|x-served-by|x-proxy-cache|via: 1\.1 varnish)'
