// Shared tool-name log/serialization sanitizer. Extracted from cc-dispatcher.ts
// so both the cc-soleur-go dispatcher (WS tool_use frames) and the TR3
// tool-attempt telemetry collector (server/tool-attempt-telemetry.ts) sanitize
// tool names identically before they enter a log line, a WS event, or a jsonb
// row — without a cc-dispatcher <-> telemetry import cycle.
//
// MCP tool names (`mcp__<server>__<tool>`) can carry config/model-influenced
// bytes; strip control chars + U+2028/U+2029 (log-injection: see
// 2026-04-17-log-injection-unicode-line-separators.md) and cap the length so a
// pathological name cannot bloat a jsonb key or a log field. Unicode separators
// are written as escapes only (cq-regex-unicode-separators-escape-only).

const MAX_TOOL_NAME_LEN_FOR_LOG = 128;

export function sanitizeToolNameForLog(name: string): string {
  return name
    .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "?")
    .slice(0, MAX_TOOL_NAME_LEN_FOR_LOG);
}
