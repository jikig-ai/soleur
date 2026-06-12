#!/usr/bin/env bash
# Idempotent bootstrap for the operator weekly comprehension digest (#5085).
#
# Run ONCE post-merge on the operator's gh-authenticated machine. It:
#   1. reads ANTHROPIC_API_KEY from Doppler (soleur/prd) and fails loud if empty;
#   2. creates the PRIVATE jikig-ai/operator-digest repo (no-op if it already exists);
#   3. sets ANTHROPIC_API_KEY as an Actions secret via STDIN (never argv);
#   4. installs the committed workflow asset into the repo's default branch;
#   5. enables the workflow so the weekly `schedule:` fires.
#
# Idempotent: re-running re-installs the workflow (create-or-update) and re-sets the secret.
# Every step is `gh`/`doppler` CLI automation — no manual dashboard step (hr-all-infrastructure-
# provisioning-servers + hr-multi-step-post-merge-bootstrap-script).
#
# After it completes: gh workflow run operator-digest.yml -R jikig-ai/operator-digest
set -uo pipefail

REPO="${OPERATOR_DIGEST_REPO:-jikig-ai/operator-digest}"
DOPPLER_PROJECT="${OPERATOR_DIGEST_DOPPLER_PROJECT:-soleur}"
DOPPLER_CONFIG="${OPERATOR_DIGEST_DOPPLER_CONFIG:-prd}"
SECRET_NAME="ANTHROPIC_API_KEY"
WORKFLOW_PATH=".github/workflows/operator-digest.yml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_ASSET="${SCRIPT_DIR}/../assets/operator-digest.workflow.yml"

SECRET_VALUE=""  # populated by fetch_secret

log() { printf '[provision] %s\n' "$*" >&2; }
die() { printf '[provision] ERROR: %s\n' "$*" >&2; exit 1; }

require_tools() {
  command -v gh >/dev/null 2>&1      || die "gh CLI not found on PATH"
  command -v doppler >/dev/null 2>&1 || die "doppler CLI not found on PATH"
  gh auth status >/dev/null 2>&1     || die "gh is not authenticated — run 'gh auth login'"
}

# fetch_secret — read ANTHROPIC_API_KEY from Doppler; fail loud (die) if missing/empty.
# Sets the global SECRET_VALUE. NOTE: split declaration from assignment so the command
# substitution's exit code is observable (a `local x=$(...)` masks it and always returns 0).
fetch_secret() {
  local value
  value="$(doppler secrets get "$SECRET_NAME" -p "$DOPPLER_PROJECT" -c "$DOPPLER_CONFIG" --plain)" \
    || die "doppler secrets get ${SECRET_NAME} failed (project=${DOPPLER_PROJECT} config=${DOPPLER_CONFIG})"
  [[ -n "$value" ]] || die "Doppler returned an EMPTY ${SECRET_NAME} (project=${DOPPLER_PROJECT} config=${DOPPLER_CONFIG}) — refusing to set an empty Actions secret"
  SECRET_VALUE="$value"
  log "read ${SECRET_NAME} from Doppler ${DOPPLER_PROJECT}/${DOPPLER_CONFIG}"
}

ensure_repo() {
  if gh repo view "$REPO" >/dev/null 2>&1; then
    log "repo ${REPO} already exists — skipping create"
  else
    log "creating private repo ${REPO}"
    gh repo create "$REPO" --private --add-readme \
      --description "Operator weekly comprehension digest — private (provisioned from soleur #5085)" \
      || die "gh repo create ${REPO} failed (needs org-owner scope)"
  fi
}

# set_secret — deliver the value to gh via STDIN; never pass it on argv.
set_secret() {
  local value="$1"
  printf '%s' "$value" | gh secret set "$SECRET_NAME" -R "$REPO" \
    || die "gh secret set ${SECRET_NAME} on ${REPO} failed"
  log "set Actions secret ${SECRET_NAME} on ${REPO} (via stdin)"
}

# install_workflow — create-or-update the workflow on the default branch via the contents API.
install_workflow() {
  [[ -r "$WORKFLOW_ASSET" ]] || die "workflow asset not readable at ${WORKFLOW_ASSET}"
  local b64 existing_sha
  b64="$(base64 -w0 "$WORKFLOW_ASSET" 2>/dev/null || base64 "$WORKFLOW_ASSET" | tr -d '\n')"
  existing_sha="$(gh api "repos/${REPO}/contents/${WORKFLOW_PATH}" --jq '.sha' 2>/dev/null || true)"
  local args=(--method PUT "repos/${REPO}/contents/${WORKFLOW_PATH}"
    -f "message=chore: install operator-digest workflow (#5085)"
    -f "content=${b64}")
  [[ -n "$existing_sha" ]] && args+=(-f "sha=${existing_sha}")
  gh api "${args[@]}" >/dev/null || die "failed to install ${WORKFLOW_PATH} into ${REPO}"
  log "installed ${WORKFLOW_PATH} into ${REPO}"
}

# enable_workflow — newly-added workflows are enabled by default, but GitHub may need a moment
# to register the file before `gh workflow enable` can find it. Soft-retry; a failure here is a
# warning, not fatal (the schedule still fires once the file is on the default branch).
enable_workflow() {
  local i
  for i in 1 2 3 4 5; do
    if gh workflow enable operator-digest.yml -R "$REPO" >/dev/null 2>&1; then
      log "enabled operator-digest.yml on ${REPO}"
      return 0
    fi
    sleep 3
  done
  log "WARN: 'gh workflow enable' did not confirm after retries — verify with 'gh workflow list -R ${REPO}'"
}

main() {
  require_tools
  fetch_secret          # fail-fast before creating anything
  ensure_repo
  set_secret "$SECRET_VALUE"
  install_workflow
  enable_workflow
  log "done. Trigger a run with: gh workflow run operator-digest.yml -R ${REPO}"
}

# Only run main when executed directly — sourcing (e.g. from the test) is side-effect-free.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
