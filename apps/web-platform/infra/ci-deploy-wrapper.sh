#!/usr/bin/env bash
# Wall-clock cap on ci-deploy.sh: SIGTERM at 1800s, SIGKILL 20s later (#3704, #2207, #5061).
#
# Inert by construction — single `exec timeout` line so the wrapper itself
# cannot become a hang surface (the timeout only protects what it spawns,
# not what runs before it). Env vars (SSH_ORIGINAL_COMMAND, DOPPLER_TOKEN,
# CI_DEPLOY_STATE, etc.) inherit naturally through `exec`.
#
# The 1800s literal MUST equal IN_FLIGHT_CEILING_S in
# .github/workflows/web-platform-release.yml — the workflow-side step
# `Pre-rerun lock probe` runtime-asserts STATUS_POLL × INTERVAL ==
# HEALTH_POLL × INTERVAL == IN_FLIGHT_CEILING_S, so a future ceiling change
# must update both files. Raised 900s→1800s (#5061) so a one-time FULL image
# re-pull (build-driver switch / base-layer bump) fits — see the v0.116.1 PIR.
exec timeout --signal=TERM --kill-after=20s 1800s /usr/local/bin/ci-deploy.sh
