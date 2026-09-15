#!/usr/bin/env bash
# Canonical Devin→Claude tool-kind map (issue #8205).
#
# Devin's wire tool names are lowercase (exec, write, edit, …); hook bodies
# gate on the Claude-canonical kind name (Bash, Write, Edit, …). One function
# consumed two ways:
#
#   * lib/hook-input.sh sources this file and exports HOOK_TOOL_KIND as a
#     sibling of HOOK_TOOL_NAME (the raw name stays byte-exact — A17).
#   * Hooks that own their own jq parse source this file directly and map
#     their locally-extracted tool name.
#
# The map targets the INTERNAL name bodies compare against, not the registry
# matcher token: agent-token-tee.sh gates on `!= "Agent"` — the wire name —
# even though its matcher is `Task`, so run_subagent→Agent here.
#
# bash 3.2 + jq 1.5 compatible: a `case`, not an associative array.
# Measured Devin tool vocabulary: knowledge-base/project/specs/
# feat-settings-matcher-devin-audit/envelope-capture.md §7.
#
# Pinned against security_reminder_hook.py's inline dict by
# hook-tool-kind.test.sh's drift guard — update both or neither.

hook_tool_kind() {
  case "${1-}" in
    exec)              printf '%s\n' "Bash" ;;
    write)             printf '%s\n' "Write" ;;
    edit)              printf '%s\n' "Edit" ;;
    multi_edit)        printf '%s\n' "MultiEdit" ;;
    notebook_edit)     printf '%s\n' "NotebookEdit" ;;
    apply_patch)       printf '%s\n' "Write" ;;
    ask_user_question) printf '%s\n' "AskUserQuestion" ;;
    run_subagent)      printf '%s\n' "Agent" ;;
    skill)             printf '%s\n' "Skill" ;;
    *)                 printf '%s\n' "${1-}" ;;
  esac
}
