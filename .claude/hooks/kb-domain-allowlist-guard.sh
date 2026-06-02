#!/usr/bin/env bash
# PreToolUse hook for Write, Edit, MultiEdit, NotebookEdit, and Bash.
# ADVISORY guard: surfaces a one-time `ask` when a write would introduce a NEW
# top-level entry under `knowledge-base/` that is NOT in the sanctioned domain
# set.
#
# Source request: keep knowledge-base/ to its documented domain + project
# directories. A stray top-level dir (e.g. an accidental `security/` that only
# holds a placeholder) renders as an anomalous entry in the GitHub/web file
# browser and fragments the domain taxonomy. This guard makes a new top-level
# segment an explicit, operator-acknowledged decision rather than a silent one.
#
# Decision tier = `ask` (NOT `deny`, NOT silent `allow`): adding a new top-level
# domain is a legitimate-but-rare operation (see plugins/soleur/AGENTS.md
# "Adding a New Domain"). A hard deny would break that flow; a silent allow
# defeats the guard. `ask` surfaces it for one operator confirmation, then the
# segment exists on disk and subsequent writes pass cleanly.
#
# Fires ONLY on a NEW top-level segment (not already on disk and not sanctioned).
# Writing INTO an existing sanctioned domain (engineering/, project/, ...) or to
# a sanctioned top-level file (INDEX.md, ...) always passes.
#
# Coverage mirrors no-memory-write.sh: file tools check file_path/notebook_path;
# Bash checks the command string for a knowledge-base/<segment> substring to
# catch `mkdir`/`cat >`/`mv`/`tee` redirects. Adversarial evasion (eval, base64)
# is out of scope — this gate exists for accidental taxonomy drift, not
# bypass-defeat.

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true
if ! declare -f emit_incident >/dev/null; then
  emit_incident() { :; }
fi

# --- Sanctioned set (SINGLE SOURCE OF TRUTH) -------------------------------
# To sanction a NEW top-level knowledge-base domain: add it to SANCTIONED_DIRS
# below AND follow the multi-step process in plugins/soleur/AGENTS.md
# "Adding a New Domain". Keep these two in sync.
#
# `security` is intentionally NOT sanctioned — it was relocated to
# engineering/security/skill-overrides/ (the override-evidence dir nests under
# the engineering domain). Do NOT re-add `security` as a top-level domain.
SANCTIONED_DIRS=(engineering finance legal marketing operations product project sales support)
SANCTIONED_FILES=(INDEX.md kb-categories.txt kb-tags.txt)

INPUT=$(cat)

# Fail-open on malformed JSON (mirror no-memory-write.sh): a parse failure must
# not silently block every tool call.
if ! TARGET=$(printf '%s' "$INPUT" | jq -r '
  .tool_input.file_path
  // .tool_input.notebook_path
  // .tool_input.command
  // ""
' 2>/dev/null); then
  exit 0
fi

[[ -z "$TARGET" ]] && exit 0

# Extract the first path component under knowledge-base/. Match the segment
# anywhere (absolute worktree paths, relative paths, and Bash command
# substrings — `mkdir knowledge-base/x` has no `/` before knowledge-base, so a
# `.*/`-prefixed regex would miss it).
if [[ ! "$TARGET" =~ knowledge-base/([^/[:space:]\"\']+) ]]; then
  exit 0
fi
SEGMENT="${BASH_REMATCH[1]}"

# Sanctioned directory? pass.
for d in "${SANCTIONED_DIRS[@]}"; do
  [[ "$SEGMENT" == "$d" ]] && exit 0
done
# Sanctioned top-level file? pass.
for f in "${SANCTIONED_FILES[@]}"; do
  [[ "$SEGMENT" == "$f" ]] && exit 0
done

# Already on disk? pass (writing into / editing an existing top-level entry is
# always fine — avoids false positives on every KB write, and a previously
# acknowledged domain stops nagging once it exists).
# Resolve the kb root from the directory prefix before the literal
# `knowledge-base/`. Only trust the prefix when it is a plausible dir path
# (ends in `/`, contains no spaces) — for relative paths or Bash command
# fragments (`mkdir -p knowledge-base/...`) fall back to CLAUDE_PROJECT_DIR.
KB_PARENT="${TARGET%%knowledge-base/*}"
if [[ -n "$KB_PARENT" && "$KB_PARENT" == */ && "$KB_PARENT" != *" "* ]]; then
  KB_ROOT="${KB_PARENT}knowledge-base"
else
  KB_ROOT="${CLAUDE_PROJECT_DIR:-.}/knowledge-base"
fi
if [[ -e "${KB_ROOT}/${SEGMENT}" ]]; then
  exit 0
fi

# NEW unsanctioned top-level entry → advisory ask.
emit_incident kb-domain-allowlist-guard ask \
  "New top-level knowledge-base entry outside sanctioned domain set" "$TARGET"
jq -n --arg seg "$SEGMENT" --arg target "$TARGET" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("ADVISORY: kb-domain-allowlist-guard — this write introduces a NEW top-level entry under knowledge-base/ (`" + $seg + "`) that is not in the sanctioned domain set.\n\nTarget: " + $target + "\n\nSanctioned top-level dirs: engineering finance legal marketing operations product project sales support\nSanctioned top-level files: INDEX.md kb-categories.txt kb-tags.txt\n\nIf this is intentional, confirm to proceed AND add the domain to .claude/hooks/kb-domain-allowlist-guard.sh + follow plugins/soleur/AGENTS.md \"Adding a New Domain\". Otherwise, place the artifact under an existing domain.")
  }
}'
exit 0
