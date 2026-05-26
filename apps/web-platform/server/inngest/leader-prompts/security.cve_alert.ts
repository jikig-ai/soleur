// Leader prompt: security.cve_alert
//
// Operator clicks Spawn on a Today card showing a CVE-class GitHub
// Advisory. The agent reads the advisory, identifies the affected
// dependency, drafts a version-bump PR on a fresh branch, and posts a
// triage comment cross-referencing the bump.

import {
  type LeaderPromptModule,
  type ClassInput,
  SONNET_MODEL,
  LEADER_MAX_TURNS,
  LEADER_MAX_TOKENS,
  type AnthropicToolDef,
} from "./constants";
import { assemblePromptText } from "./prompt-assembly";

const TOOLS: AnthropicToolDef[] = [
  {
    name: "createBranch",
    description:
      "Create a new branch off the default branch for the CVE bump.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        branch_name: { type: "string" },
      },
      required: ["owner", "repo", "branch_name"],
    },
  },
  {
    name: "createBlob",
    description: "Create a file blob containing the bumped package manifest.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        content: { type: "string" },
        encoding: { type: "string", enum: ["utf-8", "base64"] },
      },
      required: ["owner", "repo", "content"],
    },
  },
  {
    name: "createCommit",
    description: "Commit the bumped manifest on the CVE-bump branch.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        branch_name: { type: "string" },
        message: { type: "string" },
        tree_changes: { type: "array" },
      },
      required: ["owner", "repo", "branch_name", "message"],
    },
  },
  {
    name: "createPullRequest",
    description: "Open a draft PR from the CVE-bump branch to the default branch.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        head: { type: "string" },
        base: { type: "string" },
        title: { type: "string" },
        body: { type: "string" },
        draft: { type: "boolean" },
      },
      required: ["owner", "repo", "head", "base", "title", "body"],
    },
  },
  {
    name: "createComment",
    description:
      "Post a comment on the original advisory (or related issue) cross-referencing the bump PR.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        issue_number: { type: "integer" },
        body: { type: "string" },
      },
      required: ["owner", "repo", "issue_number", "body"],
    },
  },
];

const SYSTEM_PROMPT = [
  "You are a security engineer working on behalf of the operator. A CVE-class GitHub Advisory affects this repo's dependencies.",
  "Identify the affected dependency from the advisory. Determine the safe target version (typically the advisory's `patched_versions`).",
  "Available tools (use ONLY these):",
  "  - createBranch: cut a fresh branch off the default branch.",
  "  - createBlob: stage the bumped manifest content.",
  "  - createCommit: commit the bumped manifest.",
  "  - createPullRequest: open a DRAFT PR (draft: true) for operator review.",
  "  - createComment: cross-reference the bump PR on the original advisory.",
  "Draft only. Do NOT mark the PR ready for review — the operator decides.",
  "When done, return end_turn.",
].join("\n");

export const securityCveAlert: LeaderPromptModule = {
  systemPrompt: SYSTEM_PROMPT,
  userPromptTemplate: (input: ClassInput): string => {
    const content = assemblePromptText(input.scrubbedContent ?? "", null);
    return [
      `CVE alert source: ${input.sourceRef}`,
      "",
      "Advisory body (PII-scrubbed):",
      content || "(no advisory body provided)",
    ].join("\n");
  },
  tools: TOOLS,
  model: SONNET_MODEL,
  maxTurns: LEADER_MAX_TURNS,
  maxTokens: LEADER_MAX_TOKENS,
  promptVersion: "v1.0.0",
};
