// Phase 0.3 record (#4672): the per-tool canonical field lists, confirmed against each tool's REAL zod
// schema (the drift test in canonical-schema-drift.test.ts introspects the schemas the tool builders pass to
// the SDK `tool()` and compares them to `FIELD_LISTS` below, so this record cannot rot).
//
// Synthesized data only (cq-test-fixtures-synthesized-only): reserved example domains, UUID-shaped ids.

export const WORKSPACE_ID = "00000000-0000-4000-8000-000000000001";
export const OTHER_WORKSPACE_ID = "00000000-0000-4000-8000-000000000002";
export const CONVERSATION_ID = "00000000-0000-4000-8000-000000000003";
export const OTHER_CONVERSATION_ID = "00000000-0000-4000-8000-000000000004";
export const MESSAGE_ID = "00000000-0000-4000-8000-000000000005";
export const APPROVAL_ID = "00000000-0000-4000-8000-000000000006";
export const USER_ID = "00000000-0000-4000-8000-000000000007";

const P = "mcp__soleur_platform__";

export const TOOLS = {
  emailSend: `${P}email_send`,
  emailReply: `${P}email_reply`,
  emailSuppress: `${P}email_suppress`,
  pushBranch: `${P}github_push_branch`,
  createPr: `${P}create_pull_request`,
  triggerWorkflow: `${P}github_trigger_workflow`,
  kbShareCreate: `${P}kb_share_create`,
  setAutonomous: `${P}workspace_set_autonomous`,
} as const;

/**
 * `input`: every zod field the tool accepts (all of them change what runs, so all are hashed).
 * `server`: fields the model cannot supply (derived by the platform at gate time) that still change what runs.
 * `defaults`: zod defaults the handler applies, which the canonical object must apply too so an omitted
 *   field and its default value are the SAME action.
 */
export const FIELD_LISTS: Record<
  string,
  { builder: string; input: string[]; server: string[]; defaults: Record<string, unknown> }
> = {
  [TOOLS.emailSend]: {
    builder: "email-triage-tools",
    input: ["to", "subject", "body", "replyTo", "jurisdiction", "postalAddress", "optOut", "ftcDisclosure", "art14"],
    server: [],
    defaults: { jurisdiction: "unknown" },
  },
  [TOOLS.emailReply]: {
    builder: "email-triage-tools",
    input: ["messageId", "subject", "body", "jurisdiction", "postalAddress", "optOut", "ftcDisclosure", "art14"],
    server: ["recipient"],
    defaults: { jurisdiction: "unknown" },
  },
  [TOOLS.emailSuppress]: {
    builder: "email-triage-tools",
    input: ["recipient", "reason"],
    server: [],
    defaults: {},
  },
  [TOOLS.pushBranch]: {
    builder: "github-tools",
    input: ["branch", "force"],
    server: ["repo", "headSha"],
    defaults: { force: false },
  },
  [TOOLS.createPr]: {
    builder: "github-tools",
    input: ["head", "base", "title", "body"],
    server: ["repo"],
    defaults: { base: "main" },
  },
  [TOOLS.triggerWorkflow]: {
    builder: "github-tools",
    input: ["workflow_id", "ref", "inputs"],
    server: ["repo"],
    defaults: {},
  },
  [TOOLS.kbShareCreate]: {
    builder: "kb-share-tools",
    input: ["documentPath"],
    server: [],
    defaults: {},
  },
  [TOOLS.setAutonomous]: {
    builder: "workspace-settings-tools",
    input: ["value"],
    server: [],
    defaults: {},
  },
};

export const SHA40 = "a91c3e2a91c3e2a91c3e2a91c3e2a91c3e2a91c3";

export interface Sample {
  input: Record<string, unknown>;
  server: Record<string, unknown>;
}

/** One full-field sample per tool: every optional field set, so a field dropped from the canonical object is visible. */
export const SAMPLES: Record<string, Sample> = {
  [TOOLS.emailSend]: {
    input: {
      to: "maria@example.test",
      subject: "Updated pricing",
      body: "Hello Maria,\nconfirmed.",
      replyTo: "dana@example.test",
      jurisdiction: "eu_uk",
      postalAddress: "1 Example Street, Exampleville",
      optOut: "Reply STOP to opt out.",
      ftcDisclosure: "This is a commercial message.",
      art14: {
        identity: "Example Co",
        purpose: "pricing follow-up",
        legalBasis: "legitimate interest",
        dataSource: "public directory",
        retention: "12 months",
        rights: "access, erasure",
      },
    },
    server: {},
  },
  [TOOLS.emailReply]: {
    input: {
      messageId: MESSAGE_ID,
      subject: "Re: pricing",
      body: "Confirmed.",
      jurisdiction: "us",
      postalAddress: "1 Example Street, Exampleville",
      optOut: "Reply STOP to opt out.",
      ftcDisclosure: "This is a commercial message.",
      art14: { identity: "Example Co" },
    },
    server: { recipient: "sender@example.test" },
  },
  [TOOLS.emailSuppress]: {
    input: { recipient: "promo@example.test", reason: "opt_out" },
    server: {},
  },
  [TOOLS.pushBranch]: {
    input: { branch: "feat/pricing", force: false },
    server: { repo: "example-org/example-repo", headSha: SHA40 },
  },
  [TOOLS.createPr]: {
    input: { head: "feat/pricing", base: "main", title: "Pricing refresh", body: "Updates tier names." },
    server: { repo: "example-org/example-repo" },
  },
  [TOOLS.triggerWorkflow]: {
    input: { workflow_id: 4242, ref: "feat/pricing", inputs: { environment: "preview", notify: "false" } },
    server: { repo: "example-org/example-repo" },
  },
  [TOOLS.kbShareCreate]: {
    input: { documentPath: "knowledge-base/pricing/q4.md" },
    server: {},
  },
  [TOOLS.setAutonomous]: {
    input: { value: true },
    server: {},
  },
};

/** The set of input keys of a sample whose change MUST flip the hash, per tool (every field of the tool). */
export function mutateField(tool: string, field: string): Sample {
  const s = structuredClone(SAMPLES[tool]);
  const bag = field in s.input ? s.input : s.server;
  const cur = bag[field];
  // Fields with a constrained domain need a DIFFERENT VALID value, or zod rejects the mutation instead of hashing it.
  const alt: Record<string, unknown> = {
    jurisdiction: cur === "us" ? "eu_uk" : "us",
    reason: "decline",
    messageId: "00000000-0000-0000-0000-000000000000",
    headSha: `${String(cur).slice(0, -1)}b`,
  };
  if (field in alt) bag[field] = alt[field];
  else if (typeof cur === "string") bag[field] = `${cur}x`;
  else if (typeof cur === "boolean") bag[field] = !cur;
  else if (typeof cur === "number") bag[field] = cur + 1;
  else if (cur && typeof cur === "object") bag[field] = { ...(cur as object), identity: "Changed Co" };
  else throw new Error(`mutateField: unsupported field ${field}`);
  return s;
}
