#!/usr/bin/env bash
# Offline-only qualification preparation tests; real daemon access is absent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUALIFICATION_DIR="${SCRIPT_DIR}/../codex-qualification"
export PYTHONDONTWRITEBYTECODE=1
for module in api_policy test_ownership_exec test_resource_ownership test_name_collision_transport test_proxy test_resource_transport test_preparation; do
  python3 -W error "${QUALIFICATION_DIR}/${module}.py"
done
