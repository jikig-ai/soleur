/**
 * Approval card view model (#4672). Built ONLY from the canonical object (canonical.ts), the same object that is
 * hashed, so what the Owner reads cannot disagree with what is consumed (P6, Guard 1 mutation row 6). The function
 * takes one argument on purpose: no tool input, no preview text, no model prose can reach the card.
 *
 * Copy follows the operator-approved wireframe delta (knowledge-base/product/design/approvals, copy deck section C):
 * fixed verb phrases, fixed "Approve" label, a consequence line that says what the agent CAN do once released and
 * never claims an outcome. No value is truncated (a card never shows "+N more").
 */

import type { CanonicalAction, CanonicalValue } from "./canonical";
import type { ApprovalToolName } from "./tools";

export interface ApprovalViewRow {
  label: string;
  value: string;
  /** `block` = long free text (scrolls inside the card, never ellipsised); `code` = identifier-like. */
  kind: "text" | "code" | "block";
}

export interface ApprovalView {
  tool: ApprovalToolName;
  /** Card title: "Your agent wants to {verb phrase}". */
  title: string;
  verbPhrase: string;
  fields: ApprovalViewRow[];
  consequence: string;
  /** "One-time . this exact {noun}". */
  singleUse: string;
  approveLabel: "Approve";
  denyLabel: "Deny";
  /** Workspace autonomy changes what every future approval looks like: danger-tinted card. */
  danger: boolean;
}

/** Fixed strings other surfaces (card states, agent messages) reuse; asserted outcome-free by the copy test. */
export const APPROVAL_COPY = {
  approve: "Approve",
  deny: "Deny",
  releasedBadge: "Released to your agent",
  releasedTitle: "Released, your agent is continuing",
  approvedLate: "Approved. Ask your agent again.",
  expiredUnanswered: "This request expired. Nothing was run.",
  approvedNeverAsked: "You approved this, but your agent never asked again",
  resolvedNothing: "Nothing was run. Saved for your agent. Asking again with the same arguments is allowed.",
  newerRequestBanner: "A newer request from your agent exists",
  nonOwnerWaiting: "Waiting for the workspace Owner",
  conversationClosed: "This conversation is closed",
  detailsRemoved: "Details removed per retention policy",
  pendingSubline: (minutes: number) => `Your agent stopped waiting after ${minutes} minutes`,
  requestCount: (n: number) => `The agent asked again, request ${n}`,
  alreadyDecided: (name: string, role: string) => `Already decided by ${name} (${role})`,
} as const;

interface Phrase {
  verb: string;
  noun: string;
  extra?: string;
}

const PHRASES: Record<ApprovalToolName, Phrase> = {
  mcp__soleur_platform__email_send: { verb: "send this email", noun: "email" },
  mcp__soleur_platform__email_reply: { verb: "send this reply", noun: "email" },
  mcp__soleur_platform__email_suppress: { verb: "block this address", noun: "address" },
  mcp__soleur_platform__github_push_branch: { verb: "push these commits", noun: "commits" },
  mcp__soleur_platform__create_pull_request: {
    verb: "open this pull request",
    noun: "pull request",
    extra: "Nothing is merged by this approval.",
  },
  mcp__soleur_platform__github_trigger_workflow: { verb: "start this workflow", noun: "workflow run" },
  mcp__soleur_platform__kb_share_create: {
    verb: "create this link",
    noun: "link",
    extra: "Anyone who gets the link could read this document without signing in.",
  },
  mcp__soleur_platform__workspace_set_autonomous: {
    verb: "switch this setting",
    noun: "setting",
    extra: "Once switched on, agents here stop asking you before they act on supported actions.",
  },
};

const str = (v: CanonicalValue | undefined): string => (typeof v === "string" ? v : v === undefined || v === null ? "" : String(v));

function row(label: string, value: string, kind: ApprovalViewRow["kind"] = "text"): ApprovalViewRow {
  return { label, value, kind };
}

function optionalRows(f: { [k: string]: CanonicalValue }): ApprovalViewRow[] {
  const rows: ApprovalViewRow[] = [row("JURISDICTION", str(f.jurisdiction), "code")];
  if (typeof f.postalAddress === "string") rows.push(row("POSTAL ADDRESS", f.postalAddress, "block"));
  if (typeof f.optOut === "string") rows.push(row("OPT-OUT LINE", f.optOut, "block"));
  if (typeof f.ftcDisclosure === "string") rows.push(row("FTC DISCLOSURE", f.ftcDisclosure, "block"));
  const a = f.art14;
  if (a && typeof a === "object" && !Array.isArray(a)) {
    const labels: Array<[string, string]> = [
      ["identity", "ART. 14 IDENTITY"],
      ["purpose", "ART. 14 PURPOSE"],
      ["legalBasis", "ART. 14 LEGAL BASIS"],
      ["dataSource", "ART. 14 DATA SOURCE"],
      ["retention", "ART. 14 RETENTION"],
      ["rights", "ART. 14 RIGHTS"],
    ];
    for (const [key, label] of labels) {
      const v = (a as { [k: string]: CanonicalValue })[key];
      if (typeof v === "string") rows.push(row(label, v, "block"));
    }
  }
  return rows;
}

function fieldRows(action: CanonicalAction): ApprovalViewRow[] {
  const f = action.fields;
  switch (action.tool) {
    case "mcp__soleur_platform__email_send":
      return [
        row("TO", str(f.to), "code"),
        ...(typeof f.replyTo === "string" ? [row("REPLY-TO", f.replyTo, "code")] : []),
        row("SUBJECT", str(f.subject)),
        row("BODY", str(f.body), "block"),
        ...optionalRows(f),
      ];
    case "mcp__soleur_platform__email_reply":
      return [
        row("IN REPLY TO", str(f.messageId), "code"),
        row("TO", str(f.recipient), "code"),
        row("SUBJECT", str(f.subject)),
        row("BODY", str(f.body), "block"),
        ...optionalRows(f),
      ];
    case "mcp__soleur_platform__email_suppress":
      return [
        row("ADDRESS", str(f.recipient), "code"),
        row("REASON", str(f.reason), "code"),
        row("APPLIES TO", "Every agent and every email in this workspace"),
        row("EFFECT", "Agents cannot email this address until the block is removed"),
      ];
    case "mcp__soleur_platform__github_push_branch":
      return [
        row("REPOSITORY", str(f.repo), "code"),
        row("BRANCH", str(f.branch), "code"),
        row("COMMIT", str(f.headSha), "code"),
        row("FORCE PUSH", f.force === true ? "Yes, overwrites the remote branch" : "No"),
      ];
    case "mcp__soleur_platform__create_pull_request":
      return [
        row("REPOSITORY", str(f.repo), "code"),
        row("FROM", str(f.head), "code"),
        row("INTO", str(f.base), "code"),
        row("TITLE", str(f.title)),
        row("DESCRIPTION", typeof f.body === "string" ? f.body : "(none)", "block"),
      ];
    case "mcp__soleur_platform__github_trigger_workflow": {
      const inputs = f.inputs && typeof f.inputs === "object" && !Array.isArray(f.inputs) ? (f.inputs as { [k: string]: CanonicalValue }) : null;
      const lines = inputs ? Object.keys(inputs).sort().map((k) => `${k} = ${str(inputs[k])}`) : [];
      return [
        row("REPOSITORY", str(f.repo), "code"),
        row("WORKFLOW ID", str(f.workflow_id), "code"),
        row("ON REF", str(f.ref), "code"),
        row("INPUTS", lines.length > 0 ? lines.join("\n") : "(none)", "block"),
      ];
    }
    case "mcp__soleur_platform__kb_share_create":
      return [
        row("DOCUMENT", str(f.documentPath), "code"),
        row("VISIBLE TO", "Anyone with the link, no sign-in needed"),
        row("ACCESS", "Read only"),
        row("LINK EXPIRES", "Never"),
      ];
    case "mcp__soleur_platform__workspace_set_autonomous":
      return [
        row("SETTING", f.value === true ? "Agent approval: Ask first → Autonomous" : "Agent approval: Autonomous → Ask first"),
        row("APPLIES TO", "All agents, all members, all connected accounts"),
      ];
  }
}

export function renderApprovalView(action: CanonicalAction): ApprovalView {
  const phrase = PHRASES[action.tool];
  const base = `Your agent can ${phrase.verb} once, if you ask it to try again. Valid in this conversation only.`;
  // The autonomy extra only applies to switching ON; switching OFF restores the ask-first behaviour.
  const extra =
    action.tool === "mcp__soleur_platform__workspace_set_autonomous" && action.fields.value !== true
      ? "Once switched, agents here ask you before they act on supported actions."
      : phrase.extra;
  return {
    tool: action.tool,
    title: `Your agent wants to ${phrase.verb}`,
    verbPhrase: phrase.verb,
    fields: fieldRows(action),
    consequence: extra ? `${base} ${extra}` : base,
    singleUse: `One-time · this exact ${phrase.noun}`,
    approveLabel: "Approve",
    denyLabel: "Deny",
    danger: action.tool === "mcp__soleur_platform__workspace_set_autonomous",
  };
}
