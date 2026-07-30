#!/usr/bin/env bash
# Wall-clock cap on ci-deploy.sh: SIGTERM at 4800s, SIGKILL 20s later (#3704, #2207, #5061, #5669).
#
# Inert by construction — single `exec timeout` line so the wrapper itself
# cannot become a hang surface (the timeout only protects what it spawns,
# not what runs before it). Env vars (SSH_ORIGINAL_COMMAND, DOPPLER_TOKEN,
# CI_DEPLOY_STATE, etc.) inherit naturally through `exec`.
#
# The 4800s literal MUST equal IN_FLIGHT_CEILING_S in
# .github/workflows/web-platform-release.yml — the workflow-side step
# `Pre-rerun lock probe` runtime-asserts STATUS_POLL × INTERVAL ==
# HEALTH_POLL × INTERVAL == IN_FLIGHT_CEILING_S, so a future ceiling change
# must update both files. Raised 900s→1800s (#5061) so a one-time FULL image
# re-pull (build-driver switch / base-layer bump) fits — see the v0.116.1 PIR.
# Raised 1800s→4800s (#5669 / ADR-078): the cron drain in ci-deploy.sh can wait
# up to CRON_DRAIN_TIMEOUT=4200s (the MAX per-function maxTurnDurationMs) for an
# in-flight cron, so the wall-clock must exceed drain + swap overhead or the
# wrapper would SIGKILL ci-deploy.sh mid-drain (killing the very cron it protects).
# A fixed literal — NOT a $((…)) expression — so it can never evaluate to an
# empty/short value across the `exec` boundary (P1-wrapper trap).

# --- #7095: pick up the re-deliverable Doppler credential -----------------------------
# webhook.service's own EnvironmentFile is /etc/default/webhook-deploy, whose DOPPLER_TOKEN
# was revoked at 2026-07-30T11:19:30.614Z with no re-delivery path. This sources the
# re-deliverable sibling so the value the deploy actually runs on can be refreshed by a
# terraform apply. Later-wins: this assignment overrides the one inherited from the unit.
#
# THE OVERRIDE LIVES HERE, NOT IN webhook.service, AND THAT IS THE WHOLE POINT.
# Adding an EnvironmentFile= to the unit would mean the remediation apply must restart the
# webhook to take effect — and the webhook IS the channel that delivers the remediation, on a
# host with no operator SSH runbook and no orderable replacement (cx33, 0 of 3 EU DCs). A unit
# that fails to start after that restart is unrecoverable. Overriding in the wrapper leaves the
# unit definition untouched, so the delayed self-restart cannot fail to start: the worst case
# is a bad token and a failed deploy, with the remediation channel still alive.
#
# This does NOT violate the inert-by-construction property above. That property exists so the
# wrapper cannot become a HANG surface ahead of `timeout`. A `[ -r ]`-guarded `.` of a local
# KEY=VALUE file has no network, no subprocess and no loop — it cannot block. The file's shape
# is enforced three ways before it ever lands (terraform plan validation on doppler_token, the
# installer's envfile_shape rejection, systemd-analyze verify), and `[ -r ]` means an absent
# file is a silent no-op, so a host that has not yet received it keeps its current behaviour.
# Written as an `if` rather than `[ -r … ] && . …` deliberately: the latter is a bare trailing
# command whose exit status is 1 when the file is absent, which would abort the script (and so
# never reach the exec below) the day anyone adds `set -e` to this wrapper. The `if` form is
# status-neutral, so the absent-file case stays a true no-op under any future shell options.
# shellcheck disable=SC1091  # host-side file, not present at lint time
if [ -r /etc/default/soleur-doppler-token ]; then
  . /etc/default/soleur-doppler-token
fi

exec timeout --signal=TERM --kill-after=20s 4800s /usr/local/bin/ci-deploy.sh
