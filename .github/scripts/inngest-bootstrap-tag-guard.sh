#!/usr/bin/env bash
# Tag invariant guard for build-inngest-bootstrap-image.yml (#4692).
#
# Makes "every published soleur-inngest-bootstrap image corresponds to a
# vinngest-v* git tag" a workflow invariant so the consumption-side drift-guard
# (apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh AC6, #4676)
# cannot be blinded by a tagless workflow_dispatch publish.
#
# Subcommand:
#   resolve-tag <event_name> <github_ref> <inputs_ref>
#     Derives the OCI image tag (vX.Y.Z) for both publish paths:
#       - workflow_dispatch: <inputs_ref> is an existing vinngest-v* tag
#         (already regex-validated inline, pre-checkout, in the workflow).
#       - push:             <github_ref> is refs/tags/vinngest-vX.Y.Z.
#     Strips the refs/tags/ and vinngest- prefixes, then re-validates the
#     result against ^v[0-9]+\.[0-9]+\.[0-9]+$ (the regex is the reject gate,
#     not the strip). Prints the tag on stdout; exits 1 on any non-vX.Y.Z ref.
#
#     The ^v[0-9]+\.[0-9]+\.[0-9]+$ literal is byte-identical to the consumer
#     drift-guard's regex (cloud-init-inngest-bootstrap.test.sh) — the
#     producer/consumer parity gate in test-inngest-bootstrap-tag-guard.sh
#     fails if either side drifts.

set -euo pipefail
export LC_ALL=C

resolve_tag() {
  local event="${1:-}" github_ref="${2:-}" inputs_ref="${3:-}" src tag
  # Discriminate on the event name (NOT on inputs_ref emptiness) so a future
  # default/stale dispatch input can never misroute the push path.
  if [[ "$event" == "workflow_dispatch" ]]; then
    src="$inputs_ref"
  else
    src="$github_ref"
  fi
  tag="${src#refs/tags/}"
  tag="${tag#vinngest-}"
  # The regex is the reject gate: a non-vinngest ref (web-v0.1.0), a branch
  # ref (refs/heads/main), a pre-release (vinngest-v1.1.11-rc1), an empty
  # input, or a double-prefix (vinngest-vinngest-v1.2.3) all fail here. It
  # also guarantees non-empty, so no separate -n check is needed.
  if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: resolved tag '$tag' is not vX.Y.Z (from ref '$src', event '$event')" >&2
    return 1
  fi
  printf '%s\n' "$tag"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    resolve-tag) resolve_tag "$@" ;;
    *)
      echo "usage: $(basename "$0") resolve-tag <event_name> <github_ref> <inputs_ref>" >&2
      exit 2
      ;;
  esac
}

main "$@"
