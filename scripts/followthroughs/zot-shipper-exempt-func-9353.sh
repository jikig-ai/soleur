#!/usr/bin/env bash
# Follow-through for the zot log shipper's cap-exemption gap (filed from PR #9353, probe fix for #7556).
#
# The shipper's `is_cap_exempt` keys on the zerolog `message` prefix (`PatchBlobUpload*`), but the real
# PatchBlobUpload error line carries `message:unexpected error, removing .uploads/ files` and names the
# handler only in `func:`, so that line is rate-capped instead of exempt. Closing criterion: the
# `is_cap_exempt` function in cloud-init-registry.yml classifies on the parsed `func` field.
#
# Event-grep shape (no secrets, no network): PASS (exit 0) only when the function exists AND its body
# mentions `func`; anything else is TRANSIENT (exit 2), so a quiet or moved function never closes the
# tracker. This repo-file read says the fix MERGED, not that it was DEPLOYED: delivery is a gated
# registry-host-replace dispatch (ADR-096/ADR-169), tracked in the issue body.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh): 0 PASS, 1 FAIL, other TRANSIENT.
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FILE="${REPO_ROOT}/apps/web-platform/infra/cloud-init-registry.yml"

[[ -r "$FILE" ]] || { echo "zot-shipper-exempt-func[#9353]: TRANSIENT reason=file-unreadable"; exit 2; }

# The function body: from its opening line to the first line that is exactly a closing brace at its indent.
body="$(awk '/^[[:space:]]*is_cap_exempt\(\) \{/ {f=1} f {print} f && /^[[:space:]]*\}[[:space:]]*$/ {exit}' "$FILE")"
if [[ -z "$body" ]]; then
  echo "zot-shipper-exempt-func[#9353]: TRANSIENT reason=function-not-found"
  exit 2
fi
# Strip whole-line comments first: the existing prose already says "func" in places.
code="$(printf '%s\n' "$body" | sed -E 's/^[[:space:]]*#.*$//')"
if grep -qE '\bfunc\b' <<<"$code"; then
  echo "zot-shipper-exempt-func[#9353]: PASS is_cap_exempt classifies on the func field (merged; confirm the registry host was replaced)"
  exit 0
fi
echo "zot-shipper-exempt-func[#9353]: TRANSIENT reason=not-yet-func-keyed"
exit 2
