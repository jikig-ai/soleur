import { describe, it, expect, beforeEach } from "vitest";
import {
  isEditable,
  buildCommands,
  resolveShortcut,
  readShortcutsEnabled,
  writeShortcutsEnabled,
  SHORTCUTS_STORAGE_KEY,
  type Command,
} from "@/components/command-palette/use-shortcuts";

function byId(cmds: Command[], id: string): Command | undefined {
  return cmds.find((c) => c.id === id);
}

// A minimal KeyboardEvent-like shape resolveShortcut reads (pure, DOM-free).
function key(
  k: string,
  opts: { meta?: boolean; ctrl?: boolean; shift?: boolean; target?: unknown } = {},
) {
  return {
    key: k,
    metaKey: opts.meta ?? false,
    ctrlKey: opts.ctrl ?? false,
    shiftKey: opts.shift ?? false,
    target: opts.target ?? { tagName: "BODY" },
  };
}

describe("resolveShortcut", () => {
  it("maps ⌘K / Ctrl+K (any case) to openPalette", () => {
    expect(resolveShortcut(key("k", { meta: true }))).toBe("openPalette");
    expect(resolveShortcut(key("K", { ctrl: true }))).toBe("openPalette");
  });
  it("maps ⌘/ (canonical, WCAG-exempt) and bare ? (alias) to openHelp", () => {
    expect(resolveShortcut(key("/", { meta: true }))).toBe("openHelp");
    expect(resolveShortcut(key("?"))).toBe("openHelp");
  });
  it("maps ⌘B / Ctrl+B to toggleSidebar but rejects the shift variant", () => {
    expect(resolveShortcut(key("b", { meta: true }))).toBe("toggleSidebar");
    expect(resolveShortcut(key("b", { meta: true, shift: true }))).toBeNull();
  });
  it("is suppressed entirely while focus is in an editable element", () => {
    const target = { tagName: "INPUT" };
    expect(resolveShortcut(key("k", { meta: true, target }))).toBeNull();
    expect(resolveShortcut(key("?", { target }))).toBeNull();
    expect(resolveShortcut(key("b", { meta: true, target }))).toBeNull();
  });
  it("returns null for unrelated keys", () => {
    expect(resolveShortcut(key("a", { meta: true }))).toBeNull();
    expect(resolveShortcut(key("Escape"))).toBeNull();
  });
});

describe("isEditable", () => {
  it("returns true for INPUT / TEXTAREA / SELECT (case-insensitive)", () => {
    expect(isEditable({ tagName: "INPUT" })).toBe(true);
    expect(isEditable({ tagName: "textarea" })).toBe(true);
    expect(isEditable({ tagName: "SELECT" })).toBe(true);
  });
  it("returns true for contenteditable elements (incl. the palette's own input)", () => {
    expect(isEditable({ tagName: "DIV", isContentEditable: true })).toBe(true);
  });
  it("returns false for non-editable targets, null, and SVG", () => {
    expect(isEditable({ tagName: "DIV" })).toBe(false);
    expect(isEditable({ tagName: "BUTTON" })).toBe(false);
    expect(isEditable({ tagName: "svg" })).toBe(false);
    expect(isEditable(null)).toBe(false);
  });
});

describe("buildCommands", () => {
  it("emits a navigate effect for every primary nav destination", () => {
    const cmds = buildCommands({ isAdmin: false });
    const inbox = byId(cmds, "nav:/dashboard/inbox");
    expect(inbox?.group).toBe("Navigation");
    expect(inbox?.run()).toEqual({ kind: "navigate", href: "/dashboard/inbox" });
  });
  it("includes admin nav items ONLY when isAdmin", () => {
    expect(byId(buildCommands({ isAdmin: false }), "nav:/dashboard/admin/analytics")).toBeUndefined();
    expect(byId(buildCommands({ isAdmin: true }), "nav:/dashboard/admin/analytics")).toBeDefined();
  });
  it("exposes the 'Ask an agent' hero command as an openChat effect", () => {
    const ask = byId(buildCommands({ isAdmin: false }), "ask-agent");
    expect(ask?.group).toBe("Ask an agent");
    expect(ask?.run()).toEqual({ kind: "openChat" });
  });
  it("exposes the help command (opens the ? overlay) as a serializable effect", () => {
    const help = byId(buildCommands({ isAdmin: false }), "help");
    expect(help?.run().kind).toBe("openHelp");
  });
});

describe("shortcutsEnabled storage", () => {
  beforeEach(() => {
    try {
      globalThis.localStorage?.clear();
    } catch {
      /* node env: no localStorage — readShortcutsEnabled must still default true */
    }
  });
  it("defaults to true when nothing is stored (or storage is unavailable)", () => {
    expect(readShortcutsEnabled()).toBe(true);
  });
  it("round-trips false / true through storage when available", () => {
    if (typeof globalThis.localStorage === "undefined") return; // node project: skip
    writeShortcutsEnabled(false);
    expect(globalThis.localStorage.getItem(SHORTCUTS_STORAGE_KEY)).toBe("0");
    expect(readShortcutsEnabled()).toBe(false);
    writeShortcutsEnabled(true);
    expect(readShortcutsEnabled()).toBe(true);
  });
});
