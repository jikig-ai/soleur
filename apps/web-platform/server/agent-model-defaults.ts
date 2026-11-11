// The model a hosted Agent SDK session runs on when the caller passes none (`buildAgentQueryOptions()`
// in agent-runner-query-options.ts). One named constant, so the id lives in exactly one source file:
// test/server/inngest/claude-cli-pin-knows-models.test.ts harvests it and requires BOTH pinned platform
// binaries (`claude-code-linux-x64`, `claude-agent-sdk-linux-x64`) to know it as a whole token. An id the
// bundled model table does not know is treated as unknown (max_tokens halved, #6934) with tsc and CI green.
//
// Change it in a model-launch PR together with the AUTOFIX_PAIRS table in
// plugins/soleur/skills/model-launch-review/scripts/audit-models.sh, and only to an id both pins carry.
export const AGENT_DEFAULT_MODEL = "claude-sonnet-5-5";

// The model the PDF chapter-routing turn (`selectChapter` in pdf-chapter-router.ts) passes to the Agent SDK
// `query()`. Named here, beside AGENT_DEFAULT_MODEL, so the same harvest and both-binaries check cover it; the
// router itself must carry no raw model-id literal (claude-cli-pin-knows-models.test.ts, row 5 real source).
export const PDF_ROUTING_MODEL = "claude-sonnet-5-5";
