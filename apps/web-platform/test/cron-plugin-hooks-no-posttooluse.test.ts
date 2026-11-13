// #11076 review (CTO K4) — the cron substrate spawns `claude --plugin-dir <clone>/plugins/soleur`,
// so the plugin's hooks.json loads into every cron run. `runFramingHookSelfTest` reads only the
// spawn's `.claude/settings.json`; a PostToolUse entry in the plugin file would register a
// PostToolUse hook that no `frameGhOutput` option controls and no self-test checks.
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const HOOKS_JSON = join(__dirname, "../../../plugins/soleur/hooks/hooks.json");

describe("plugin hooks.json registers no PostToolUse hook (cron framing dark gate, #11076 K4)", () => {
  it("has a hooks object with at least one event, and no PostToolUse key", () => {
    const parsed = JSON.parse(readFileSync(HOOKS_JSON, "utf-8")) as { hooks?: Record<string, unknown> };
    const events = Object.keys(parsed.hooks ?? {});
    expect(events.length).toBeGreaterThan(0);
    expect(
      events.includes("PostToolUse"),
      "plugins/soleur/hooks/hooks.json gained a PostToolUse key. `--plugin-dir` loads this file into " +
        "every cron spawn, so widen runFramingHookSelfTest (apps/web-platform/server/inngest/functions/" +
        "_cron-claude-eval-substrate.ts) to read it before adding the entry (ADR-287 addendum 2026-11-12).",
    ).toBe(false);
  });
});
