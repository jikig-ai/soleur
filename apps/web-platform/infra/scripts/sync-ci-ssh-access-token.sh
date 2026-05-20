#!/usr/bin/env bash
# Local-fallback sync (#4177) — write the CF Access CI-SSH service-token
# credentials into Doppler `prd_terraform`. The canonical path is the
# `Sync CF Access CI-SSH service token to Doppler` step in
# `.github/workflows/apply-web-platform-infra.yml`, which runs post-apply
# on every infra merge. Use this script only for local reprovisioning
# (e.g., after `terraform apply` from a workstation, or rotating the
# token by tainting the resource). Idempotent (`doppler secrets set`
# overwrites in place).
#
# Pre-requisites:
#   - Operator has just run `terraform apply` against apps/web-platform/infra/.
#   - `doppler` CLI is authenticated against the soleur project.
#   - `terraform` CLI is on PATH and pointed at the same R2-backed state.
#
# Run from the worktree root.
set -euo pipefail
trap 'unset CLIENT_ID CLIENT_SECRET' EXIT

INFRA_DIR="apps/web-platform/infra"

if [[ ! -d "$INFRA_DIR" ]]; then
  echo "[sync-ci-ssh-access-token] not in soleur worktree root (expected $INFRA_DIR/)" >&2
  exit 1
fi

# `terraform output -raw <name>` exits non-zero when there's no state at
# all, but exits 0 with empty stdout when state exists but the named
# output isn't defined yet (e.g., apply ran with -target= excluding the
# SSH resources). The `-z` guard below catches both cases.
pushd "$INFRA_DIR" >/dev/null
CLIENT_ID=$(terraform output -raw ci_ssh_access_service_token_client_id 2>/dev/null || true)
CLIENT_SECRET=$(terraform output -raw ci_ssh_access_service_token_client_secret 2>/dev/null || true)
popd >/dev/null

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "[sync-ci-ssh-access-token] ci_ssh_access_service_token outputs missing or empty." >&2
  echo "  Run \`terraform apply\` against $INFRA_DIR/ first, or trigger" >&2
  echo "  \`gh workflow run apply-web-platform-infra.yml --ref main -F reason=...\`." >&2
  exit 1
fi

# `doppler secrets set` overwrites in-place (idempotent). `--silent` suppresses
# the just-set value echo; `--no-interactive` skips the confirmation prompt.
# stdin write is safer than `--body "$VALUE"` (no argv exposure to `ps aux`).
printf '%s' "$CLIENT_ID" \
  | doppler secrets set CI_SSH_ACCESS_TOKEN_ID --silent --no-interactive -p soleur -c prd_terraform >/dev/null 2>&1

printf '%s' "$CLIENT_SECRET" \
  | doppler secrets set CI_SSH_ACCESS_TOKEN_SECRET --silent --no-interactive -p soleur -c prd_terraform >/dev/null 2>&1

echo "[sync-ci-ssh-access-token] OK — CI_SSH_ACCESS_TOKEN_ID/_SECRET written to doppler prd_terraform."
echo "  Next: re-fire apply-deploy-pipeline-fix.yml so the SSH bridge picks up the new creds:"
echo "    gh workflow run apply-deploy-pipeline-fix.yml --ref main -F reason='post-#4177 CF SSH tunnel bring-up'"
