// Leader prompt: triage.p0p1_issue
//
// Operator clicks Spawn on a Today card showing a P0/P1-class issue.
// The agent reads the issue body, classifies severity, applies a
// severity label, and posts a triage comment naming the next action.

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
    name: "addLabels",
    description:
      "Apply one or more labels to the issue. Use for severity labels (severity/p0, severity/p1) and domain labels.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        issue_number: { type: "integer" },
        labels: { type: "array", items: { type: "string" } },
      },
      required: ["owner", "repo", "issue_number", "labels"],
    },
  },
  {
    name: "createComment",
    description:
      "Post a triage comment naming the next concrete action (assign, reproduce, file follow-up, ...).",
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
  "You are an issue triager working on behalf of the operator.",
  "Read the issue body. Classify severity (p0, p1, p2, p3). Apply the severity label and one or more domain labels. Post a concise triage comment naming the next action.",
  "Available tools (use ONLY these):",
  "  - addLabels: apply severity + domain labels.",
  "  - createComment: post the triage comment.",
  "Be decisive. One label-add call and one comment is enough for most issues.",
  "When done, return end_turn.",
].join("\n");

export const triageP0p1Issue: LeaderPromptModule = {
  systemPrompt: SYSTEM_PROMPT,
  userPromptTemplate: (input: ClassInput): string => {
    const owner = input.owner ?? "<unknown-owner>";
    const repo = input.repo ?? "<unknown-repo>";
    const num = input.number ?? 0;
    const content = assemblePromptText(input.scrubbedContent ?? "", null);
    return [
      `Issue: ${owner}/${repo}#${num}`,
      "",
      "Body (PII-scrubbed):",
      content || "(no body content provided)",
    ].join("\n");
  },
  tools: TOOLS,
  model: HAIKU_MODEL,
  maxTurns: LEADER_MAX_TURNS,
  maxTokens: LEADER_MAX_TOKENS,
  promptVersion: "v1.0.0",
};
