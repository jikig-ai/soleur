#!/usr/bin/env bash
# PR-B §1.6 — Service-role allowlist gate.
#
# Rejects any importer of `createServiceClient` or `getServiceClient`
# in apps/web-platform/{server,lib,app} that is not enumerated in
# apps/web-platform/.service-role-allowlist.
#
# Run from repo root:
#   bash apps/web-platform/scripts/service-role-allowlist-gate.sh
#
# Replaces the rejected ESLint custom rule (per DHH cut #1, simplicity #6).
# CODEOWNERS pins the allowlist file so this gate cannot be self-defeated.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

ALLOWLIST="apps/web-platform/.service-role-allowlist"

if [[ ! -f "$ALLOWLIST" ]]; then
  echo "::error::$ALLOWLIST is missing. The gate file is load-bearing — recreate from PR-B history."
  exit 1
fi

# Use git ls-files so untracked / build artifacts cannot smuggle imports.
# Plan §1.6 scope: apps/web-platform/server and apps/web-platform/lib only.
# `app/api/**/route.ts` is migrated in PR-C (per spec §2.1.5) — gate
# extends to it then.
mapfile -t IMPORTERS < <(
  git ls-files \
    'apps/web-platform/server/*.ts' \
    'apps/web-platform/server/**/*.ts' \
    'apps/web-platform/lib/*.ts' \
    'apps/web-platform/lib/**/*.ts' \
    | xargs -r grep -lE '\b(createServiceClient|getServiceClient)\b' \
    || true
)

if [[ ${#IMPORTERS[@]} -eq 0 ]]; then
  echo "Service-role allowlist gate: no importers detected."
  exit 0
fi

# Strip comments + blank lines from the allowlist for `grep -vFf`.
ALLOWED_PATHS="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST")"

VIOLATORS=()
for f in "${IMPORTERS[@]}"; do
  if ! grep -qxF "$f" <<<"$ALLOWED_PATHS"; then
    VIOLATORS+=("$f")
  fi
done

if [[ ${#VIOLATORS[@]} -gt 0 ]]; then
  echo "::error::Undisclosed service-role importer(s) detected. Either:"
  echo "::error::  (a) Migrate the file to getFreshTenantClient(userId), OR"
  echo "::error::  (b) Add the path to apps/web-platform/.service-role-allowlist with a justifying comment."
  echo "::error::CODEOWNERS will require security-owner review on (b)."
  for v in "${VIOLATORS[@]}"; do
    echo "::error::  $v"
  done
  exit 1
fi

echo "Service-role allowlist gate: ${#IMPORTERS[@]} importer(s) — all enumerated. OK."
