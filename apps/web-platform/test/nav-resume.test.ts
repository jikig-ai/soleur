// @vitest-environment happy-dom
/**
 * Pure helpers for nav-rail position resume (#4826 / RQ4).
 * sessionStorage is only touched via higher-level helpers that wrap safeSession;
 * these pure functions must never throw on corrupt input.
 */
import { describe, it, expect, beforeEach } from "vitest";
import {
  resumeKey,
  parseExpanded,
  serializeExpanded,
  isResumeableConversationId,
  sanitizeKbRelativePath,
  kbPathFromPathname,
  chatIdFromPathname,
  kbEntryHrefFromStored,
  chatEntryIdFromStored,
  MAX_EXPANDED_PATHS,
} from "@/lib/nav-resume";

const WS = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const CONV = "11111111-2222-3333-4444-555555555555";

describe("resumeKey", () => {
  it("shapes workspace-scoped keys", () => {
    expect(resumeKey(WS, "kb", "path")).toBe(
      `soleur:nav.resume.${WS}.kb.path`,
    );
    expect(resumeKey(WS, "kb", "expanded")).toBe(
      `soleur:nav.resume.${WS}.kb.expanded`,
    );
    expect(resumeKey(WS, "kb", "scrollTop")).toBe(
      `soleur:nav.resume.${WS}.kb.scrollTop`,
    );
    expect(resumeKey(WS, "chat", "id")).toBe(
      `soleur:nav.resume.${WS}.chat.id`,
    );
  });

  it("isolates workspace A from workspace B", () => {
    const a = resumeKey("ws-a", "chat", "id");
    const b = resumeKey("ws-b", "chat", "id");
    expect(a).not.toBe(b);
    expect(a).toContain("ws-a");
    expect(b).toContain("ws-b");
  });
});

describe("kbPathFromPathname", () => {
  it("extracts relative path under /dashboard/kb/", () => {
    expect(kbPathFromPathname("/dashboard/kb/foo/bar.md")).toBe("foo/bar.md");
    expect(kbPathFromPathname("/dashboard/kb/x.md")).toBe("x.md");
  });

  it("returns null for section root and non-KB paths", () => {
    expect(kbPathFromPathname("/dashboard/kb")).toBeNull();
    expect(kbPathFromPathname("/dashboard/kb/")).toBeNull();
    expect(kbPathFromPathname("/dashboard/chat")).toBeNull();
    expect(kbPathFromPathname("/dashboard")).toBeNull();
  });

  it("decodes URI components", () => {
    expect(kbPathFromPathname("/dashboard/kb/dir%20name/file.md")).toBe(
      "dir name/file.md",
    );
  });
});

describe("sanitizeKbRelativePath", () => {
  it("accepts safe relative paths", () => {
    expect(sanitizeKbRelativePath("foo/bar.md")).toBe("foo/bar.md");
    expect(sanitizeKbRelativePath("engineering/adr-044.md")).toBe(
      "engineering/adr-044.md",
    );
    expect(sanitizeKbRelativePath("a_b-c.d/x.md")).toBe("a_b-c.d/x.md");
  });

  it("rejects traversal, double-slash, backslash, absolute, empty", () => {
    expect(sanitizeKbRelativePath("..")).toBeNull();
    expect(sanitizeKbRelativePath("foo/../bar.md")).toBeNull();
    expect(sanitizeKbRelativePath("foo//bar.md")).toBeNull();
    expect(sanitizeKbRelativePath("foo\\bar.md")).toBeNull();
    expect(sanitizeKbRelativePath("/absolute.md")).toBeNull();
    expect(sanitizeKbRelativePath("")).toBeNull();
    expect(sanitizeKbRelativePath(null)).toBeNull();
    expect(sanitizeKbRelativePath("evil?x=1")).toBeNull();
    expect(sanitizeKbRelativePath("evil#hash")).toBeNull();
  });
});

describe("chatIdFromPathname + isResumeableConversationId", () => {
  it("extracts UUID conversation ids", () => {
    expect(chatIdFromPathname(`/dashboard/chat/${CONV}`)).toBe(CONV);
  });

  it("rejects bare chat, /new, empty, and non-uuid segments", () => {
    expect(chatIdFromPathname("/dashboard/chat")).toBeNull();
    expect(chatIdFromPathname("/dashboard/chat/")).toBeNull();
    expect(chatIdFromPathname("/dashboard/chat/new")).toBeNull();
    expect(chatIdFromPathname("/dashboard/chat/not-a-uuid")).toBeNull();
    expect(chatIdFromPathname("/dashboard/kb/x")).toBeNull();
  });

  it("isResumeableConversationId rejects new/empty/non-uuid", () => {
    expect(isResumeableConversationId(CONV)).toBe(true);
    expect(isResumeableConversationId("new")).toBe(false);
    expect(isResumeableConversationId("")).toBe(false);
    expect(isResumeableConversationId("abc")).toBe(false);
    expect(isResumeableConversationId("11111111-2222-3333-4444-55555555555")).toBe(
      false,
    ); // 35 chars
  });
});

describe("parseExpanded / serializeExpanded", () => {
  it("parses a JSON string array", () => {
    expect(parseExpanded(JSON.stringify(["a", "b/c"]))).toEqual(["a", "b/c"]);
  });

  it("returns [] on corrupt / non-array / non-string entries", () => {
    expect(parseExpanded(null)).toEqual([]);
    expect(parseExpanded("")).toEqual([]);
    expect(parseExpanded("{not json")).toEqual([]);
    expect(parseExpanded("null")).toEqual([]);
    expect(parseExpanded('"string"')).toEqual([]);
    expect(parseExpanded(JSON.stringify([1, "ok", null, "x"]))).toEqual([
      "ok",
      "x",
    ]);
  });

  it("caps expanded list length on serialize", () => {
    const many = Array.from({ length: MAX_EXPANDED_PATHS + 50 }, (_, i) => `d${i}`);
    const raw = serializeExpanded(many);
    const parsed = parseExpanded(raw);
    expect(parsed.length).toBe(MAX_EXPANDED_PATHS);
  });

  it("filters unsafe paths out of expanded on parse", () => {
    expect(
      parseExpanded(JSON.stringify(["safe/dir", "..", "foo//bar", "ok"])),
    ).toEqual(["safe/dir", "ok"]);
  });
});

describe("kbEntryHrefFromStored / chatEntryIdFromStored", () => {
  it("builds sticky KB href from stored safe path", () => {
    expect(kbEntryHrefFromStored("foo/bar.md")).toBe("/dashboard/kb/foo/bar.md");
  });

  it("falls back to section root for unsafe/missing path", () => {
    expect(kbEntryHrefFromStored(null)).toBe("/dashboard/kb");
    expect(kbEntryHrefFromStored("..")).toBe("/dashboard/kb");
    expect(kbEntryHrefFromStored("")).toBe("/dashboard/kb");
  });

  it("returns chat id only when resumeable", () => {
    expect(chatEntryIdFromStored(CONV)).toBe(CONV);
    expect(chatEntryIdFromStored("new")).toBeNull();
    expect(chatEntryIdFromStored(null)).toBeNull();
    expect(chatEntryIdFromStored("not-uuid")).toBeNull();
  });
});

describe("scrollTop parse helpers (via parseExpanded sibling API)", () => {
  // scrollTop is integer string — covered in module as parseScrollTop
  it("is covered by module exports used by hook", async () => {
    const { parseScrollTop } = await import("@/lib/nav-resume");
    expect(parseScrollTop("400")).toBe(400);
    expect(parseScrollTop("0")).toBe(0);
    expect(parseScrollTop("-1")).toBeNull();
    expect(parseScrollTop("1.5")).toBeNull();
    expect(parseScrollTop("nope")).toBeNull();
    expect(parseScrollTop(null)).toBeNull();
    expect(parseScrollTop("")).toBeNull();
  });
});

describe("sessionStorage isolation (workspace keys)", () => {
  beforeEach(() => {
    sessionStorage.clear();
  });

  it("does not collide keys across workspaces when writing via key builder", () => {
    const keyA = resumeKey("ws-a", "kb", "path");
    const keyB = resumeKey("ws-b", "kb", "path");
    sessionStorage.setItem(keyA, "from-a.md");
    sessionStorage.setItem(keyB, "from-b.md");
    expect(sessionStorage.getItem(keyA)).toBe("from-a.md");
    expect(sessionStorage.getItem(keyB)).toBe("from-b.md");
  });
});
