import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { getFlag, getFeatureFlags } from "./server";

describe("getFlag", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  it("returns true when env var is '1'", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    expect(getFlag("kb-chat-sidebar")).toBe(true);
  });

  it("returns false when env var is '0'", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "0";
    expect(getFlag("kb-chat-sidebar")).toBe(false);
  });

  it("returns false when env var is unset", () => {
    delete process.env.FLAG_KB_CHAT_SIDEBAR;
    expect(getFlag("kb-chat-sidebar")).toBe(false);
  });

  it("returns false when env var is any non-'1' value", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "yes";
    expect(getFlag("kb-chat-sidebar")).toBe(false);

    process.env.FLAG_KB_CHAT_SIDEBAR = "true";
    expect(getFlag("kb-chat-sidebar")).toBe(false);
  });
});

describe("getFeatureFlags", () => {
  const ORIGINAL_ENV = process.env;

  beforeEach(() => {
    process.env = { ...ORIGINAL_ENV };
  });

  afterEach(() => {
    process.env = ORIGINAL_ENV;
  });

  it("returns all flags as a record", () => {
    process.env.FLAG_KB_CHAT_SIDEBAR = "1";
    const flags = getFeatureFlags();
    expect(flags).toEqual({ "kb-chat-sidebar": true });
  });

  it("returns false for all flags when none are set", () => {
    delete process.env.FLAG_KB_CHAT_SIDEBAR;
    const flags = getFeatureFlags();
    expect(flags).toEqual({ "kb-chat-sidebar": false });
  });
});
