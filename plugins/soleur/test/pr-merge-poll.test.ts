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

  test("shouldResyncBeforePoll fires only on BEHIND", () => {
    expect(shouldResyncBeforePoll(MERGE_STATE_BEHIND)).toBe(true);
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
    expect(PR_BEHIND_SYNC_SENTINEL).toBe("pr-behind-sync-protocol");
  });

  test("ship SKILL.md documents BEHIND stop-and-sync for Grok", () => {
    const ship = readFileSync(resolve(PLUGIN_ROOT, "skills/ship/SKILL.md"), "utf-8");
    expect(ship).toContain("sync-pr-behind.sh");
    expect(ship).toContain("pr-merge-poll.ts");
  });
});