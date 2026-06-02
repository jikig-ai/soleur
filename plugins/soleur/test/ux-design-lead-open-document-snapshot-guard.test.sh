#!/usr/bin/env bash

# #3274 — Regression guard: the ux-design-lead agent must guard `open_document`
# against the destructive .pen wipe (a 133KB source silently overwritten with
# 41-byte empty state while open_document returned success). The agent body must
# carry a pre-open snapshot instruction, a post-open collapse HARD GATE with a
# concrete threshold, and a new-file exemption. Also guards the AC7 fold-in: the
# retired `cq-pencil-mcp-silent-drop-diagnosis-checklist` citation must be gone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
AGENT="$REPO_ROOT/plugins/soleur/agents/product/design/ux-design-lead.md"

echo "=== ux-design-lead open_document snapshot/collapse guard ==="
echo ""

assert_file_exists "$AGENT" "ux-design-lead agent exists"

# AC1 — pre-open snapshot instruction (record size + checksum BEFORE open_document).
set +e
grep -qiE "before .*open_document|snapshot.*(size|sha256|checksum)" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "agent records a pre-open snapshot before open_document on existing .pen"

# AC2 — post-open collapse gate present. Match tokens unique to the new gate
# block — NOT the bare word "collapse", which already appears in the pre-existing
# UX-audit "sidebar collapse" prose and would make this assertion vacuous.
set +e
grep -qiE "collapse gate|destructive wipe|parse failure" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "agent has a post-open collapse gate"

# AC3 — concrete, testable trip condition (the 41-byte / 133KB #3274 case must trip).
set +e
grep -qiE "< ?50%|64 bytes" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "collapse threshold is concrete (e.g. < 50% OR <= 64 bytes)"

# AC4 — new-file open is exempt from the collapse gate.
set +e
grep -qiE "new[- ]file exemption|brand-new document|new doc legitimately" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "collapse gate exempts brand-new document creation"

# AC10 — fold-in regression guards: retired citation gone, canonical path stays.
set +e
grep -q "AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist" "$AGENT"
rc=$?
set -e
assert_eq "1" "$rc" "retired AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist citation removed"

set +e
grep -q "ex-cq-pencil-mcp-silent-drop-diagnosis-checklist" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "repointed to live ex-cq-pencil-mcp-silent-drop-diagnosis-checklist Sharp Edge"

# The repoint must be machine-resolvable: the anchor token must grep cleanly in
# the cited target (guards against the backtick-split rendering that made the
# token unsearchable in SKILL.md).
PENCIL_SKILL="$REPO_ROOT/plugins/soleur/skills/pencil-setup/SKILL.md"
assert_file_exists "$PENCIL_SKILL" "pencil-setup SKILL.md (repoint target) exists"
set +e
grep -q "ex-cq-pencil-mcp-silent-drop-diagnosis-checklist" "$PENCIL_SKILL"
rc=$?
set -e
assert_eq "0" "$rc" "anchor token is greppable (contiguous) in the cited target SKILL.md"

set +e
grep -q "knowledge-base/product/design/" "$AGENT"
rc=$?
set -e
assert_eq "0" "$rc" "canonical knowledge-base/product/design/ path still referenced"

print_results
