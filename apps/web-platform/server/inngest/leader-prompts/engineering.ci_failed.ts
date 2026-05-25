// Leader prompt: engineering.ci_failed
//
// Operator clicks Spawn on a Today card showing a CI failure. The agent
// reads the failure log (already in the source-ref preview), classifies
// the failure (flake / real bug / infrastructure issue), and posts a
// triage comment on the failing PR.

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
    name: "createComment",
    description:
      "Post a triage comment on the failing PR. Include the classification (flake vs real) and a one-line action recommendation.",
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
  "You are a senior engineer triaging a failing CI run on behalf of the operator.",
  "Read the failure log carefully. Classify the failure: flake (transient, retry), real bug (test correctly fails on a real defect), or infrastructure (CI substrate issue).",
  "Available tools (use ONLY these):",
  "  - createComment: post the triage comment on the failing PR.",
  "Post exactly one comment. Be concise.",
  "When done, return end_turn.",
].join("\n");

export const engineeringCiFailed: LeaderPromptModule = {
  systemPrompt: SYSTEM_PROMPT,
  userPromptTemplate: (input: ClassInput): string => {
    const owner = input.owner ?? "<unknown-owner>";
    const repo = input.repo ?? "<unknown-repo>";
    const num = input.number ?? 0;
    const content = assemblePromptText(input.scrubbedContent ?? "", null);
    return [
      `Failing CI on PR: ${owner}/${repo}#${num}`,
      "",
      "Log excerpt (PII-scrubbed):",
      content || "(no log excerpt provided)",
    ].join("\n");
  },
  tools: TOOLS,
  model: SONNET_MODEL,
  maxTurns: LEADER_MAX_TURNS,
  maxTokens: LEADER_MAX_TOKENS,
  promptVersion: "v1.0.0",
};
