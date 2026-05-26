// Leader prompt: engineering.pr_review_pending
//
// Operator clicks Spawn on a Today card showing a PR awaiting review.
// The agent reads the PR diff (via tool call), drafts a substantive
// review comment, and posts it either as a code-line review comment
// or a general issue comment.

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
    name: "createPullRequestReviewComment",
    description:
      "Post a code-line review comment on a specific file + line of the PR. Use for line-specific feedback (bug, suggestion, question).",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        pull_number: { type: "integer" },
        path: { type: "string" },
        line: { type: "integer" },
        body: { type: "string" },
        side: { type: "string", enum: ["LEFT", "RIGHT"] },
      },
      required: ["owner", "repo", "pull_number", "path", "line", "body"],
    },
  },
  {
    name: "createComment",
    description:
      "Post a general issue-level comment on the PR (NOT a code-line comment). Use for the overall review summary.",
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
  "You are a senior engineer reviewing a pull request on behalf of the operator.",
  "Read the PR diff carefully. Identify substantive concerns: bugs, security issues, performance regressions, missing tests, or convention drift.",
  "Available tools (use ONLY these):",
  "  - createPullRequestReviewComment: post a code-line review comment.",
  "  - createComment: post the overall review summary as an issue-level comment.",
  "Post at most one summary comment and up to a few code-line comments for the most important findings. Be concise and constructive. Do not nitpick.",
  "When done, return end_turn.",
].join("\n");

export const engineeringPrReviewPending: LeaderPromptModule = {
  systemPrompt: SYSTEM_PROMPT,
  userPromptTemplate: (input: ClassInput): string => {
    const owner = input.owner ?? "<unknown-owner>";
    const repo = input.repo ?? "<unknown-repo>";
    const num = input.number ?? 0;
    const content = assemblePromptText(input.scrubbedContent ?? "", null);
    return [
      `PR: ${owner}/${repo}#${num}`,
      "",
      "Diff (PII-scrubbed):",
      content || "(no diff content provided — use a tool call to fetch as needed)",
    ].join("\n");
  },
  tools: TOOLS,
  model: SONNET_MODEL,
  maxTurns: LEADER_MAX_TURNS,
  maxTokens: LEADER_MAX_TOKENS,
  promptVersion: "v1.0.0",
};
