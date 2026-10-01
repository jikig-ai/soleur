// Guards 2+3 of #9239 — version-independent memory-backstop dispatch.
//
// #9239 made .claude/hooks/memory-backstop.sh version-independent: instead of
// settings.json exec'ing the checkout's copy directly, it invokes a resolver
// shim (memory-backstop-resolve.sh) that picks the newest installed copy —
// the checkout, the managed path ~/.local/share/soleur/hooks/, and both plugin
// caches — by each copy's BACKSTOP_REVISION marker. Two degenerate edits can
// silently re-break that property:
//
//   Guard 2 — the vendored plugin payload drifts. `plugins/soleur/hooks/
//   memory-backstop.sh` exists so `claude plugin update` delivers the hook to
//   the resolver's plugin-cache glob (the issue's "plugin updates don't reach
//   it" complaint). It is payload-only — deliberately NOT registered in
//   plugins/soleur/hooks/hooks.json — and must stay byte-identical to the repo
//   hook. A one-byte drift or a deleted copy makes the plugin channel ship a
//   different control than the one the repo tests.
//
//   Guard 3 — the settings wiring bypasses the resolver. The one registry
//   that binds the backstop is .claude/settings.json (verified: .devin/
//   config.json and .codex/config.toml do not bind it). Reverting the
//   SessionStart command to memory-backstop.sh restores checkout-pinned
//   dispatch; deleting the entry disables the backstop outright. Both must be
//   test failures — asserted by PARSING the JSON, never grepping file text.
//
// Mutation matrices live in
// knowledge-base/project/plans/2026-09-29-fix-backstop-hook-version-resolution-plan.md
// (Guard Contract, Guards 2 and 3). Absence is a violation everywhere below —
// never a vacuous pass.

import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const REPO_HOOK = join(REPO_ROOT, ".claude", "hooks", "memory-backstop.sh");
const RESOLVER = join(REPO_ROOT, ".claude", "hooks", "memory-backstop-resolve.sh");
const VENDORED_HOOK = join(REPO_ROOT, "plugins", "soleur", "hooks", "memory-backstop.sh");
const SETTINGS_JSON = join(REPO_ROOT, ".claude", "settings.json");
const PLUGIN_HOOKS_JSON = join(REPO_ROOT, "plugins", "soleur", "hooks", "hooks.json");

// The same marker shape the resolver greps for (`grep -m1 -oE
// 'BACKSTOP_REVISION=[0-9]+'` — never `source`, ADR-156 posture).
const MARKER = /BACKSTOP_REVISION=\d+/;

interface HookEntry {
  type?: string;
  command?: string;
}
interface HookGroup {
  matcher?: string;
  hooks?: HookEntry[];
}

/** Every command string registered under one hook event, or [] if absent. */
function eventCommands(registryText: string, event: string): string[] {
  const registry = JSON.parse(registryText);
  const groups: HookGroup[] = registry?.hooks?.[event] ?? [];
  return groups.flatMap((g) => (g.hooks ?? []).map((h) => h.command ?? ""));
}

/** Every command string registered under every hook event. */
function allCommands(registryText: string): string[] {
  const registry = JSON.parse(registryText);
  const hooks = registry?.hooks ?? {};
  return Object.values(hooks).flatMap((groups) =>
    (groups as HookGroup[]).flatMap((g) => (g.hooks ?? []).map((h) => h.command ?? "")),
  );
}

describe("Guard 2 — vendored plugin copy stays byte-equal to the repo hook", () => {
  test("plugins/soleur/hooks/memory-backstop.sh exists (absence is a failure, not a skip)", () => {
    expect(
      existsSync(VENDORED_HOOK),
      "vendored payload missing — `claude plugin update` delivers no backstop copy " +
        "to the resolver's plugin-cache glob (#9239). Vendor it: " +
        "cp .claude/hooks/memory-backstop.sh plugins/soleur/hooks/ && chmod 0755",
    ).toBe(true);
  });

  test("vendored copy is byte-identical to .claude/hooks/memory-backstop.sh", () => {
    const repo = readFileSync(REPO_HOOK);
    const vendored = readFileSync(VENDORED_HOOK);
    expect(
      vendored.equals(repo),
      "vendored payload drifted from the repo hook — re-vendor with `cp` " +
        "(the copy is never generated, only copied; drift means the plugin ships " +
        "a different control than the one the repo tests)",
    ).toBe(true);
  });

  test("both copies carry a BACKSTOP_REVISION=<n> marker line", () => {
    // Independent of byte-equality: stripping the marker from BOTH copies must
    // still go RED (Guard 2 matrix row 4) — an equality-only assertion would
    // pass on two markerless files the resolver orders as revision 0.
    const repo = readFileSync(REPO_HOOK, "utf8");
    const vendored = readFileSync(VENDORED_HOOK, "utf8");
    expect(MARKER.test(repo), `${REPO_HOOK} has no BACKSTOP_REVISION=<n> marker`).toBe(true);
    expect(MARKER.test(vendored), `${VENDORED_HOOK} has no BACKSTOP_REVISION=<n> marker`).toBe(
      true,
    );
  });

  test("vendored copy is NOT registered in plugins/soleur/hooks/hooks.json (payload only)", () => {
    // AC4: registration would fire the backstop from the plugin registry on
    // top of the repo-scoped SessionStart binding — double dispatch. The
    // resolver's plugin-cache glob is the delivery channel, not hooks.json.
    const commands = allCommands(readFileSync(PLUGIN_HOOKS_JSON, "utf8"));
    const registered = commands.filter((c) => c.includes("memory-backstop"));
    expect(
      registered,
      `memory-backstop must stay unregistered in hooks.json (payload-only delivery); found: ${registered}`,
    ).toEqual([]);
  });

  test("vendored lib/log-rotation.sh exists and is byte-identical to .claude/hooks/lib/log-rotation.sh", () => {
    // The hook sources $(dirname BASH_SOURCE)/lib/log-rotation.sh
    // opportunistically — a plugin-cache winner without the sibling runs with
    // NO ledger rotation (unbounded .memory-backstop.jsonl growth), and the
    // resolver's publish_carry_lib can only carry a file that exists next to
    // the winner. Absence is a violation, not a skip (PR #9241 review).
    const vendoredLib = join(
      REPO_ROOT,
      "plugins",
      "soleur",
      "hooks",
      "lib",
      "log-rotation.sh",
    );
    const repoLib = join(REPO_ROOT, ".claude", "hooks", "lib", "log-rotation.sh");
    expect(
      existsSync(vendoredLib),
      "vendored lib/log-rotation.sh missing — vendor it: " +
        "cp .claude/hooks/lib/log-rotation.sh plugins/soleur/hooks/lib/",
    ).toBe(true);
    if (existsSync(vendoredLib)) {
      expect(
        readFileSync(vendoredLib).equals(readFileSync(repoLib)),
        "vendored log-rotation.sh drifted from .claude/hooks/lib/ — re-vendor with `cp`",
      ).toBe(true);
    }
  });
});

describe("Guard 3 — settings.json SessionStart binds the resolver, never the hook", () => {
  const settingsText = readFileSync(SETTINGS_JSON, "utf8");

  test("settings.json parses and declares a non-empty SessionStart hook list", () => {
    // JSON.parse throws on a malformed file (test fails), and a missing or
    // emptied SessionStart array is a violation — the backstop entry cannot
    // silently disappear inside a deleted event (matrix row 2's other half).
    const groups = JSON.parse(settingsText)?.hooks?.SessionStart;
    expect(Array.isArray(groups) && groups.length > 0).toBe(true);
  });

  test("a LIVE-matcher SessionStart command invokes memory-backstop-resolve.sh", () => {
    // Matcher-aware: a resolver entry parked under a dead matcher (e.g.
    // `"matcher": "never"`) must NOT satisfy this guard — it would parse as
    // wired while never firing (PR #9241 review). The command must also be
    // bash-prefixed (mode-bit immunity, #7151), not merely name the file.
    const registry = JSON.parse(settingsText);
    const groups: HookGroup[] = registry?.hooks?.SessionStart ?? [];
    const SOURCES = ["startup", "resume", "clear", "compact"];
    const live = groups.filter((g) =>
      SOURCES.every((s) => (g.matcher ?? "").split("|").includes(s)),
    );
    const liveCommands = live.flatMap((g) => (g.hooks ?? []).map((h) => h.command ?? ""));
    const resolvers = liveCommands.filter((c) => /\bbash\s.*memory-backstop-resolve\.sh/.test(c));
    expect(
      resolvers.length,
      "no SessionStart command under a live (startup|resume|clear|compact-covering) matcher " +
        "bash-invokes memory-backstop-resolve.sh — the backstop entry is missing, dead-matchered, " +
        "or never re-pointed at the resolver (#9239)",
    ).toBeGreaterThanOrEqual(1);
  });

  test("no SessionStart command invokes memory-backstop.sh directly", () => {
    // A reverted/bypassing registration restores checkout-pinned dispatch —
    // the exact defect this change exists to close. The resolver's own
    // filename (memory-backstop-resolve.sh) does not contain this token.
    const commands = eventCommands(settingsText, "SessionStart");
    const direct = commands.filter((c) => c.includes("memory-backstop.sh"));
    expect(
      direct,
      `SessionStart still invokes memory-backstop.sh directly — re-point it at ` +
        `the resolver; found: ${direct}`,
    ).toEqual([]);
  });

  test("the resolver the wiring names actually exists on disk", () => {
    // A dangling settings entry is wiring that points at nothing — distinct
    // from the hook itself, which may legitimately be absent pre-resolution.
    expect(
      existsSync(RESOLVER),
      "settings.json binds .claude/hooks/memory-backstop-resolve.sh but the file does not exist",
    ).toBe(true);
  });
});
