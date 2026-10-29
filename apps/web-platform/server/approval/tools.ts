/**
 * Slice-1 approval tool set (#4672) and the Guard 2 census.
 *
 * `APPROVAL_REQUIRED_TOOLS` are the gated platform tools whose gate becomes a durable, action-bound approval
 * request (when the `approval-queue` flag is on). Every OTHER gated tool in `TOOL_TIER_MAP` must be listed in
 * `APPROVAL_EXEMPT_TOOLS` with a one-line reason, so a newly added gated tool cannot silently stay on the old
 * in-memory path: the census test (test/approval/tools-census.test.ts) fails until it is classified.
 *
 * Adding a gated tool: follow the checklist in ADR-307 § Adding a gated tool (it owns it; do not restate it here).
 *
 * This module is dependency-free on purpose: the migration shape test, the canonicalizer and the (later)
 * permission callback all import it.
 */

const P = "mcp__soleur_platform__";

export const APPROVAL_REQUIRED_TOOLS = [
  `${P}email_send`,
  `${P}email_reply`,
  `${P}email_suppress`,
  `${P}github_push_branch`,
  `${P}create_pull_request`,
  `${P}github_trigger_workflow`,
  `${P}kb_share_create`,
  `${P}workspace_set_autonomous`,
] as const;

export type ApprovalToolName = (typeof APPROVAL_REQUIRED_TOOLS)[number];

const REQUIRED = new Set<string>(APPROVAL_REQUIRED_TOOLS);

export function isApprovalRequiredTool(toolName: string): toolName is ApprovalToolName {
  return REQUIRED.has(toolName);
}

const SLICE2 = "stays on the in-memory review gate in slice 1; candidate for a later slice";

/** Gated tools that deliberately stay on the existing in-memory review gate in slice 1, each with its reason. */
export const APPROVAL_EXEMPT_TOOLS: Readonly<Record<string, string>> = {
  [`${P}create_issue`]: `files an issue only, reversible by closing it; ${SLICE2}`,
  [`${P}kb_share_revoke`]: `revocation reduces exposure and is idempotent; ${SLICE2}`,
  [`${P}routine_run`]: `starts a registered routine the user already configured; ${SLICE2}`,
  [`${P}workstream_issue_create`]: `GitHub issue write through the audited accessor; ${SLICE2}`,
  [`${P}workstream_issue_set_status`]: `GitHub issue write through the audited accessor; ${SLICE2}`,
  [`${P}workstream_issue_update_title`]: `GitHub issue write through the audited accessor; ${SLICE2}`,
  [`${P}workstream_issue_update_fields`]: `GitHub issue write through the audited accessor; ${SLICE2}`,
  [`${P}workstream_issue_close`]: `GitHub issue write through the audited accessor, reversible by reopening; ${SLICE2}`,
  [`${P}crm_contact_upsert`]: `writes the founder's own CRM rows under the auth.uid()-pinned RPC; ${SLICE2}`,
  [`${P}crm_note_append`]: `writes the founder's own CRM rows under the auth.uid()-pinned RPC; ${SLICE2}`,
  [`${P}crm_contact_set_stage`]: `writes the founder's own CRM rows under the auth.uid()-pinned RPC; ${SLICE2}`,
  [`${P}plausible_create_site`]: `uses the user's own account-wide analytics key; credential-broker work (#9543) decides its gate`,
  [`${P}plausible_add_goal`]: `uses the user's own account-wide analytics key; credential-broker work (#9543) decides its gate`,
  [`${P}plausible_get_stats`]: `read-only against the user's own analytics key; credential-broker work (#9543) decides its gate`,
  [`${P}account_export_enqueue`]: `account data export is already a signed-in, user-initiated flow; ${SLICE2}`,
  [`${P}account_delete_initiate`]: `account deletion has its own typed confirmation flow; ${SLICE2}`,
};

export interface GatedToolCensus {
  /** Every tool whose tier is `gated` in the map. */
  gated: string[];
  /** Gated, but neither required nor exempt: a new tool nobody decided about. */
  unclassified: string[];
  /** Exempt entries whose reason is empty or blank. */
  emptyReason: string[];
  /** Both required and exempt. */
  doubleClassified: string[];
  /** Exempt entries that are no longer gated in the map (stale). */
  staleExempt: string[];
}

/**
 * Guard 2: classify every `gated` entry of a tier map. Throws when the census is vacuous (no gated tool, or an
 * empty required set): a census that checks zero tools must be red, not green.
 */
export function classifyGatedTools(
  tierMap: Readonly<Record<string, string>>,
  required: ReadonlyArray<string>,
  exempt: Readonly<Record<string, string>>,
): GatedToolCensus {
  const gated = Object.keys(tierMap).filter((k) => tierMap[k] === "gated");
  if (gated.length === 0 || required.length === 0) {
    throw new Error("approval tool census is vacuous: no gated tools or no required tools were enumerated");
  }
  const req = new Set(required);
  const gatedSet = new Set(gated);
  return {
    gated,
    unclassified: gated.filter((t) => !req.has(t) && !Object.hasOwn(exempt, t)),
    emptyReason: Object.keys(exempt).filter((t) => exempt[t].trim().length === 0),
    doubleClassified: Object.keys(exempt).filter((t) => req.has(t)),
    staleExempt: Object.keys(exempt).filter((t) => !gatedSet.has(t)),
  };
}
