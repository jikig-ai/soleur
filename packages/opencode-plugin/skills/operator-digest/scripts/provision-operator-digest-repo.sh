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

# REPO is a hardcoded constant — it MUST stay in lockstep with the `gh issue create -R <repo>`
# post target in assets/operator-digest.workflow.yml. Making it env-overridable would let
# provisioning create/secret/install into repo X while the installed workflow still posts to
# jikig-ai/operator-digest (a silent misroute). If the target ever changes, change both together.
REPO="jikig-ai/operator-digest"
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
    # --add-readme is load-bearing, not cosmetic: install_workflow uses the contents API
    # (PUT repos/.../contents/...), which requires a default branch to already exist. A repo
    # created with zero commits has no default-branch ref and the PUT 404s. The README is the
    # initial commit that creates `main`. Do not drop --add-readme.
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

# set_operator_login — the digest posts to a PRIVATE repo, and a `gh issue
# create` into a repo with zero subscribers notifies nobody. That is not
# hypothetical: the digest ran correctly for months while 130 days of
# action-required backlog accumulated unseen, because the delivery channel was
# dead. The workflow assigns each digest to this login so it notifies
# unconditionally, independent of watch state.
#
# Repo VARIABLE, not a secret: a GitHub login is not confidential, and secrets
# are masked in logs — masking the assignee would make a delivery failure
# harder to diagnose, which is the failure mode being repaired.
set_operator_login() {
  local login="${OPERATOR_GH_LOGIN:-}"
  if [[ -z "$login" ]]; then
    login="$(gh api user --jq .login 2>/dev/null || true)"
  fi
  [[ -n "$login" ]] || die "could not resolve operator login; set OPERATOR_GH_LOGIN explicitly"
  gh variable set OPERATOR_GH_LOGIN -R "$REPO" --body "$login" \
    || die "gh variable set OPERATOR_GH_LOGIN on ${REPO} failed"
  log "set Actions variable OPERATOR_GH_LOGIN=${login} on ${REPO} (digest assignee)"
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

# enable_workflow — newly-added workflows may need a moment to register before `gh workflow enable`
# can find them. Soft-retry the enable, then POSITIVELY verify the workflow state is `active`. This
# is the terminal step of a fire-and-forget bootstrap whose operator is non-technical: a silently-
# not-enabled workflow means the digest never fires, and a WARN buried in stderr of a "done" run is
# effectively invisible. Fail loud (die) if it is not active — the script is idempotent, so the
# operator can simply re-run. NOTE: `gh workflow view` has no --json; state lives on `gh workflow list`.
enable_workflow() {
  local state="" _
  for _ in 1 2 3 4 5; do
    gh workflow enable operator-digest.yml -R "$REPO" >/dev/null 2>&1 || true
    state="$(gh workflow list -R "$REPO" --json path,state \
      -q '.[] | select(.path==".github/workflows/operator-digest.yml") | .state' 2>/dev/null || true)"
    if [[ "$state" == "active" ]]; then
      log "operator-digest.yml is active on ${REPO}"
      return 0
    fi
    sleep 3
  done
  die "operator-digest.yml is not active on ${REPO} (last state: '${state:-unknown}') — the digest will NOT fire. Re-run this script, or check 'gh workflow list -R ${REPO}'."
}

main() {
  require_tools
  fetch_secret          # fail-fast before creating anything
  ensure_repo
  set_secret "$SECRET_VALUE"
  set_operator_login    # must precede install_workflow: the workflow fails loud without it
  install_workflow
  enable_workflow
  log "done. Trigger a run with: gh workflow run operator-digest.yml -R ${REPO}"
}

# Only run main when executed directly — sourcing (e.g. from the test) is side-effect-free.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
