import { describe, it, expect, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, basename, resolve } from "node:path";
import { buildAgentEnv } from "../server/agent-env";

// Guard: every plugin Stop hook is classified for the web runtime.
//
// The web Concierge loads the plugin's hooks.json (SDK `plugins:[{type:"local"}]`;
// `settingSources:[]` does not exclude it), so an operator-CLI Stop hook runs
// against end users and can steer the model into leaking internal vocabulary
// (`<stop>OPERATOR-GATE...` replacing a CRM question list). Scope: the `Stop`
// event only — it is the one event that can force an extra model turn and
// rewrite the visible reply. See the ADR-093 amendment (2026-09-30).
//
// The population is DERIVED from hooks.json; the registry below classifies it.
// Behaviour, not the label, is the anchor: `web-safe` hooks are spawned with NO
// opt-out env, `web-disabled` hooks with the env buildAgentEnv really produces.

const REPO_ROOT = resolve(__dirname, "../../..");
const HOOKS_JSON = join(REPO_ROOT, "plugins/soleur/hooks/hooks.json");
const HOOKS_DIR = join(REPO_ROOT, "plugins/soleur/hooks");

type Classification =
  | { kind: "web-safe"; why: string }
  | { kind: "web-disabled"; optOutVar: string }
  | { kind: "deferred"; issue: string };

const REGISTRY: Record<string, Classification> = {
  // Acts only on `.claude/ralph-loop.<PPID>.local.md` state files that a web
  // workspace never has; spawned in a fresh temp git repo below.
  "stop-hook.sh": { kind: "web-safe", why: "no ralph-loop state file in a web workspace" },
  "unkept-promise-hook.sh": { kind: "web-disabled", optOutVar: "SOLEUR_DISABLE_UNKEPT_PROMISE_HOOK" },
  // Kills host Chrome processes; whether that can reach another tenant is unverified.
  "browser-cleanup-hook.sh": { kind: "deferred", issue: "#9281" },
};

// The incident's closing, and a differently-phrased promise, so a hook that
// allows one memorised string is not enough.
const CRM_CLOSING =
  "To enter the lead I need:\n- **lastContact**\n- **amount**, with **currency**\n\nYou can paste everything in one message. I'll show you a review before saving, and that review is the only confirmation step.";
const FORM_CLOSING = "Implementing the lead form now.";
const FIXTURES = [CRM_CLOSING, FORM_CLOSING];

function stopHookBasenames(): string[] {
  const parsed = JSON.parse(readFileSync(HOOKS_JSON, "utf8")) as {
    hooks: { Stop?: Array<{ hooks: Array<{ command: string }> }> };
  };
  return (parsed.hooks.Stop ?? []).flatMap((g) => g.hooks.map((h) => basename(h.command)));
}

const scratch = mkdtempSync(join(tmpdir(), "stop-hook-parity-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

function cleanGitEnv(): Record<string, string | undefined> {
  const env: Record<string, string | undefined> = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith("GIT_")) env[k] = v;
  return env;
}
const REPO = join(scratch, "ws");
spawnSync("mkdir", ["-p", REPO]);
spawnSync("git", ["init", "-q", REPO], { env: cleanGitEnv() as unknown as NodeJS.ProcessEnv });

// Per-script spawn and SUT-marker counts. Only hooks that write the trace marker
// (`unkept-promise-hook.sh`) can be counted; `stop-hook.sh` writes none, so its
// rows rest on rc + verdict alone.
const spawnsBy: Record<string, number> = {};
const ranBy: Record<string, number> = {};

function runHook(script: string, message: string, env: Record<string, string | undefined>): { blocked: boolean; rc: number | null } {
  spawnsBy[script] = (spawnsBy[script] ?? 0) + 1;
  const r = spawnSync("bash", [join(HOOKS_DIR, script)], {
    cwd: REPO,
    input: JSON.stringify({ last_assistant_message: message, stop_hook_active: false, session_id: "parity" }),
    env: { ...env, SOLEUR_HOOK_TRACE: "1" } as unknown as NodeJS.ProcessEnv,
    encoding: "utf8",
    timeout: 20_000,
  });
  if (/^SOLEUR_HOOK_RAN$/m.test(r.stderr ?? "")) ranBy[script] = (ranBy[script] ?? 0) + 1;
  let blocked = false;
  try {
    blocked = JSON.parse(r.stdout || "{}").decision === "block";
  } catch {
    blocked = /"decision"\s*:\s*"block"/.test(r.stdout ?? "");
  }
  return { blocked, rc: r.status };
}

// What the platform really hands the agent process, and the bare baseline.
const WEB_ENV = buildAgentEnv({ value: "sk-ant-test", scheme: "api_key" });
const BASE_ENV: Record<string, string | undefined> = { PATH: process.env.PATH, HOME: process.env.HOME };

describe("plugin Stop hooks are classified for the web runtime", () => {
  it("has bash and jq (hard failure, never a skip)", () => {
    expect(spawnSync("bash", ["--version"]).status).toBe(0);
    expect(spawnSync("jq", ["--version"]).status).toBe(0);
  });

  it("every registered Stop hook is classified, and the registry has no stale entry", () => {
    const parsed = stopHookBasenames();
    expect(parsed.length).toBeGreaterThanOrEqual(1);
    for (const name of parsed) {
      expect(REGISTRY, `Stop hook ${name} has no web classification`).toHaveProperty(name);
    }
    for (const key of Object.keys(REGISTRY)) {
      expect(parsed, `registry entry ${key} matches no Stop hook`).toContain(key);
    }
  });

  it("deferred entries cite an issue number", () => {
    for (const [name, c] of Object.entries(REGISTRY)) {
      if (c.kind === "deferred") expect(c.issue, name).toMatch(/^#\d+$/);
    }
  });

  for (const [name, c] of Object.entries(REGISTRY)) {
    if (c.kind === "web-safe") {
      it(`${name} (web-safe) does not block either closing with no opt-out env`, () => {
        for (const msg of FIXTURES) {
          const r = runHook(name, msg, BASE_ENV);
          expect(r.rc).toBe(0);
          expect(r.blocked, msg).toBe(false);
        }
      });
    }
    if (c.kind === "web-disabled") {
      it(`${name} (web-disabled): buildAgentEnv sets ${c.optOutVar}=1`, () => {
        expect(WEB_ENV[c.optOutVar]).toBe("1");
      });
      it(`${name} (web-disabled) allows both closings under the web env`, () => {
        for (const msg of FIXTURES) {
          const r = runHook(name, msg, { ...BASE_ENV, ...WEB_ENV });
          expect(r.rc).toBe(0);
          expect(r.blocked, msg).toBe(false);
        }
      });
      it(`${name} still blocks both closings without the opt-out (the hook is real)`, () => {
        for (const msg of FIXTURES) {
          expect(runHook(name, msg, BASE_ENV).blocked, msg).toBe(true);
        }
      });
    }
  }

  it("the web-disabled hooks themselves ran (SUT-written floor, not a harness counter)", () => {
    // 4 spawns of the web-disabled hook (2 fixtures x {web env, bare env}). A test
    // that never spawns it cannot satisfy this: only the hook writes the marker.
    for (const [name, c] of Object.entries(REGISTRY)) {
      if (c.kind !== "web-disabled") continue;
      expect(spawnsBy[name] ?? 0, name).toBeGreaterThanOrEqual(4);
      expect(ranBy[name] ?? 0, name).toBe(spawnsBy[name]);
    }
  });
});
