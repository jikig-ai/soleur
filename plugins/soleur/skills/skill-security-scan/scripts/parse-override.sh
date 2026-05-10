#!/usr/bin/env bash
set -euo pipefail
# TODO Phase 4: scan git diff <base>...<head> --diff-filter=A for new files
# under knowledge-base/security/skill-overrides/, validate frontmatter against
# override-artifact-schema.json, check rule_pack_sha256 freshness, validate
# slug regex ^[a-z][a-z0-9-]*$.
echo '{"matched":[],"invalid_schema":[],"stale_findings":[]}'
