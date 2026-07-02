import { describe, it, expect, beforeEach } from "vitest";
import {
  isEditable,
  buildCommands,
  resolveShortcut,
  resolveSequence,
  formatSeqHint,
  ASK_AGENT_SEQ,
  SEQUENCE_WINDOW_MS,
  readShortcutsEnabled,
  writeShortcutsEnabled,
  SHORTCUTS_STORAGE_KEY,
  type Command,
} from "@/components/command-palette/use-shortcuts";
import {
  NAV_ITEMS,
  ADMIN_NAV_ITEMS,
} from "@/components/command-palette/nav-items";
import {
  isApplePlatform,
  modChord,
} from "@/components/command-palette/platform";

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

describe("resolveSequence", () => {
  const admin = { isAdmin: true };
  const nonAdmin = { isAdmin: false };
  // `armed` is the phase discriminant: false = arm phase, true = resolve phase.
  // Expiry (the arm timestamp) is the listener's concern, not the pure resolver's.

  it("arms on a bare g when no prefix is pending", () => {
    expect(resolveSequence(false, key("g"), nonAdmin)).toBe("arm");
    expect(resolveSequence(false, key("G"), nonAdmin)).toBe("arm");
  });

  it("does not arm on g with a modifier, or while focus is editable", () => {
    expect(resolveSequence(false, key("g", { meta: true }), nonAdmin)).toBeNull();
    expect(resolveSequence(false, key("g", { ctrl: true }), nonAdmin)).toBeNull();
    expect(
      resolveSequence(false, key("g", { target: { tagName: "INPUT" } }), nonAdmin),
    ).toBeNull();
  });

  it("does not arm or resolve on auto-repeat", () => {
    expect(resolveSequence(false, { ...key("g"), repeat: true }, nonAdmin)).toBeNull();
    expect(
      resolveSequence(true, { ...key("d"), repeat: true }, nonAdmin),
    ).toBeNull();
  });

  it("resolves each mapped second key to its navigate/openChat effect", () => {
    expect(resolveSequence(true, key("d"), nonAdmin)).toEqual({
      kind: "navigate",
      href: "/dashboard",
    });
    expect(resolveSequence(true, key("i"), nonAdmin)).toEqual({
      kind: "navigate",
      href: "/dashboard/inbox",
    });
    expect(resolveSequence(true, key("w"), nonAdmin)).toEqual({
      kind: "navigate",
      href: "/dashboard/workstream",
    });
    expect(resolveSequence(true, key("k"), nonAdmin)).toEqual({
      kind: "navigate",
      href: "/dashboard/kb",
    });
    expect(resolveSequence(true, key("r"), nonAdmin)).toEqual({
      kind: "navigate",
      href: "/dashboard/routines",
    });
    // `g c` — Ask an agent (the rebound-from-Ctrl+C hero summon).
    expect(resolveSequence(true, key("c"), nonAdmin)).toEqual({
      kind: "openChat",
    });
  });

  it("gates g a (Analytics) on ctx.isAdmin", () => {
    expect(resolveSequence(true, key("a"), admin)).toEqual({
      kind: "navigate",
      href: "/dashboard/admin/analytics",
    });
    expect(resolveSequence(true, key("a"), nonAdmin)).toBeNull();
  });

  it("returns null for an unmapped second key, a second g, and a chord", () => {
    expect(resolveSequence(true, key("x"), admin)).toBeNull();
    expect(resolveSequence(true, key("g"), admin)).toBeNull();
    expect(resolveSequence(true, key("k", { meta: true }), admin)).toBeNull();
  });

  it("is suppressed while focus is editable even mid-sequence", () => {
    expect(
      resolveSequence(true, key("d", { target: { tagName: "TEXTAREA" } }), admin),
    ).toBeNull();
  });
});

describe("seq single-source (AC7) + formatSeqHint", () => {
  it("upcases a sequence for display (g d -> G D)", () => {
    expect(formatSeqHint("g d")).toBe("G D");
    expect(formatSeqHint(ASK_AGENT_SEQ)).toBe("G C");
  });

  it("uses GitHub's proven 1500 ms sequence window", () => {
    expect(SEQUENCE_WINDOW_MS).toBe(1500);
  });

  it("derives every nav command's keys hint from the seq field on the arrays", () => {
    const cmds = buildCommands({ isAdmin: true });
    for (const item of [...NAV_ITEMS, ...ADMIN_NAV_ITEMS]) {
      const cmd = byId(cmds, `nav:${item.href}`);
      expect(item.seq).toBeTruthy();
      expect(cmd?.keys).toBe(formatSeqHint(item.seq as string));
    }
    // The ask hero shows its GLOBAL summon binding, not the palette-only ⌘↵.
    expect(byId(cmds, "ask-agent")?.keys).toBe("G C");
    expect(byId(cmds, "ask-agent")?.keys).not.toBe("⌘↵");
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

// FR1/AC3 — platform detection is a pure, SSR-safe, DOM-free helper (inject the
// navigator shape) used only to pick the display glyph (⌘ vs Ctrl). It never
// touches the resolver path.
describe("isApplePlatform", () => {
  it("returns true for a macOS navigator shape", () => {
    expect(isApplePlatform({ platform: "MacIntel", userAgent: "Mozilla/5.0 (Macintosh)" })).toBe(true);
  });
  it("returns true for iPhone/iPad user agents", () => {
    expect(isApplePlatform({ platform: "iPhone", userAgent: "iPhone" })).toBe(true);
    expect(isApplePlatform({ platform: "", userAgent: "Mozilla/5.0 (iPad; CPU OS 17_0)" })).toBe(true);
  });
  it("returns false for Windows / Linux / ChromeOS shapes", () => {
    expect(isApplePlatform({ platform: "Win32", userAgent: "Windows NT 10.0" })).toBe(false);
    expect(isApplePlatform({ platform: "Linux x86_64", userAgent: "X11; Linux" })).toBe(false);
    expect(isApplePlatform({ platform: "Linux armv8l", userAgent: "CrOS" })).toBe(false);
  });
  it("returns false (stable SSR default) when no navigator is available", () => {
    expect(isApplePlatform(null)).toBe(false);
    expect(isApplePlatform(undefined as unknown as null)).toBe(false);
  });
});

describe("modChord", () => {
  it("renders the ⌘ glyph (no separator) on Apple", () => {
    expect(modChord("K", true)).toBe("⌘K");
    expect(modChord("/", true)).toBe("⌘/");
  });
  it("renders Ctrl+ on non-Apple", () => {
    expect(modChord("K", false)).toBe("Ctrl+K");
    expect(modChord("B", false)).toBe("Ctrl+B");
  });
});

// FR2 — the ⌘B palette hint is a display substitution that follows the platform;
// the default (SSR / non-Apple) is Ctrl+B, and the model (seq/formatSeqHint) is
// untouched.
describe("buildCommands — platform-aware modifier glyph", () => {
  it("shows Ctrl+B for the sidebar toggle on a non-Apple platform (default)", () => {
    expect(byId(buildCommands({ isAdmin: false }), "toggle-sidebar")?.keys).toBe("Ctrl+B");
    expect(byId(buildCommands({ isAdmin: false }, { isApplePlatform: false }), "toggle-sidebar")?.keys).toBe("Ctrl+B");
  });
  it("shows ⌘B for the sidebar toggle on Apple", () => {
    expect(byId(buildCommands({ isAdmin: false }, { isApplePlatform: true }), "toggle-sidebar")?.keys).toBe("⌘B");
  });
});
