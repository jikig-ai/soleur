// Leader prompt: knowledge.kb_drift
//
// Operator clicks Fix link on a Today card showing a knowledge-base drift
// (broken anchor, dead link, ...). The agent locates the offending file,
// drafts a fix on a new branch, and commits it. No PR opened — the
// operator reviews the branch via the artifact_url.

import {
  type LeaderPromptModule,
  type ClassInput,
  HAIKU_MODEL,
  LEADER_MAX_TURNS,
  LEADER_MAX_TOKENS,
  type AnthropicToolDef,
} from "./constants";
import { assemblePromptText } from "./prompt-assembly";

const TOOLS: AnthropicToolDef[] = [
  {
    name: "createBranch",
    description: "Create a fresh branch off the default branch for the kb-drift fix.",
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
    description: "Stage the fixed file content.",
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
    description: "Commit the kb-drift fix on the new branch.",
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
];

const SYSTEM_PROMPT = [
  "You are a docs maintainer working on behalf of the operator. A knowledge-base link is broken.",
  "Locate the offending file and the broken link. Determine the corrected target (search adjacent files in the same directory; the target file may have been renamed or moved).",
  "Available tools (use ONLY these):",
  "  - createBranch: cut a fresh branch off the default branch.",
  "  - createBlob: stage the fixed file content.",
  "  - createCommit: commit the fix on the new branch.",
  "Do NOT open a PR. The operator reviews the branch directly.",
  "When done, return end_turn.",
].join("\n");

export const knowledgeKbDrift: LeaderPromptModule = {
  systemPrompt: SYSTEM_PROMPT,
  userPromptTemplate: (input: ClassInput): string => {
    const content = assemblePromptText(input.scrubbedContent ?? "", null);
    return [
      `KB-drift source-ref: ${input.sourceRef}`,
      "",
      "Drift context (PII-scrubbed):",
      content || "(no drift context provided)",
    ].join("\n");
  },
  tools: TOOLS,
  model: HAIKU_MODEL,
  maxTurns: LEADER_MAX_TURNS,
  maxTokens: LEADER_MAX_TOKENS,
  promptVersion: "v1.0.0",
};
