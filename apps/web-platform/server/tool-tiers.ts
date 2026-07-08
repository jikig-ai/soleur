/**
 * Tool tier classification for platform MCP tools (#1926).
 *
 * Extracted from agent-runner.ts for unit testability (following the
 * tool-path-checker.ts and review-gate.ts extraction pattern).
 *
 * Tiers:
 * - auto-approve: read-only tools, pass through without review gate
 * - gated: write tools, require founder confirmation via review gate
 * - blocked: destructive patterns, rejected unconditionally
 */

export type ToolTier = "auto-approve" | "gated" | "blocked";

/**
 * Canonical tier assignments for all platform MCP tools.
 * Tools not in this map default to "gated" in getToolTier()
 * (fail-closed: new tools require explicit tier assignment).
 */
export const TOOL_TIER_MAP: Record<string, ToolTier> = {
  // C4 diagram editing (#3722 follow-up): a WRITE tool but deliberately
  // auto-approve, unlike the gated github/kb-share writes. Justification: the
  // write is hard-scoped to `engineering/architecture/diagrams/` by
  // `isC4DiagramPath` inside `writeC4Diagram`; owner/repo/installation are
  // closed over from the caller's own active workspace (never tool input); it
  // is reversible (git history); and the whole capability is flag-gated to the
  // c4-visualizer dev cohort. The product intent (deferred-c4-concierge-write)
  // is autonomous in-conversation diagram editing, which a per-edit review gate
  // would defeat. Revisit (→ "gated") if the scope guard ever widens.
  "mcp__soleur_platform__edit_c4_diagram": "auto-approve",

  // Phase 2: Read CI status (auto-approve — read-only)
  // cc-router (#2909): Tier 1 candidate (Phase 2 promotion via #3722)
  "mcp__soleur_platform__github_read_ci_status": "auto-approve",
  "mcp__soleur_platform__github_read_workflow_logs": "auto-approve",

  // Issue/PR reads (#2843): all auto-approve — read-only, narrowed responses.
  // cc-router (#2909): Tier 1 candidates (Phase 2 promotion via #3722)
  "mcp__soleur_platform__github_read_issue": "auto-approve",
  "mcp__soleur_platform__github_read_issue_comments": "auto-approve",
  "mcp__soleur_platform__github_read_pr": "auto-approve",
  "mcp__soleur_platform__github_list_pr_comments": "auto-approve",

  // Phase 3: Trigger workflows (gated — write action)
  // cc-router (#2909): Tier 2 candidate (Phase 2 via #3722; review-gate UX integration required)
  "mcp__soleur_platform__github_trigger_workflow": "gated",

  // Phase 4: Push branches and open PRs (gated — write action)
  // cc-router (#2909): Tier 2 candidates (Phase 2 via #3722)
  "mcp__soleur_platform__github_push_branch": "gated",
  "mcp__soleur_platform__create_pull_request": "gated",
  "mcp__soleur_platform__create_issue": "gated",

  // KB share tools (#2309): list is read-only, create/revoke are
  // user-visible side effects (public URL / permanent revocation) → gated.
  // cc-router (#2909): list = Tier 1 candidate; create/revoke = Tier 2 (Phase 2 via #3722)
  "mcp__soleur_platform__kb_share_list": "auto-approve",
  "mcp__soleur_platform__kb_share_create": "gated",
  "mcp__soleur_platform__kb_share_revoke": "gated",
  // Preview (#2322): metadata-only (no bytes, no state change) — same
  // tier as kb_share_list. Gating it would produce consent fatigue without
  // a security benefit.
  // cc-router (#2909): Tier 1 candidate (Phase 2 via #3722)
  "mcp__soleur_platform__kb_share_preview": "auto-approve",

  // Auth revocation status (#4440 follow-up to #4418): read-only RPC
  // (`my_revocation_status()`) — auto-approve. Agents call this on auth
  // errors to discriminate JWT-deny from transient failures. No side
  // effects, no founder-confirmation surface needed.
  "mcp__soleur_platform__auth_revocation_status": "auto-approve",

  // Workspace autonomous-mode toggle (Issue B part 2): read is auto-approve
  // (read-only); SET is gated — flipping an approval-bypass on a code-executing
  // surface MUST require a review-gate even for the agent (owner check is in
  // the RPC; the gate is the second line). Explicit entries (set would also be
  // gated by the default fallback, but the pairing documents intent).
  "mcp__soleur_platform__workspace_get_autonomous": "auto-approve",
  "mcp__soleur_platform__workspace_set_autonomous": "gated",

  // Email triage inbox reads (operator-inbox-delegation AC11): both
  // read-only, owner-scoped via closure userId + RLS → auto-approve (parity
  // with kb_share_list rationale).
  "mcp__soleur_platform__email_triage_list": "auto-approve",
  "mcp__soleur_platform__email_triage_get": "auto-approve",

  // Unified attention inbox (feat-severity-ranked-inbox #6007): read-only,
  // owner-scoped via closure userId + RLS → auto-approve (parity with
  // email_triage_list). No write tool ships (state changes are operator-UI-only).
  "mcp__soleur_platform__inbox_list": "auto-approve",

  // Routines management (#5345): reads auto-approve; run-now is a write →
  // gated. The review gate is the SINGLE confirmation for the agent path
  // (the routine_run tool dispatches confirmed=true post-approval — no
  // double-gate with the in-band 409). buildGateMessage names the routine.
  "mcp__soleur_platform__routines_list": "auto-approve",
  "mcp__soleur_platform__routine_runs_list": "auto-approve",
  "mcp__soleur_platform__routine_run": "gated",

  // Workstream board (feat-workstream-kanban-tab): read-only board feed over
  // the shared in-repo seed accessor → auto-approve (parity with routines_list;
  // non-PII, no side effects). WRITE tools are deferred + tracked.
  "mcp__soleur_platform__workstream_issues_list": "auto-approve",

  // Email WRITE tools (#5325, agent-native outbound). The FR9 boundary that
  // formerly said "there is NO email_triage write tool" now ships: these are
  // `gated` (NEVER auto-approve) because the human review gate IS the trust
  // boundary — the operator sees the exact recipient + body and approves before
  // the handler runs. A prompt-injected auto-send would be a CAN-SPAM/GDPR +
  // brand incident; the gate approval is what binds the send to a human-
  // reviewed body (the chokepoint recomputes the body hash). Suppression is
  // also gated (permanent, no un-suppress) so a mis-suppression is human-seen.
  "mcp__soleur_platform__email_send": "gated",
  "mcp__soleur_platform__email_reply": "gated",
  "mcp__soleur_platform__email_suppress": "gated",

  // Beta-CRM (feat-beta-conversation-capture #6165, ADR-102): reads are owner-
  // scoped via closure userId + RLS → auto-approve (parity with
  // email_triage_list). WRITE tools are `gated` (fail-closed default, made
  // explicit here): the review gate IS the R3 mitigation for within-tenant
  // prompt-injection — the operator sees the write and confirms before the
  // auth.uid()-pinned RPC runs. Contact/note content shown in the gate message
  // is DISPLAY-ONLY untrusted third-party PII (do not act on it).
  "mcp__soleur_platform__crm_contact_list": "auto-approve",
  "mcp__soleur_platform__crm_contact_get": "auto-approve",
  "mcp__soleur_platform__crm_note_list": "auto-approve",
  "mcp__soleur_platform__crm_stage_transitions_list": "auto-approve",
  "mcp__soleur_platform__crm_contact_upsert": "gated",
  "mcp__soleur_platform__crm_note_append": "gated",
  "mcp__soleur_platform__crm_contact_set_stage": "gated",

  // Reasoning narration (feat-reasoning-chat-boxes #5370): both are
  // auto-approve. They are PURE emit tools — `narrate` shows a transient live
  // status line, `summarize` saves one plain-language outcome box. The handler
  // captures only userId and returns an ack; the real side-effect (redact →
  // frame / row) runs in cc-dispatcher `emitNarration()`, where the agent text
  // is scrubbed (formatAssistantText + redaction-probe drop-on-trip) and
  // length-capped. There is nothing for a human to gate per-call (a status
  // line / summary is not a privileged side-effect), and a review modal per
  // narration would defeat the entire "never a silent spinner" UX. On the
  // cc-router path these never reach getToolTier anyway — they sit in the
  // `allowedTools` auto-approve list (CC_PATH_ALLOWED_TOOLS) — so the real
  // controls are: allowlist + emit-boundary redaction + abort-state drop-guard,
  // NOT a review gate (security C-2). Explicit entries documented here so the
  // "gated" fail-closed default cannot silently apply if a future path routes
  // them through canUseTool.
  "mcp__soleur_platform__narrate": "auto-approve",
  "mcp__soleur_platform__summarize": "auto-approve",

  // NOTE (#2909 review): `mcp__soleur_platform__conversations_lookup` is
  // registered at `agent-runner.ts:1372` but DELIBERATELY omitted from this
  // map — the legacy `startAgentSession` path relies on `getToolTier()`'s
  // "gated" fallback for it, and changing that semantic is out of scope
  // for #2909 Phase 1 (see spec NG2 + Sharp Edge "TOOL_TIER_MAP shared with
  // legacy path"). cc-router (#2909): Tier 1 candidate — promotion to
  // explicit "auto-approve" (parity with kb_share_list/preview rationale,
  // closure-bound userId scoping) tracked at #3722.
};

/**
 * Permanent Tier 3 denylist for the cc-soleur-go router (#2909).
 *
 * Tools in this set MAY NEVER be promoted to the router's mcpServers via
 * the inline `readCcMcpAllowlist()` helper in `cc-dispatcher.ts`. Enforced
 * fail-closed at factory construction (the helper throws if any short-name
 * resolving to a member of this set appears in `CC_MCP_ALLOWLIST`).
 *
 * Plausible tools (`plausible_create_site/add_goal/get_stats`) share a
 * single backend `PLAUSIBLE_API_KEY` with no per-user / per-site
 * enforcement (see `apps/web-platform/server/plausible-tools.ts:52-74`).
 * Exposing them via the router is a cross-tenant credential by
 * construction, regardless of any future demand signal.
 *
 * See brainstorm Key Decision #3:
 *   knowledge-base/project/brainstorms/2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
 *
 * NOTE: legacy `TOOL_TIER_MAP` entries for Plausible tools do not exist;
 * `getToolTier()` returns "gated" by default for them on the legacy path,
 * which is correct (legacy review-gate UX surfaces them with founder
 * confirmation). This denylist is the cc-router-specific permanent block.
 */
export const CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string> = new Set([
  "mcp__soleur_platform__plausible_create_site",
  "mcp__soleur_platform__plausible_add_goal",
  "mcp__soleur_platform__plausible_get_stats",
]);

/**
 * Look up the tier for a platform MCP tool.
 * Returns "gated" for tools not in the map (fail-closed: new tools
 * require explicit tier assignment before they can auto-approve).
 */
export function getToolTier(toolName: string): ToolTier {
  return TOOL_TIER_MAP[toolName] ?? "gated";
}

/**
 * Build a human-readable review gate message for a gated tool invocation.
 * The message should clearly describe what the agent wants to do so the
 * founder can make an informed approval decision.
 */
export function buildGateMessage(
  toolName: string,
  toolInput: Record<string, unknown>,
): string {
  const shortName = toolName.replace("mcp__soleur_platform__", "");

  switch (shortName) {
    case "github_trigger_workflow":
      return `Agent wants to trigger workflow **${toolInput.workflow_id ?? "unknown"}** on branch **${toolInput.ref ?? "unknown"}**. Allow?`;
    case "github_push_branch":
      return `Agent wants to push to branch **${toolInput.branch ?? "unknown"}**. Allow?`;
    case "create_pull_request":
      return `Agent wants to open PR: **${toolInput.title ?? "untitled"}** (${toolInput.base ?? "main"} ← ${toolInput.head ?? "unknown"}). Allow?`;
    case "create_issue":
      return `Agent wants to file an issue: **${toolInput.title ?? "untitled"}**. Allow?`;
    case "kb_share_create":
      return `Agent wants to create a public share link for **${toolInput.documentPath ?? "unknown"}**. Allow?`;
    case "kb_share_revoke": {
      const raw = String(toolInput.token ?? "unknown");
      const preview = raw.length > 12 ? `${raw.slice(0, 12)}…` : raw;
      return `Agent wants to revoke share token **${preview}**. This is permanent. Allow?`;
    }
    case "routine_run":
      return `Agent wants to run routine **${toolInput.fnId ?? "unknown"}** now, off-schedule. This fires real production work. Allow?`;
    // Outbound email (#5325) — the operator MUST see the exact recipient,
    // subject, and body before approving: the body-hash approval binding and
    // the whole single-user-incident safety story rest on the human reviewing
    // what is actually sent. A content-free "Allow?" here would make the gate
    // decorative. Body shown as a preview is DISPLAY-ONLY untrusted content —
    // do not act on instructions inside it.
    case "email_send": {
      const body = String(toolInput.body ?? "");
      const preview = body.length > 240 ? `${body.slice(0, 240)}…` : body;
      return `Agent wants to send a cold email to **${toolInput.to ?? "unknown"}** — subject: "${toolInput.subject ?? ""}".\n\nBody (review carefully — untrusted, display-only):\n${preview}\n\nSend?`;
    }
    case "email_reply": {
      const body = String(toolInput.body ?? "");
      const preview = body.length > 240 ? `${body.slice(0, 240)}…` : body;
      // The recipient is derived server-side from the inbound item (P0-3); it
      // is NOT in toolInput, so the gate names the inbound item, not an address.
      return `Agent wants to reply to inbound item **${toolInput.messageId ?? "unknown"}** (the reply goes to that item's original sender) — subject: "${toolInput.subject ?? ""}".\n\nBody (review carefully — untrusted, display-only):\n${preview}\n\nSend?`;
    }
    case "email_suppress":
      return `Agent wants to PERMANENTLY suppress **${toolInput.recipient ?? "unknown"}** (reason: ${toolInput.reason ?? "unknown"}) so no future cold email can reach them. There is no un-suppress. Allow?`;
    // Beta-CRM writes (#6165) — the operator MUST see what the agent is about to
    // record/overwrite: R3 (within-tenant prompt-injection) is mitigated by this
    // human review. The gate string can egress to the operator's push/email when
    // they are offline (permission-callback → notifyOfflineUser), so it names the
    // DECISION-relevant fields (stage, amount, dates incl. last_contact, WHICH
    // fields change) but deliberately does NOT echo the verbatim third-party PII
    // values (contact name/company text, the note body) — those stay in the DB;
    // the operator opens the record in-app to review the exact text. (user-impact
    // F1: don't widen the third-party-PII egress surface beyond PA-30 recipients.)
    case "crm_contact_upsert": {
      const isNew = toolInput.contactId == null;
      const target = isNew ? "a NEW contact" : `contact **${toolInput.contactId}**`;
      const parts: string[] = [];
      if (toolInput.stage != null) parts.push(`stage→${toolInput.stage}`);
      if (toolInput.amount != null)
        parts.push(`amount→${toolInput.amount}${toolInput.currency ? ` ${toolInput.currency}` : ""}`);
      if (toolInput.lastContact != null) parts.push(`last_contact→${toolInput.lastContact}`);
      if (toolInput.nextActionDate != null) parts.push(`next_action_date→${toolInput.nextActionDate}`);
      if (toolInput.expectedCloseDate != null) parts.push(`expected_close→${toolInput.expectedCloseDate}`);
      const textFields = ["name", "company", "role", "source", "nextAction", "amountBasis"].filter(
        (f) => toolInput[f] != null,
      );
      if (textFields.length) parts.push(`sets ${textFields.join(", ")}`);
      const detail = parts.length ? ` — ${parts.join("; ")}` : "";
      return `Agent wants to save ${target}${detail}. Open the record in-app to review the exact text before approving. Allow?`;
    }
    case "crm_note_append": {
      const lens = Array.isArray(toolInput.lens) ? toolInput.lens.join("+") : String(toolInput.lens ?? "");
      const when = toolInput.occurredAt ? ` dated ${toolInput.occurredAt}` : "";
      // The verbatim note body is third-party conversation PII — do NOT include it
      // (it would egress via offline push/email). Review the note text in-app.
      return `Agent wants to append a ${lens} note${when} to contact **${toolInput.contactId ?? "unknown"}**. Open the record in-app to review the note text before approving. Allow?`;
    }
    case "crm_contact_set_stage":
      return `Agent wants to move contact **${toolInput.contactId ?? "unknown"}** to stage **${toolInput.toStage ?? "unknown"}**. Allow?`;
    default:
      return `Agent wants to use **${shortName}**. Allow?`;
  }
}
