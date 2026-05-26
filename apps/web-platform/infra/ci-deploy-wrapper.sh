#!/usr/bin/env bash
# Wall-clock cap on ci-deploy.sh: SIGTERM at 900s, SIGKILL 20s later (#3704, #2207).
#
# Inert by construction — single `exec timeout` line so the wrapper itself
# cannot become a hang surface (the timeout only protects what it spawns,
# not what runs before it). Env vars (SSH_ORIGINAL_COMMAND, DOPPLER_TOKEN,
# CI_DEPLOY_STATE, etc.) inherit naturally through `exec`.
#
# The 900s literal MUST equal IN_FLIGHT_CEILING_S in
# .github/workflows/web-platform-release.yml — the workflow-side step
# `Pre-rerun lock probe` runtime-asserts STATUS_POLL × INTERVAL ==
# HEALTH_POLL × INTERVAL == IN_FLIGHT_CEILING_S, so a future ceiling change
# must update both files.
exec timeout --signal=TERM --kill-after=20s 900s /usr/local/bin/ci-deploy.sh
