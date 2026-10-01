#!/usr/bin/env bash
# Canonical Devin→Claude tool-kind map (issue #8205) — PLUGIN COPY.
#
# Plugin hooks run in projects that may not carry this repo's
# .claude/hooks/lib/, so the map is duplicated here. Pinned against the
# canonical map by .claude/hooks/hook-tool-kind.test.sh — update both or
# neither. multi_edit/notebook_edit/apply_patch are probed-absent from Devin's
# vocabulary (envelope-capture §7) — speculative passthroughs; re-probe before
# relying on them.

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
