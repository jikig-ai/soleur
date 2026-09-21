import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  isBehindPollState,
  isTerminalPollState,
  shouldResyncBeforePoll,
  behindSyncInstructions,
  PR_BEHIND_SYNC_SENTINEL,
  MERGE_STATE_BEHIND,
  MERGE_STATE_DIRTY,
  formatPrPollState,
} from "../lib/pr-merge-poll";
import { pollInstructions } from "../lib/harness";

const PLUGIN_ROOT = resolve(import.meta.dir, "..");

describe("pr-merge-poll BEHIND contract", () => {
  test("formatPrPollState matches ship Phase 7 jq output", () => {
    expect(formatPrPollState("OPEN", "BEHIND")).toBe("OPEN BEHIND");
    expect(isBehindPollState("OPEN BEHIND")).toBe(true);
    expect(isBehindPollState("OPEN CLEAN")).toBe(false);
  });

  test("shouldResyncBeforePoll fires on BEHIND or DIRTY", () => {
    expect(shouldResyncBeforePoll(MERGE_STATE_BEHIND)).toBe(true);
    expect(shouldResyncBeforePoll(MERGE_STATE_DIRTY)).toBe(true);
    expect(shouldResyncBeforePoll("CLEAN")).toBe(false);
    expect(shouldResyncBeforePoll("BLOCKED")).toBe(false);
  });

  test("terminal states stop poll loop", () => {
    expect(isTerminalPollState("MERGED CLEAN")).toBe(true);
    expect(isTerminalPollState("CLOSED DIRTY")).toBe(true);
    expect(isTerminalPollState("OPEN BEHIND")).toBe(false);
  });

  test("grok pollInstructions mention BEHIND and sync script", () => {
    const md = pollInstructions("grok");
    expect(md).toContain("mergeStateStatus");
    expect(md).toContain("BEHIND");
    expect(md).toContain("sync-pr-behind.sh");
    expect(md).toContain("AwaitShell");
  });

  test("behindSyncInstructions (claude) names the --step call the Monitor loop makes", () => {
    expect(behindSyncInstructions("claude")).toContain("sync-pr-behind.sh <PR-number> --step");
  });

  test("standalone invocations use the installed plugin root, never a repo-relative path (ADR-179)", () => {
    for (const h of ["grok", "claude", "devin"] as const) {
      const md = behindSyncInstructions(h);
      expect(md).toContain('bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"');
      expect(md).not.toContain("bash plugins/soleur/scripts/sync-pr-behind.sh");
    }
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    expect(ship).not.toContain("bash plugins/soleur/scripts/sync-pr-behind.sh");
  });

  test("Grok AwaitShell patterns wake on every tagged Phase 7 / sync line", () => {
    const sync = behindSyncInstructions("grok");
    const poll = pollInstructions("grok");
    for (const md of [sync, poll]) {
      expect(md).toContain("\\[pr-behind-sync\\] kind=");
      expect(md).toContain("\\[ship\\.phase7\\.");
    }
    expect(poll).toContain("Merge poll timed out");
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    // The Phase 7 Grok line must name the fence's actual timeout text.
    expect(ship).toMatch(/AwaitShell\*\* with a `pattern` matching poll output \([^\n]*`Merge poll timed out`[^\n]*`\\\[ship\\\.phase7\\\.`/);
  });

  test("behindSyncInstructions forbids operator handoff on Grok", () => {
    const md = behindSyncInstructions("grok");
    expect(md).toContain("STOP");
    expect(md).toContain("sync-pr-behind.sh");
    expect(md).toContain("do NOT ask");
  });
});

describe("pr-merge-poll sentinel markers", () => {
  test("sync-pr-behind.sh exists and is executable", () => {
    const script = resolve(PLUGIN_ROOT, "scripts/sync-pr-behind.sh");
    const stat = readFileSync(script, "utf-8");
    expect(stat).toContain("BEHIND detected");
    expect(stat).toContain("auto-sync");
    expect(stat).toContain("[pr-behind-sync]");
    // The Phase 7 fences run `--step` and refuse a copy whose --help lacks it (#8383).
    expect(stat).toContain("--step");
    expect(PR_BEHIND_SYNC_SENTINEL).toBe("pr-behind-sync-protocol");
  });

  test("ship SKILL.md documents BEHIND stop-and-sync for Grok", () => {
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    expect(ship).toContain("sync-pr-behind.sh");
    expect(ship).toContain("pr-merge-poll.ts");
  });
});