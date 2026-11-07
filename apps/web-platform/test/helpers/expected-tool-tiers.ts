/**
 * The expected tier of EVERY platform MCP tool, written out by hand (#11303).
 *
 * This table is deliberately NOT derived from `TOOL_TIER_MAP`: a test that builds its expectation from the map it is
 * checking passes when the map is edited. Flipping a tool between `gated` and `auto-approve` therefore needs a second,
 * visible edit here, which is what a reviewer sees in the diff. Keyed by short tool name (no `mcp__soleur_platform__`).
 */
export const PLATFORM_PREFIX = "mcp__soleur_platform__";

export const EXPECTED_AUTO_APPROVE: readonly string[] = [
  "edit_c4_diagram",
  "github_read_ci_status",
  "github_read_workflow_logs",
  "github_read_issue",
  "github_read_issue_comments",
  "github_read_pr",
  "github_list_pr_comments",
  "kb_share_list",
  "kb_share_preview",
  "auth_revocation_status",
  "workspace_get_autonomous",
  "email_triage_list",
  "email_triage_get",
  "inbox_list",
  "routines_list",
  "routine_runs_list",
  "workstream_issues_list",
  "workstream_issue_options",
  "crm_contact_list",
  "crm_contact_get",
  "crm_note_list",
  "crm_stage_transitions_list",
  "narrate",
  "summarize",
  "conversations_lookup",
];

export const EXPECTED_GATED: readonly string[] = [
  "github_trigger_workflow",
  "github_push_branch",
  "create_pull_request",
  "create_issue",
  "kb_share_create",
  "kb_share_revoke",
  "workspace_set_autonomous",
  "routine_run",
  "workstream_issue_create",
  "workstream_issue_set_status",
  "workstream_issue_update_title",
  "workstream_issue_update_fields",
  "workstream_issue_close",
  "email_send",
  "email_reply",
  "email_suppress",
  "crm_contact_upsert",
  "crm_note_append",
  "crm_contact_set_stage",
  "plausible_create_site",
  "plausible_add_goal",
  "plausible_get_stats",
  "account_export_enqueue",
  "account_delete_initiate",
];

/** FQN -> tier, for every tool in the two lists above. */
export const EXPECTED_TOOL_TIERS: Readonly<Record<string, "auto-approve" | "gated">> = Object.freeze({
  ...Object.fromEntries(EXPECTED_AUTO_APPROVE.map((n) => [`${PLATFORM_PREFIX}${n}`, "auto-approve" as const])),
  ...Object.fromEntries(EXPECTED_GATED.map((n) => [`${PLATFORM_PREFIX}${n}`, "gated" as const])),
});
