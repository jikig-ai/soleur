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
import { APPROVAL_COPY, AUTONOMOUS_CARD_COPY_PROVISIONAL as AUTONOMOUS } from "@/lib/approval-copy";
import { revealInvisible } from "@/lib/approval-card-state";

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
  /**
   * "One-time · this exact {noun}" only where every part of the noun is bound by the hash (or pinned by the execution
   * grant); otherwise it names just what IS bound (see `Phrase.bound`).
   */
  singleUse: string;
  /** The request as one noun ("email", "commits"); the card's titles read it instead of parsing `singleUse`. */
  noun: string;
  approveLabel: "Approve";
  denyLabel: "Deny";
  /** Workspace autonomy changes what every future approval looks like: danger-tinted card. */
  danger: boolean;
}

interface Phrase {
  verb: string;
  noun: string;
  /**
   * What the single-use line names when "this exact {noun}" would claim more than is bound: the approval binds
   * identifiers (a path, branch names, a workflow id and ref), not the content a handler re-reads at execution
   * (CTO ruling 1, CLO ruling 5). Absent = the noun is fully bound.
   */
  bound?: string;
  extra?: string;
}

const PHRASES: Record<ApprovalToolName, Phrase> = {
  mcp__soleur_platform__email_send: { verb: "send this email", noun: "email" },
  mcp__soleur_platform__email_reply: { verb: "send this reply", noun: "email" },
  mcp__soleur_platform__email_suppress: { verb: "block this address", noun: "address" },
  // The commit is pinned: the push executes exactly the commit shown (grants.ts), whatever HEAD does while the card waits.
  mcp__soleur_platform__github_push_branch: { verb: "push these commits", noun: "commits", bound: "this exact commit" },
  mcp__soleur_platform__create_pull_request: {
    verb: "open this pull request",
    noun: "pull request",
    bound: "these two branch names",
    extra: "Nothing is merged by this approval. Opens a pull request between these branches. The changes on the branch were approved when they were pushed, not here.",
  },
  mcp__soleur_platform__github_trigger_workflow: {
    verb: "start this workflow",
    noun: "workflow run",
    bound: "this workflow and ref",
    extra: "Runs the workflow as it exists on this branch or tag when it starts.",
  },
  mcp__soleur_platform__kb_share_create: {
    verb: "create this link",
    noun: "link",
    bound: "this document path",
    extra:
      "Anyone who gets the link could read this document without signing in. Creates a public link to this file as it is when your agent creates the link. The file's contents are not shown here.",
  },
  mcp__soleur_platform__workspace_set_autonomous: {
    verb: "switch this setting",
    noun: "setting",
    // PROVISIONAL wording (needs CPO and CLO sign-off): lives in lib/approval-copy.ts AUTONOMOUS_CARD_COPY_PROVISIONAL.
    extra: AUTONOMOUS.consequenceExtraOn,
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
      // Each name and value is JSON-escaped, so a newline inside a value cannot start a fake "name = value" row.
      const lines = inputs ? Object.keys(inputs).sort().map((k) => `${JSON.stringify(k)} = ${JSON.stringify(str(inputs[k]))}`) : [];
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
        row("SETTING", f.value === true ? AUTONOMOUS.settingOn : AUTONOMOUS.settingOff),
        row("APPLIES TO", AUTONOMOUS.appliesTo),
      ];
  }
}

export function renderApprovalView(action: CanonicalAction): ApprovalView {
  const phrase = PHRASES[action.tool];
  const base = `Your agent can ${phrase.verb} once, if you ask it to try again. Valid in this conversation only.`;
  // The autonomy extra only applies to switching ON; switching OFF restores the ask-first behaviour.
  const extra =
    action.tool === "mcp__soleur_platform__workspace_set_autonomous" && action.fields.value !== true
      ? AUTONOMOUS.consequenceExtraOff
      : phrase.extra;
  return {
    tool: action.tool,
    title: `Your agent wants to ${phrase.verb}`,
    verbPhrase: phrase.verb,
    fields: fieldRows(action),
    consequence: extra ? `${base} ${extra}` : base,
    singleUse: `One-time · ${phrase.bound ?? `this exact ${phrase.noun}`}`,
    noun: phrase.noun,
    approveLabel: "Approve",
    denyLabel: "Deny",
    danger: action.tool === "mcp__soleur_platform__workspace_set_autonomous",
  };
}

// ---------------------------------------------------------------------------
// Inbox row text (wireframe 06). Built from the same canonical object, so the row cannot name an action the card does
// not show. Plain text only: the inbox row renders it as a React text node.
// ---------------------------------------------------------------------------

export type ApprovalInboxState = "pending" | "approved" | "rejected" | "consumed" | "expired" | "expired_after_approval";

const sha7 = (v: CanonicalValue | undefined): string => str(v).slice(0, 7);

/** "send email to a@b.c, subject “…”": the verb and the primary target in full, never ellipsised. */
function summarizeApprovalAction(action: CanonicalAction): string {
  const f = action.fields;
  switch (action.tool) {
    case "mcp__soleur_platform__email_send":
      return `send email to ${str(f.to)}, subject “${str(f.subject)}”`;
    case "mcp__soleur_platform__email_reply":
      return `send reply to ${str(f.recipient)}, subject “${str(f.subject)}”`;
    case "mcp__soleur_platform__email_suppress":
      return `block address ${str(f.recipient)}`;
    case "mcp__soleur_platform__github_push_branch":
      return `push commit ${sha7(f.headSha)} to branch ${str(f.branch)} in ${str(f.repo)}`;
    case "mcp__soleur_platform__create_pull_request":
      return `open pull request ${str(f.head)} into ${str(f.base)} in ${str(f.repo)}`;
    case "mcp__soleur_platform__github_trigger_workflow":
      return `start workflow ${str(f.workflow_id)} on ${str(f.ref)} in ${str(f.repo)}`;
    case "mcp__soleur_platform__kb_share_create":
      return `create a public link for ${str(f.documentPath)}`;
    case "mcp__soleur_platform__workspace_set_autonomous":
      return f.value === true ? "switch this workspace to autonomous" : "switch this workspace back to ask first";
  }
}

/** The inbox row title. `null` canonical (details removed) falls back to the static, content-free stored title. */
export function renderApprovalInboxTitle(action: CanonicalAction | null, state: ApprovalInboxState, fallback: string): string {
  if (!action) return fallback;
  // The inbox title is plain text from stored values: make direction/zero-width controls visible, as the card does.
  const what = revealInvisible(summarizeApprovalAction(action));
  switch (state) {
    case "pending":
      return `Approval needed: ${what}`;
    case "approved":
      return `You approved: ${what}`;
    case "rejected":
      return `You denied: ${what}`;
    case "consumed":
      return `Released to your agent: ${what}`;
    case "expired":
      return `Approval expired: ${what}. Nothing was run.`;
    case "expired_after_approval":
      return `${APPROVAL_COPY.approvedNeverAsked}: ${what}. Nothing was run.`;
  }
}
