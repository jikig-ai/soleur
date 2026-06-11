// extractModelJson contract tests (#5080 follow-up — fence-wrapped model JSON).
import { describe, expect, it } from "vitest";
import { extractModelJson } from "@/server/model-json";

describe("extractModelJson", () => {
  it("strips a ```json fence (the live-reproduced claude-sonnet-4-6 shape)", () => {
    expect(extractModelJson('```json\n{"a":1}\n```')).toBe('{"a":1}');
  });

  it("strips uppercase / variant language tags (```JSON, ```jsonc)", () => {
    expect(extractModelJson('```JSON\n{"a":1}\n```')).toBe('{"a":1}');
    expect(extractModelJson('```jsonc\n{"a":1}\n```')).toBe('{"a":1}');
  });

  it("strips a bare fence with no language tag", () => {
    expect(extractModelJson('```\n[1,2]\n```')).toBe("[1,2]");
  });

  it("passes unfenced text through untouched (trimmed)", () => {
    expect(extractModelJson('  {"a":1}\n')).toBe('{"a":1}');
  });

  it("leaves prose-wrapped fences alone (caller's parse throws -> existing fallbacks)", () => {
    const prose = 'Here you go: ```json\n{"a":1}\n``` Hope this helps';
    expect(extractModelJson(prose)).toBe(prose.trim());
  });

  it("handles embedded triple-backticks inside string values (end anchor wins)", () => {
    const inner = '{"code":"```js fenced```","ok":true}';
    expect(extractModelJson("```json\n" + inner + "\n```")).toBe(inner);
  });
});
