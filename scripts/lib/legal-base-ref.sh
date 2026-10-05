#!/usr/bin/env bash
# legal-base-ref.sh -- THE base-ref resolver for the legal-corpus gates. Source it.
#
# Both gates ask the same question ("what am I diffing against?") and, before #7388's
# review, answered it differently: gate 2 was event-aware while gate 1 hardcoded
# origin/main. Registered side by side in the same runner, they would then measure the
# same PR against two different bases -- on a stacked PR, gate 1 re-scans every line the
# parent branch already landed and blocks the wrong PR for text its author never wrote.
#
# One resolver, two consumers; the same argument that extracted the normaliser.
#
# Provides:
#   legal_resolve_base <explicit-ref-or-empty>
#     Echoes "<base-ref>\t<merge-base-sha>" on success.
#     Exit 2 on anything undecidable -- never a vacuous 0.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "legal-base-ref.sh is a library and must be sourced, not executed." >&2
  exit 64
fi

if [[ -n "${_SOLEUR_LEGAL_BASE_REF_SOURCED:-}" ]]; then
  return 0
fi
_SOLEUR_LEGAL_BASE_REF_SOURCED=1

# Resolve the base ref for the current event, fetching only if it does not already resolve.
#
# THE FETCH IS CONDITIONAL, and that is a measured decision rather than a micro-optimisation:
# CI checks the `test-scripts` shard out at `fetch-depth: 0`, so origin/main already resolves
# before either gate runs. The unconditional fetch both gates used to do was ~98% of their
# measured wall time (gate 1: 2.4s observed, 0.05s of actual work) and cost two network
# round-trips per PR. The guard keeps the shallow-checkout fallback intact for anyone running
# the gate outside that job.
legal_resolve_base() {
  local explicit="${1:-}"
  local base_ref

  if [[ -n "$explicit" ]]; then
    base_ref="$explicit"
  elif [[ -n "${MERGE_GROUP_BASE_SHA:-}" ]]; then
    base_ref="$MERGE_GROUP_BASE_SHA"
  elif [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    base_ref="origin/${GITHUB_BASE_REF}"
  else
    base_ref="origin/main"
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "::error::not inside a git work tree; cannot resolve a base ref" >&2
    return 2
  fi

  if [[ "$base_ref" == origin/* ]] && ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
    git fetch --no-tags --quiet origin "${base_ref#origin/}" 2>/dev/null || true
  fi

  local base_sha
  if ! base_sha=$(git rev-parse --verify --quiet "${base_ref}^{commit}"); then
    echo "::error::base ref '${base_ref}' does not resolve; refusing to report clean" >&2
    return 2
  fi

  local merge_base
  if ! merge_base=$(git merge-base HEAD "$base_sha" 2>/dev/null) || [[ -z "$merge_base" ]]; then
    echo "::error::no merge base between HEAD and '${base_ref}'; refusing to report clean" >&2
    return 2
  fi

  printf '%s\t%s\n' "$base_ref" "$merge_base"
}
