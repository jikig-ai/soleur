#!/usr/bin/env bash
# Post-apply operator sync (#4177) — write the CF Access CI-SSH service-token
# credentials produced by `cloudflare_zero_trust_access_service_token.ci_ssh`
# into Doppler `prd_terraform` so `apply-deploy-pipeline-fix.yml` can pull
# them at run time. Apply-web-platform-infra creates the token; this script
# closes the loop into Doppler. Idempotent (`doppler secrets set` overwrites).
#
# Pre-requisites:
#   - Operator has just run `terraform apply` against apps/web-platform/infra/
#     (or the apply-web-platform-infra.yml workflow has landed the new tokens).
#   - `doppler` CLI is authenticated against the soleur project.
#   - `terraform` CLI is on PATH and pointed at the same R2-backed state.
#
# Run from the worktree root.
set -euo pipefail

INFRA_DIR="apps/web-platform/infra"

if [[ ! -d "$INFRA_DIR" ]]; then
  echo "[sync-ci-ssh-access-token] not in soleur worktree root (expected $INFRA_DIR/)" >&2
  exit 1
fi

# Read outputs from the infra root. `terraform output -raw` exits non-zero
# if the output is missing — set -e propagates that.
CLIENT_ID=$(cd "$INFRA_DIR" && terraform output -raw ci_ssh_access_service_token_client_id)
CLIENT_SECRET=$(cd "$INFRA_DIR" && terraform output -raw ci_ssh_access_service_token_client_secret)

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "[sync-ci-ssh-access-token] empty terraform output — has \`terraform apply\` been run against $INFRA_DIR/?" >&2
  exit 1
fi

# `doppler secrets set` overwrites in-place (idempotent). `--silent` suppresses
# the just-set value echo; `--no-interactive` skips the confirmation prompt.
# stdin write is safer than `--body "$VALUE"` (no argv exposure to `ps aux`).
printf '%s' "$CLIENT_ID" \
  | doppler secrets set CI_SSH_ACCESS_TOKEN_ID --silent --no-interactive -p soleur -c prd_terraform >/dev/null

printf '%s' "$CLIENT_SECRET" \
  | doppler secrets set CI_SSH_ACCESS_TOKEN_SECRET --silent --no-interactive -p soleur -c prd_terraform >/dev/null

unset CLIENT_ID CLIENT_SECRET

echo "[sync-ci-ssh-access-token] OK — CI_SSH_ACCESS_TOKEN_ID/_SECRET written to doppler prd_terraform."
echo "  Next: re-fire apply-deploy-pipeline-fix.yml so the SSH bridge picks up the new creds:"
echo "    gh workflow run apply-deploy-pipeline-fix.yml --ref main -F reason='post-#4177 CF SSH tunnel bring-up'"
