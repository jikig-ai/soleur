# shellcheck shell=bash
# bastion-birth-readiness.sh — the boot-readiness interlock both bastion routes run before any plan
# (#12866 F-interlock, extracted by #12879 F1; ADR-327 steps 2a and 2b).
#
#   bastion_birth_readiness <dispatch-label>   # 0 = ready to plan; 1 = HELD (message names the label)
#
# Fail closed BEFORE any plan: a create whose boot cannot be read would be followed by a SKIPPED
# verdict, and boot-verify powers a skipped host off, so the birth (or the replacement) would be
# wasted. Both workflows call this from a step still named "Birth-readiness interlock", so the suites
# anchored on that name keep binding; the body moved here word for word with `bastion-host-create`
# replaced by the label, so a replace never prints "bastion-host-create is HELD".
#
# Inputs (environment): SENTRY_ACTIONS_RO_TOKEN (the boot-trail reader's token; never printed).
# BASTION_CLOUD_INIT overrides the template path for the SUITE ONLY (tests/scripts/test-bastion-boot-verify.sh):
# set while GITHUB_ACTIONS=true it is refused as HELD, never silently honoured or ignored (Q-R10).

_BBR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bastion_birth_readiness() {
  local label="${1:-}" ci body lit
  [[ "$label" =~ ^bastion-host-(create|replace)$ ]] || {
    echo "::error::bastion_birth_readiness: unknown dispatch label '${label}'. Nothing was planned or created."
    return 1
  }
  if [[ -n "${BASTION_CLOUD_INIT+set}" && "${GITHUB_ACTIONS:-}" == true ]]; then
    echo "::error::${label} is HELD: BASTION_CLOUD_INIT is a test-only override of the cloud-init template path and is never honoured in a workflow run. Nothing was planned or created."
    return 1
  fi
  ci="${BASTION_CLOUD_INIT:-${_BBR_DIR}/../../apps/web-platform/infra/bastion-cloud-init.yml}"
  if [[ ! -r "$ci" ]]; then
    echo "::error::${label} is HELD: bastion-cloud-init.yml could not be read at ${ci}, so the boot could not be verified. Nothing was planned or created."
    return 1
  fi
  # Comment lines stripped first: a literal that survives only in a comment emits nothing. grep exits 1
  # when every line is a comment; inside `if !` that is a named refusal, never a silent set -e exit.
  if ! body="$(grep -vE '^[[:space:]]*#' "$ci")"; then
    echo "::error::${label} is HELD: bastion-cloud-init.yml at ${ci} holds no line outside a comment, so it emits nothing and the boot could not be verified. Nothing was planned or created."
    return 1
  fi
  for lit in fresh_boot_ready fresh_boot_not_ready_ cloud_init_complete; do
    if ! grep -qF "$lit" <<<"$body"; then
      echo "::error::${label} is HELD: bastion-cloud-init.yml does not emit '${lit}', so the boot could not be verified. Nothing was planned or created."
      return 1
    fi
  done
  if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]; then
    echo "::error::${label} is HELD: SENTRY_ACTIONS_RO_TOKEN is not bound, so the boot trail could not be read and a born bastion would be powered off as unverified. Nothing was planned or created."
    return 1
  fi
  # Byte-identical to the reader's _bearer_ok (fresh-host-boot-trail.sh), LC_ALL=C included,
  # so this interlock never admits a token the reader then refuses.
  _bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
  if ! _bearer_ok "$SENTRY_ACTIONS_RO_TOKEN"; then
    echo "::error::${label} is HELD: SENTRY_ACTIONS_RO_TOKEN failed the boot-trail reader's token-shape check. Nothing was planned or created."
    return 1
  fi
  echo "birth-readiness interlock PASSED (emitter literals present; boot-trail token bound and well-formed)."
  return 0
}
