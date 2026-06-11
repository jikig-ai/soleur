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
# Coverage mirrors no-memory-write.sh: file tools check file_path/notebook_path
# (an unambiguous write target). Bash checks the command string for a
# knowledge-base/<segment> substring, but ONLY treats it as guard-worthy when the
# command actually WRITES to that path — a positive write-VERB / kb-targeted-
# REDIRECT allowlist (`mkdir`/`touch`/`tee`/`cat >`/`mv`/`cp`/`git add`/…). A
# read-only reference that merely MENTIONS a kb path (`git show <ref>:path`,
# `git ls-tree`, `grep`, `cat`) carries no write verb and no kb-targeted redirect,
# so it passes cleanly instead of firing a spurious `ask`. Adversarial evasion
# (eval, base64) AND exotic write forms are out of scope — this gate exists for
# accidental taxonomy drift, not bypass-defeat.

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

# Bash-class discriminator (fail-open). `tool_name` is the authoritative signal,
# but the existing test payloads omit it (`{tool_input:{command:...}}` /
# `{tool_input:{file_path:...}}`), so fall back to the payload shape: a command
# present with no file_path/notebook_path is the Bash class. Mirror
# background-poll-prefer-monitor.sh:81 (`jq -r '.tool_name // empty'`). Any jq
# failure yields empty — a missing/garbled tool_name on a real Bash command still
# gets the read-vs-write gate (command present), and on a file write still reaches
# the existing `ask` logic (file_path present, so IS_BASH stays unset).
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
HAS_COMMAND=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input.command // "") != "" then "1" else "" end' 2>/dev/null || true)
HAS_FILE_PATH=$(printf '%s' "$INPUT" | jq -r 'if (.tool_input.file_path // .tool_input.notebook_path // "") != "" then "1" else "" end' 2>/dev/null || true)
IS_BASH=""
if [[ "$TOOL_NAME" == "Bash" ]] || { [[ -z "$TOOL_NAME" ]] && [[ -n "$HAS_COMMAND" ]] && [[ -z "$HAS_FILE_PATH" ]]; }; then
  IS_BASH=1
fi

# Extract the first path component under knowledge-base/. Match the segment
# anywhere (absolute worktree paths, relative paths, and Bash command
# substrings — `mkdir knowledge-base/x` has no `/` before knowledge-base, so a
# `.*/`-prefixed regex would miss it).
if [[ ! "$TARGET" =~ knowledge-base/([^/[:space:]\"\']+) ]]; then
  exit 0
fi
SEGMENT="${BASH_REMATCH[1]}"

# Bash write-target gate (read-vs-write distinction). For the Bash class only,
# the matched knowledge-base/<segment> is a guard-worthy NEW top-level entry ONLY
# when the command actually WRITES to it. A read reference (`git show
# <ref>:knowledge-base/...`, `git ls-tree`, `grep`, `cat`, `gh ... view`) merely
# MENTIONS the path — the Bash coverage exists to catch accidental taxonomy-drift
# WRITES (mkdir/cat >/mv/tee), not reads. A Bash read that passes this gate
# `exit 0`s HERE; it does not need the downstream checks (glob-guard /
# sanctioned-dir / sanctioned-file / on-disk) — those are ALL pass-through
# branches a read never required. Only a Bash *write* fails this gate and falls
# through to the existing logic unchanged, so the gate can NEVER convert a pass
# into an `ask` nor remove the existing `ask`. File-tool payloads skip the gate
# entirely (IS_BASH unset) and reach the existing logic with current behavior
# preserved. Note: this runs BEFORE the glob-guard below — the glob-guard is
# simply not exercised for Bash reads (they exit here first).
#
# Detection is a positive write-VERB / kb-targeted-REDIRECT allowlist. Per the
# header philosophy (adversarial evasion + exotic write forms out of scope), this
# need not be exhaustive — it covers every write a human/agent realistically uses
# to create a new top-level kb entry, mirroring the verb family in
# no-memory-write.sh.
#   - KB_WRITE_VERB_RE: a write verb followed — WITHIN ONE pipeline/command
#     segment (`[^|;&<newline>]*`) — by a knowledge-base/ path. The segment bound
#     stops a verb in stage-1 from matching a kb READ in a later stage/line
#     (`... | grep ... ; cat knowledge-base/x`, or a verb on line 1 + a kb read on
#     line 3). The newline is part of the exclusion class (via `$'...'` so `\n` is
#     a literal newline char) — a multi-line command does not let a stage-1 verb
#     reach a later-line kb read.
#   - KB_WRITE_REDIR_RE: a `>`/`>>` redirect whose target is a knowledge-base/
#     path. It anchors the literal `knowledge-base/` immediately after the
#     `>`/spaces/optional-quote, so `>/dev/null 2>&1` (present in the repro) does
#     NOT match — a naive `>`-presence check would re-introduce the false positive.
# Both regexes MUST be assigned to variables before `[[ =~ ]]`: an inline literal
# containing `;`/`&`/`|` triggers a bash conditional-expression parse error.
if [[ -n "$IS_BASH" ]]; then
  KB_WRITE_VERB_RE=$'(mkdir|touch|tee|sed[[:space:]]+-i|cp|mv|install|ln|rsync|git[[:space:]]+add|git[[:space:]]+mv|git[[:space:]]+rm)[^|;&\n]*knowledge-base/'
  KB_WRITE_REDIR_RE='>>?[[:space:]]*"?'"'"'?knowledge-base/'
  if [[ ! "$TARGET" =~ $KB_WRITE_VERB_RE ]] && [[ ! "$TARGET" =~ $KB_WRITE_REDIR_RE ]]; then
    exit 0
  fi
fi

# Glob/regex-metachar guard: a SEGMENT containing `*`, `?`, `[`, or `]` is the
# signature of a COMMENT or grep/regex PATTERN that merely mentions a
# knowledge-base/<glob> path — NOT a real write target. The first-match scan
# (line 67) can land on `# ... knowledge-base/*.md ...` or
# `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'` before the genuine
# `git add knowledge-base/project/...` write, yielding a bogus SEGMENT
# (`*.md`, `[A-Za-z0-9`) that is neither sanctioned nor on disk → false-positive
# `ask`. Real KB segments (dir names like `project`, files like INDEX.md) never
# contain these chars, so genuine new-domain detection is unaffected. The
# bracket expression `['*?[]']` lists the four metacharacters as literal members
# (`]` via the `[]']` form so it is a member, not the closer); reuses the file's
# existing `[[ == ]]` glob idiom (below) — no subprocess, `set -euo pipefail`-safe.
if [[ "$SEGMENT" == *['*?[]']* ]]; then
  exit 0
fi

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
# emit_incident's event_type enum is {deny, bypass, applied, warn} (lib/incidents.sh);
# `warn` is the advisory/non-blocking class (the harness-facing decision below is
# still "ask"). `ask` is NOT a telemetry event_type and would be dropped from
# the aggregator's fire_count.
emit_incident kb-domain-allowlist-guard warn \
  "New top-level knowledge-base entry outside sanctioned domain set" "$TARGET"
# Reason-string dir/file lists are derived from the arrays above (single source of
# truth) so they cannot drift from SANCTIONED_DIRS/SANCTIONED_FILES.
jq -n --arg seg "$SEGMENT" --arg target "$TARGET" \
      --arg dirs "${SANCTIONED_DIRS[*]}" --arg files "${SANCTIONED_FILES[*]}" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("ADVISORY: kb-domain-allowlist-guard — this write introduces a NEW top-level entry under knowledge-base/ (`" + $seg + "`) that is not in the sanctioned domain set.\n\nTarget: " + $target + "\n\nSanctioned top-level dirs: " + $dirs + "\nSanctioned top-level files: " + $files + "\n\nIf this is intentional, confirm to proceed AND add the domain to .claude/hooks/kb-domain-allowlist-guard.sh + follow plugins/soleur/AGENTS.md \"Adding a New Domain\". Otherwise, place the artifact under an existing domain.")
  }
}'
exit 0
