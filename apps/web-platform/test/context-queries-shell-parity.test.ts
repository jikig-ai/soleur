// Cross-language note-parity guard (#6046, ADR-086). The `context_queries` note
// TEMPLATE (wording/structure) lives in two hand-maintained copies — the CLI
// shell hook `.claude/hooks/skill-context-queries.sh` (jq pipeline) and the web
// JS hook `server/context-queries-hook.ts`. Unlike phase-surface (which shares a
// DATA map), this hook shares NO data with the shell — only the note wording. So
// this test asserts the TS hook's `additionalContext` is byte-equal to the real
// shell hook's output for the note shapes (resolved / 0-resolved / skipped),
// reusing the SAME committed git fixture the unit test builds (one shared helper,
// not a second harness — deepen-plan simplicity finding).
//
// Best-effort on the toolchain: if bash/jq/git are absent (a minimal node shard),
// the suite skips loudly rather than reddening — it runs in every environment
// with the bash+jq+git toolchain (local dev + the bash-hooks CI runner).
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

// Keep the observability import inert (the JS hook imports it transitively).
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import { createContextQueriesHook } from "../server/context-queries-hook";
import { buildFixture, cleanupFixture } from "./helpers/context-queries-fixture";

function findRepoRoot(start: string): string {
  let dir = start;
  for (let i = 0; i < 20; i++) {
    if (existsSync(path.join(dir, ".claude", "hooks", "skill-context-queries.sh"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error("context-queries-shell-parity: could not locate the CLI hook from " + start);
}

const REPO_ROOT = findRepoRoot(__dirname);
const HOOK = path.join(REPO_ROOT, ".claude", "hooks", "skill-context-queries.sh");

function toolchainReady(): boolean {
  try {
    execFileSync("bash", ["-c", "command -v jq >/dev/null && command -v git >/dev/null"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

const ready = toolchainReady();

let FIX: string;
let jsHook: ReturnType<typeof createContextQueriesHook>;

function shellNote(fix: string, skill: string): string {
  const stdout = execFileSync("bash", [HOOK], {
    input: JSON.stringify({ tool_name: "Skill", tool_input: { skill } }),
    encoding: "utf-8",
    env: { ...process.env, CONTEXT_QUERIES_REPO_ROOT: fix, SOLEUR_DISABLE_CONTEXT_QUERIES: "" },
  });
  // The shell hook emits nothing on a fast-exit; parity cases always declare.
  return JSON.parse(stdout).hookSpecificOutput.additionalContext as string;
}

async function jsNote(skill: string): Promise<string> {
  const out = (await jsHook(
    { hook_event_name: "PostToolUse", tool_name: "Skill", tool_input: { skill }, tool_response: null, tool_use_id: "t" } as never,
    "t",
    { signal: new AbortController().signal } as never,
  )) as { hookSpecificOutput: { additionalContext: string } };
  return out.hookSpecificOutput.additionalContext;
}

// The whole block is skipped when the toolchain is absent (skipIf), so the
// non-blocking skip is reported by vitest itself; a `beforeAll` warn guard would
// be dead code (beforeAll never runs under skipIf). One console.warn at collection
// time keeps the skip visible without a dead runtime branch.
if (!ready) {
  console.warn("context-queries-shell-parity: bash/jq/git unavailable — skipping shell↔JS note parity.");
}

describe.skipIf(!ready)("shell ↔ JS context-queries note byte-parity (#6046)", () => {
  beforeAll(() => {
    FIX = buildFixture();
    jsHook = createContextQueriesHook(FIX);
  });
  afterAll(() => {
    if (FIX) cleanupFixture(FIX);
  });

  // One skill per note shape. Byte-equality proves the note template — including
  // EVERY hand-maintained skip-reason fragment — is identical across the two
  // hand-ported copies. Covers: resolved-only, 0-resolved-clean,
  // 0-resolved+skipped, resolved+skipped, MAX_GLOB cap, per-match symlink reject,
  // and the out-of-tree traversal rejection.
  for (const [shape, skill] of [
    ["resolved", "with-query"],
    ["0-resolved (clean)", "empty-query"],
    ["0-resolved + skipped", "missing-art"],
    ["resolved + skipped", "mixed-query"],
    ["MAX_GLOB cap", "many-query"],
    ["per-match symlink reject", "symlink-query"],
    ["out-of-tree traversal reject", "traversal"],
  ] as const) {
    it(`emits a byte-identical note for the ${shape} shape (${skill})`, async () => {
      expect(await jsNote(skill)).toBe(shellNote(FIX, skill));
    });
  }
});
