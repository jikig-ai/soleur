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
# Pinned against security_reminder_hook.py's inline dict AND the plugin copy
# (plugins/soleur/hooks/lib/hook-tool-kind.sh) by hook-tool-kind.test.sh's
# drift guard — update all three or none.
#
# multi_edit, notebook_edit and apply_patch are PROBED-ABSENT from Devin's
# tool vocabulary (envelope-capture §7, 2026-09-15) — the arms are speculative
# passthroughs so the `.devin` write-class matcher `^(edit|multi_edit|
# notebook_edit)$` keeps its intended shape if Devin ships them. If they
# activate on a real tool, their payload shape is unmeasured — re-probe before
# relying on body-gate coverage there.
#
# Source discipline is deliberately asymmetric: hook-input.sh sources this
# file FAIL-HARD (a missing lib kills the hook loudly), while own-jq hooks —
# incl. the plugin copies, which run in arbitrary projects where an install
# may be partial — source it FAIL-SOFT with an identity-stub fallback. The
# trade-off: a broken plugin install degrades a kind-gated hook to pre-#8205
# raw-name behavior (a dead gate under Devin) rather than erroring on every
# dispatch. That is the lesser evil for an optional plugin, but it is a known
# silent-off path — `hook_parse_input`'s `declare -f` guard does NOT extend to
# own-jq call sites.

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
