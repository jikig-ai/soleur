// #11076 review (CTO K4) — the cron substrate spawns `claude --plugin-dir <clone>/plugins/soleur`,
// so the plugin's hook sources load into every cron run. `runFramingHookSelfTest` reads only the
// spawn's `.claude/settings.json`; a PostToolUse hook registered by the plugin would run under no
// `frameGhOutput` option and no self-test.
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const PLUGIN = join(__dirname, "../../../plugins/soleur");
const WIDEN =
  "`--plugin-dir` loads this into every cron spawn, so widen runFramingHookSelfTest " +
  "(apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts) to read it first " +
  "(ADR-287 addendum 2026-11-12).";

function markdownFiles(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) markdownFiles(p, out);
    else if (e.name.endsWith(".md")) out.push(p);
  }
  return out;
}

describe("the plugin registers no PostToolUse hook (cron framing dark gate, #11076 K4)", () => {
  it("hooks/hooks.json has events, and no PostToolUse key", () => {
    const parsed = JSON.parse(readFileSync(join(PLUGIN, "hooks/hooks.json"), "utf-8")) as { hooks?: Record<string, unknown> };
    const events = Object.keys(parsed.hooks ?? {});
    expect(events.length).toBeGreaterThan(0);
    expect(events.includes("PostToolUse"), `plugins/soleur/hooks/hooks.json gained a PostToolUse key. ${WIDEN}`).toBe(false);
  });

  it(".claude-plugin/plugin.json declares no inline hooks", () => {
    const manifest = JSON.parse(readFileSync(join(PLUGIN, ".claude-plugin/plugin.json"), "utf-8")) as Record<string, unknown>;
    expect(Object.hasOwn(manifest, "hooks"), `plugins/soleur/.claude-plugin/plugin.json gained a hooks key. ${WIDEN}`).toBe(false);
  });

  it("no skill or agent frontmatter names PostToolUse", () => {
    const files = [...markdownFiles(join(PLUGIN, "skills")), ...markdownFiles(join(PLUGIN, "agents"))];
    expect(files.length).toBeGreaterThan(50);
    const hits = files.filter((f) => {
      const m = /^---\n([\s\S]*?)\n---/.exec(readFileSync(f, "utf-8"));
      return m !== null && /PostToolUse/.test(m[1]);
    });
    expect(hits, `skill or agent frontmatter registers PostToolUse. ${WIDEN}`).toEqual([]);
  });
});
