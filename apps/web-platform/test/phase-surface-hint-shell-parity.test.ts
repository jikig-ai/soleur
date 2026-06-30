// Cross-language format-parity guard (#5772, review M2). The hint TEMPLATE
// (wording/structure) lives in two hand-maintained copies — the CLI shell hook
// `.claude/hooks/phase-surface-hint.sh` (jq pipeline) and the web JS hook
// `server/phase-surface-hook.ts`. The map-data parity test guards the DATA; this
// guards the FORMAT: it runs the actual shell hook and asserts byte-equality with
// the JS hook's `additionalContext` for every phase. A wording edit to either
// side that the other doesn't mirror fails here (FR4 byte-parity).
//
// Best-effort on the toolchain: if bash or jq is absent (a minimal node shard),
// the suite skips with a loud warning rather than reddening — it runs in every
// environment that has the bash+jq toolchain (local dev + the bash-hooks CI runner).
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { beforeAll, describe, expect, it } from "vitest";
import { createPhaseSurfaceHook } from "../server/phase-surface-hook";

function findRepoRoot(start: string): string {
  let dir = start;
  for (let i = 0; i < 20; i++) {
    if (existsSync(path.join(dir, ".claude", "hooks", "phase-surface-hint.sh"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error("phase-surface-hint-shell-parity: could not locate the CLI hook from " + start);
}

const REPO_ROOT = findRepoRoot(__dirname);
const HOOK = path.join(REPO_ROOT, ".claude", "hooks", "phase-surface-hint.sh");

function toolchainReady(): boolean {
  try {
    execFileSync("bash", ["-c", "command -v jq >/dev/null"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function shellHint(fqnSkill: string): string {
  const stdout = execFileSync("bash", [HOOK], {
    input: JSON.stringify({ tool_name: "Skill", tool_input: { skill: fqnSkill } }),
    encoding: "utf-8",
    env: { ...process.env, SOLEUR_DISABLE_PHASE_HINT: "" },
  });
  return JSON.parse(stdout).hookSpecificOutput.additionalContext as string;
}

const jsHook = createPhaseSurfaceHook();
async function jsHint(skill: string): Promise<string> {
  const out = (await jsHook(
    { hook_event_name: "PostToolUse", tool_name: "Skill", tool_input: { skill }, tool_response: null, tool_use_id: "t" } as never,
    "t",
    { signal: new AbortController().signal } as never,
  )) as { hookSpecificOutput: { additionalContext: string } };
  return out.hookSpecificOutput.additionalContext;
}

const ready = toolchainReady();
describe.skipIf(!ready)("shell ↔ JS phase-surface hint format parity (FR4)", () => {
  beforeAll(() => {
    if (!ready) console.warn("phase-surface-hint-shell-parity: bash/jq unavailable — skipping shell↔JS parity (DATA parity still guarded by phase-surface-map-parity).");
  });

  // One FQN skill per phase (the shell hook is FQN-keyed; the JS hook accepts FQN
  // and normalizes bare→FQN, so passing FQN exercises the shared template path).
  for (const skill of ["soleur:brainstorm", "soleur:plan", "soleur:work", "soleur:review", "soleur:ship"]) {
    it(`emits a byte-identical hint for ${skill}`, async () => {
      expect(await jsHint(skill)).toBe(shellHint(skill));
    });
  }
});
